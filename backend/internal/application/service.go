package application

import (
	"blackbook/backend/internal/domain"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/google/uuid"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"
)

type Service struct {
	DB    domain.Store
	Root  string
	Audio domain.AudioService
	Notes domain.NoteService
	mu    sync.Mutex
}

func New(db domain.Store, root string, a domain.AudioService, n domain.NoteService) (*Service, error) {
	if err := os.MkdirAll(root, 0700); err != nil {
		return nil, err
	}
	s := &Service{DB: db, Root: root, Audio: a, Notes: n}
	var c domain.Config
	if db.Get(&c, map[string]any{"id": 1}) != nil {
		c = domain.Config{ID: 1, AudioURL: "http://127.0.0.1:8091", OpenAIURL: "https://api.openai.com/v1", Protocol: "chat", GPULimit: 1, NoteLimit: 2, InputBudget: 12000, NotePrompt: "请基于课堂原文整理中文 Markdown 笔记：概述、知识点、公式/例题、作业事项，保留时间戳。不确定内容明确标记，不编造。"}
		if err := db.Save(&c); err != nil {
			return nil, err
		}
	}
	var misc domain.Course
	if db.Get(&misc, map[string]any{"id": "misc"}) != nil {
		misc = domain.Course{ID: "misc", Name: "misc", Directory: "misc"}
		if err := db.Save(&misc); err != nil {
			return nil, err
		}
	}
	return s, nil
}
func (s *Service) Config() (domain.Config, error) {
	var c domain.Config
	err := s.DB.Get(&c, map[string]any{"id": 1})
	return c, err
}
func (s *Service) Recording(id string) (domain.Recording, error) {
	var r domain.Recording
	err := s.DB.Get(&r, map[string]any{"id": id, "deleted": false})
	return r, err
}

var invalidName = regexp.MustCompile(`[<>:"/\\|?*\x00-\x1f]`)

func SafeName(name string) string {
	name = strings.Trim(invalidName.ReplaceAllString(name, "_"), " .")
	if name == "" {
		name = "course"
	}
	r := []rune(name)
	if len(r) > 80 {
		name = string(r[:80])
	}
	// Prefix also handles reserved Windows device names (CON, AUX, COM1...).
	upper := strings.ToUpper(strings.Split(name, ".")[0])
	if upper == "CON" || upper == "PRN" || upper == "AUX" || upper == "NUL" || regexp.MustCompile(`^(COM|LPT)[0-9]$`).MatchString(upper) {
		name = "_" + name
	}
	return name
}
func (s *Service) CreateCourse(c *domain.Course) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if c.ID == "" {
		c.ID = uuid.NewString()
	}
	if _, e := uuid.Parse(c.ID); e != nil {
		return errors.New("课程 ID 必须为 UUID")
	}
	c.Directory = SafeName(c.Name) + "-" + c.ID[:8]
	var existing domain.Course
	if s.DB.Get(&existing, map[string]any{"id": c.ID}) == nil {
		return errors.New("课程 ID 已存在")
	}
	return s.DB.Save(c)
}
func (s *Service) CreateRecording(r *domain.Recording) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if r.ID == "" {
		r.ID = uuid.NewString()
	}
	if _, err := uuid.Parse(r.ID); err != nil {
		return errors.New("录音 ID 必须为 UUID")
	}
	var existing domain.Recording
	if s.DB.Get(&existing, map[string]any{"id": r.ID}) == nil {
		if existing.Deleted || existing.CourseID != r.CourseID {
			return errors.New("录音 ID 冲突")
		}
		*r = existing
		return nil
	}
	var c domain.Course
	if err := s.DB.Get(&c, map[string]any{"id": r.CourseID, "deleted": false}); err != nil {
		return err
	}
	if r.StartedAt.IsZero() {
		r.StartedAt = time.Now()
	}
	r.Status = "recording"
	r.Samples = 0
	r.TotalChunks = 0
	dir := filepath.Join(s.Root, c.Directory)
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	// Reserve filenames with O_EXCL. Reservations survive crashes, so names are never reused.
	date := r.StartedAt.In(time.FixedZone("Asia/Shanghai", 8*3600)).Format("2006-01-02")
	for i := 1; ; i++ {
		r.Path = filepath.Join(dir, fmt.Sprintf("%s-%d.wav", date, i))
		f, err := os.OpenFile(r.Path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
		if os.IsExist(err) {
			continue
		}
		if err != nil {
			return err
		}
		f.Close()
		break
	}
	return s.DB.Save(r)
}
func (s *Service) AddChunk(id string, seq int, hash string, data []byte) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if seq < 0 || seq > 86400 || len(data) == 0 || len(data) > 320000 || len(data)%2 != 0 {
		return errors.New("无效 PCM 分块")
	}
	sum := sha256.Sum256(data)
	if hex.EncodeToString(sum[:]) != strings.ToLower(hash) {
		return errors.New("分块 SHA256 不匹配")
	}
	r, err := s.Recording(id)
	if err != nil {
		return err
	}
	var previous domain.Chunk
	if s.DB.Get(&previous, map[string]any{"recording_id": id, "seq": seq}) == nil {
		if previous.SHA256 != hash {
			return errors.New("相同序号内容冲突")
		}
		return nil
	}
	if r.Status != "recording" {
		return errors.New("录音已经完成")
	}
	dir := filepath.Join(s.Root, ".chunks", id)
	if err = os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	path := filepath.Join(dir, fmt.Sprintf("%08d.pcm", seq))
	tmp := path + ".tmp"
	f, err := os.OpenFile(tmp, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	_, err = f.Write(data)
	if err == nil {
		err = f.Sync()
	}
	f.Close()
	if err != nil {
		return err
	}
	if err = os.Rename(tmp, path); err != nil {
		return err
	}
	return s.DB.Save(&domain.Chunk{RecordingID: id, Seq: seq, Samples: int64(len(data) / 2), SHA256: hash, Path: path})
}
func (s *Service) Chunks(id string) ([]domain.Chunk, error) {
	var chunks []domain.Chunk
	err := s.DB.List(&chunks, map[string]any{"recording_id": id})
	sort.Slice(chunks, func(i, j int) bool { return chunks[i].Seq < chunks[j].Seq })
	return chunks, err
}
func WAVHeader(samples int64) []byte {
	b := make([]byte, 44)
	copy(b, "RIFF")
	binary.LittleEndian.PutUint32(b[4:], uint32(samples*2+36))
	copy(b[8:], "WAVEfmt ")
	binary.LittleEndian.PutUint32(b[16:], 16)
	binary.LittleEndian.PutUint16(b[20:], 1)
	binary.LittleEndian.PutUint16(b[22:], 1)
	binary.LittleEndian.PutUint32(b[24:], 16000)
	binary.LittleEndian.PutUint32(b[28:], 32000)
	binary.LittleEndian.PutUint16(b[32:], 2)
	binary.LittleEndian.PutUint16(b[34:], 16)
	copy(b[36:], "data")
	binary.LittleEndian.PutUint32(b[40:], uint32(samples*2))
	return b
}
func (s *Service) Complete(id string, total int) (domain.Recording, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	r, err := s.Recording(id)
	if err != nil {
		return r, err
	}
	if r.Status != "recording" {
		if total != r.TotalChunks {
			return r, errors.New("最终块数冲突")
		}
		return r, nil
	}
	chunks, err := s.Chunks(id)
	if err != nil {
		return r, err
	}
	if total < 1 || len(chunks) != total {
		return r, errors.New("音频缺块，不能完成")
	}
	var samples int64
	for i, c := range chunks {
		if c.Seq != i {
			return r, errors.New("音频序号不连续")
		}
		samples += c.Samples
	}
	if samples*2 > 0xffffffff-36 {
		return r, errors.New("WAV 超出 4GB 限制")
	}
	f, err := os.Create(r.Path + ".tmp")
	if err != nil {
		return r, err
	}
	defer f.Close()
	if _, err = f.Write(WAVHeader(samples)); err != nil {
		return r, err
	}
	for _, c := range chunks {
		data, e := os.ReadFile(c.Path)
		if e != nil {
			return r, e
		}
		sum := sha256.Sum256(data)
		if hex.EncodeToString(sum[:]) != c.SHA256 {
			return r, errors.New("磁盘分块校验失败")
		}
		if _, err = f.Write(data); err != nil {
			return r, err
		}
	}
	if err = f.Sync(); err != nil {
		return r, err
	}
	f.Close()
	if err = os.Rename(r.Path+".tmp", r.Path); err != nil {
		return r, err
	}
	r.Samples = samples
	r.TotalChunks = total
	r.Status = "processing"
	err = s.DB.Atomic(func(tx domain.Store) error {
		if e := tx.Save(&r); e != nil {
			return e
		}
		return tx.Save(&domain.Task{ID: id + "-transcribe", RecordingID: id, Kind: "transcribe", Status: "queued", CreatedAt: time.Now()})
	})
	return r, err
}
func (s *Service) UploadWAV(id string, reader io.Reader) (domain.Recording, error) {
	// Strict canonical WAV upload; arbitrary codecs are not silently interpreted as PCM.
	h := make([]byte, 44)
	if _, e := io.ReadFull(reader, h); e != nil {
		return domain.Recording{}, e
	}
	if string(h[:4]) != "RIFF" || string(h[8:16]) != "WAVEfmt " || binary.LittleEndian.Uint32(h[16:]) != 16 || binary.LittleEndian.Uint16(h[20:]) != 1 || binary.LittleEndian.Uint16(h[22:]) != 1 || binary.LittleEndian.Uint32(h[24:]) != 16000 || binary.LittleEndian.Uint16(h[34:]) != 16 || string(h[36:40]) != "data" {
		return domain.Recording{}, errors.New("仅接受规范 PCM16/16kHz/单声道 WAV")
	}
	remaining := int64(binary.LittleEndian.Uint32(h[40:]))
	seq := 0
	for remaining > 0 {
		n := min(remaining, 32000)
		b := make([]byte, n)
		if _, e := io.ReadFull(reader, b); e != nil {
			return domain.Recording{}, e
		}
		sum := sha256.Sum256(b)
		if e := s.AddChunk(id, seq, hex.EncodeToString(sum[:]), b); e != nil {
			return domain.Recording{}, e
		}
		seq++
		remaining -= n
	}
	return s.Complete(id, seq)
}
func (s *Service) SaveSegments(id string, segments []domain.Segment, final bool, taskID ...string) error {
	return s.DB.Atomic(func(tx domain.Store) error {
		if len(taskID) > 0 {
			var task domain.Task
			if e := tx.Get(&task, map[string]any{"id": taskID[0], "status": "running"}); e != nil {
				return e
			}
		}
		var r domain.Recording
		if err := tx.Get(&r, map[string]any{"id": id, "deleted": false}); err != nil {
			return err
		}
		// Replace the revised suffix, so overlapping inference windows cannot duplicate text.
		from := 0.0
		if !final {
			if len(segments) == 0 {
				return nil
			}
			from = segments[0].Start
			for _, p := range segments {
				if p.Start < from {
					from = p.Start
				}
			}
		}
		var previous []domain.Segment
		if e := tx.List(&previous, map[string]any{"recording_id": id}); e != nil {
			return e
		}
		for _, p := range previous {
			if final || (!p.Final && p.End > from) {
				if e := tx.Delete(&domain.Segment{}, map[string]any{"id": p.ID}); e != nil {
					return e
				}
			}
		}
		reset, _ := json.Marshal(map[string]any{"replace_from": from})
		if e := tx.Save(&domain.Event{RecordingID: id, Payload: string(reset)}); e != nil {
			return e
		}
		for _, p := range segments {
			p.RecordingID = id
			p.Final = final
			p.ID = id + "-" + p.ID
			var old domain.Segment
			tx.Get(&old, map[string]any{"id": p.ID})
			p.Version = old.Version + 1
			if e := tx.Save(&p); e != nil {
				return e
			}
			b, _ := json.Marshal(p)
			if e := tx.Save(&domain.Event{RecordingID: id, Payload: string(b)}); e != nil {
				return e
			}
		}
		return nil
	})
}
func (s *Service) DeleteRecording(id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.DB.Atomic(func(tx domain.Store) error { return deleteRecording(tx, id) })
}
func deleteRecording(tx domain.Store, id string) error {
	var r domain.Recording
	if e := tx.Get(&r, map[string]any{"id": id}); e != nil {
		return e
	}
	r.Deleted = true
	if e := tx.Save(&r); e != nil {
		return e
	}
	var tasks []domain.Task
	tx.List(&tasks, map[string]any{"recording_id": id})
	for _, t := range tasks {
		if t.Kind != "cleanup" {
			if t.Status == "running" {
				t.Status = "stopping"
			} else {
				t.Status = "stopped"
			}
			if e := tx.Save(&t); e != nil {
				return e
			}
		}
	}
	return tx.Save(&domain.Task{ID: id + "-cleanup", RecordingID: id, Kind: "cleanup", Status: "queued", CreatedAt: time.Now()})
}

func (s *Service) EditRecording(id string, edit func(*domain.Recording)) (domain.Recording, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var r domain.Recording
	err := s.DB.Atomic(func(tx domain.Store) error {
		if e := tx.Get(&r, map[string]any{"id": id, "deleted": false}); e != nil {
			return e
		}
		edit(&r)
		return tx.Save(&r)
	})
	return r, err
}
func (s *Service) DeleteCourse(id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if id == "misc" {
		return errors.New("不能删除 misc")
	}
	return s.DB.Atomic(func(tx domain.Store) error {
		var c domain.Course
		if e := tx.Get(&c, map[string]any{"id": id}); e != nil {
			return e
		}
		c.Deleted = true
		if e := tx.Save(&c); e != nil {
			return e
		}
		var records []domain.Recording
		if e := tx.List(&records, map[string]any{"course_id": id, "deleted": false}); e != nil {
			return e
		}
		for _, r := range records {
			if e := deleteRecording(tx, r.ID); e != nil {
				return e
			}
		}
		return tx.Delete(&domain.Occurrence{}, map[string]any{"course_id": id})
	})
}
