package application

import (
	"blackbook/backend/internal/domain"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"sort"
	"strings"
	"sync"
	"time"
)

type Worker struct {
	S       *Service
	mu      sync.Mutex
	wg      sync.WaitGroup
	running map[string]context.CancelFunc
	live    map[string]int
}

func (w *Worker) Run(ctx context.Context) {
	defer w.wg.Wait()
	w.running = map[string]context.CancelFunc{}
	w.live = map[string]int{}
	timer := time.NewTicker(time.Second)
	defer timer.Stop()
	for {
		select {
		case <-ctx.Done():
			w.mu.Lock()
			for _, cancel := range w.running {
				cancel()
			}
			w.mu.Unlock()
			return
		case <-timer.C:
			w.tick(ctx)
		}
	}
}
func (w *Worker) tick(ctx context.Context) {
	c, err := w.S.Config()
	if err != nil {
		return
	}
	var tasks []domain.Task
	if w.S.DB.List(&tasks, nil) != nil {
		return
	}
	now := time.Now()
	gpu, notes := 0, 0
	for _, t := range tasks {
		w.mu.Lock()
		cancel, local := w.running[t.ID]
		w.mu.Unlock()
		if t.Status == "stopping" && local {
			cancel()
		}
		if (t.Status == "running" || t.Status == "stopping") && !local && t.Lease.Before(now) {
			_ = w.S.DB.Atomic(func(tx domain.Store) error {
				var current domain.Task
				if e := tx.Get(&current, map[string]any{"id": t.ID}); e != nil {
					return e
				}
				if current.Lease.Before(now) {
					if current.Status == "stopping" {
						current.Status = "stopped"
					} else if current.Status == "running" {
						current.Status = "queued"
					}
					return tx.Save(&current)
				}
				return nil
			})
			continue
		}
		if local {
			if t.Kind == "note" {
				notes++
			} else {
				gpu++
			}
			continue
		}
		if t.Status == "waiting_config" && c.OpenAIKey != "" && c.Model != "" {
			t.Status = "queued"
			w.S.DB.Save(&t)
		}
	}
	// Submit realtime work before queued offline inference. Each recording has one live task.
	var recordings []domain.Recording
	w.S.DB.List(&recordings, map[string]any{"status": "recording", "deleted": false})
	if gpu < c.GPULimit {
		for _, r := range recordings {
			chunks, e := w.S.Chunks(r.ID)
			if e != nil || len(chunks) == 0 {
				continue
			}
			contiguous := 0
			for i, ch := range chunks {
				if ch.Seq != i {
					break
				}
				contiguous++
			}
			id := r.ID + "-live"
			w.mu.Lock()
			_, busy := w.running[id]
			w.mu.Unlock()
			if busy {
				continue
			}
			t := domain.Task{ID: id, RecordingID: r.ID, Kind: "live", Status: "queued", CreatedAt: now}
			var previous domain.Task
			if w.S.DB.Get(&previous, map[string]any{"id": id}) == nil {
				if previous.Status == "stopped" || previous.Status == "stopping" || previous.Status == "failed" {
					continue
				}
				t.Checkpoint = previous.Checkpoint
				t.Attempts = previous.Attempts
			}
			if contiguous-t.Checkpoint < 3 {
				continue
			}
			w.S.DB.Save(&t)
			w.live[r.ID] = contiguous
			w.launch(ctx, t)
			gpu++
			if gpu >= c.GPULimit {
				break
			}
		}
	}
	sort.Slice(tasks, func(i, j int) bool { return tasks[i].CreatedAt.Before(tasks[j].CreatedAt) })
	for _, t := range tasks {
		if t.Status != "queued" || t.Kind == "live" {
			continue
		}
		if t.Kind == "note" {
			if notes >= c.NoteLimit {
				continue
			}
			notes++
		} else {
			if gpu >= c.GPULimit {
				continue
			}
			gpu++
		}
		w.launch(ctx, t)
	}
}
func (w *Worker) launch(parent context.Context, t domain.Task) {
	ctx, cancel := context.WithCancel(parent)
	w.mu.Lock()
	if _, ok := w.running[t.ID]; ok {
		w.mu.Unlock()
		cancel()
		return
	}
	w.running[t.ID] = cancel
	w.mu.Unlock()
	w.wg.Add(1)
	go func() {
		defer w.wg.Done()
		defer func() { cancel(); w.mu.Lock(); delete(w.running, t.ID); w.mu.Unlock() }()
		err := w.S.DB.Atomic(func(tx domain.Store) error {
			var current domain.Task
			if e := tx.Get(&current, map[string]any{"id": t.ID}); e != nil {
				return e
			}
			if current.Status != "queued" {
				return errors.New("task not queued")
			}
			t = current
			t.Status = "running"
			t.Attempts++
			t.Lease = time.Now().Add(30 * time.Second)
			return tx.Save(&t)
		})
		if err != nil {
			return
		}
		heartbeatDone := make(chan struct{})
		go func() {
			defer close(heartbeatDone)
			timer := time.NewTicker(5 * time.Second)
			defer timer.Stop()
			for {
				select {
				case <-ctx.Done():
					return
				case <-timer.C:
					_ = w.S.DB.Atomic(func(tx domain.Store) error {
						var current domain.Task
						if e := tx.Get(&current, map[string]any{"id": t.ID}); e != nil {
							return e
						}
						if current.Status == "stopping" {
							cancel()
							return nil
						}
						current.Lease = time.Now().Add(30 * time.Second)
						return tx.Save(&current)
					})
				}
			}
		}()
		err = w.execute(ctx, &t)
		cancel()
		<-heartbeatDone
		_ = w.S.DB.Atomic(func(tx domain.Store) error {
			var current domain.Task
			if e := tx.Get(&current, map[string]any{"id": t.ID}); e != nil {
				return e
			}
			current.Snapshot = t.Snapshot
			current.Checkpoint = t.Checkpoint
			current.Lease = time.Time{}
			if current.Status == "stopping" || errors.Is(err, context.Canceled) {
				current.Status = "stopped"
			} else if err != nil {
				current.Error = err.Error()
				if errors.Is(err, errConfig) {
					current.Status = "waiting_config"
				} else if current.Attempts < 3 {
					current.Status = "queued"
				} else {
					current.Status = "failed"
				}
			} else {
				current.Status = "succeeded"
				current.Error = ""
				current.Progress = 1
				if current.Kind == "live" {
					current.Attempts = 0
				}
			}
			return tx.Save(&current)
		})
	}()
}

var errConfig = errors.New("请配置 OpenAI API key 和模型")

func (w *Worker) execute(ctx context.Context, t *domain.Task) error {
	s := w.S
	if t.Kind == "cleanup" {
		var r domain.Recording
		if e := s.DB.Get(&r, map[string]any{"id": t.RecordingID}); e != nil {
			return e
		}
		var tasks []domain.Task
		s.DB.List(&tasks, map[string]any{"recording_id": r.ID})
		for _, other := range tasks {
			if other.ID != t.ID && (other.Status == "running" || other.Status == "stopping") {
				return errors.New("等待关联任务停止")
			}
		}
		if e := os.Remove(r.Path); e != nil && !os.IsNotExist(e) {
			return e
		}
		chunks, e := s.Chunks(r.ID)
		if e != nil {
			return e
		}
		for _, ch := range chunks {
			if e = os.Remove(ch.Path); e != nil && !os.IsNotExist(e) {
				return e
			}
		}
		for _, model := range []any{&domain.Chunk{}, &domain.Segment{}, &domain.Event{}, &domain.Note{}} {
			if e = s.DB.Delete(model, map[string]any{"recording_id": r.ID}); e != nil {
				return e
			}
		}
		return nil
	}
	r, err := s.Recording(t.RecordingID)
	if err != nil {
		return err
	}
	c, err := s.Config()
	if err != nil {
		return err
	}
	if t.Kind == "transcribe" || t.Kind == "live" {
		var segments []domain.Segment
		if t.Kind == "live" {
			chunks, e := s.Chunks(r.ID)
			if e != nil {
				return e
			}
			var pcm bytes.Buffer
			var offset int64
			checkpoint := t.Checkpoint
			for i, ch := range chunks {
				if ch.Seq != i {
					break
				}
				if i < t.Checkpoint {
					offset += ch.Samples
					continue
				}
				b, e := os.ReadFile(ch.Path)
				if e != nil {
					return e
				}
				pcm.Write(b)
				checkpoint = i + 1
			}
			wav := append(WAVHeader(int64(pcm.Len()/2)), pcm.Bytes()...)
			segments, err = s.Audio.Transcribe(ctx, c, r.ID, bytes.NewReader(wav), false, offset)
			if err != nil && strings.Contains(err.Error(), "replay_required") {
				t.Checkpoint = 0
			}
			if err == nil {
				t.Checkpoint = checkpoint
			}
		} else {
			f, e := os.Open(r.Path)
			if e != nil {
				return e
			}
			defer f.Close()
			segments, err = s.Audio.Transcribe(ctx, c, r.ID, f, true, 0)
		}
		if err != nil {
			return err
		}
		if ctx.Err() != nil {
			return ctx.Err()
		}
		if err = s.SaveSegments(r.ID, segments, t.Kind != "live", t.ID); err != nil {
			return err
		}
		if t.Kind == "transcribe" {
			return s.DB.Atomic(func(tx domain.Store) error {
				var task domain.Task
				if e := tx.Get(&task, map[string]any{"id": t.ID, "status": "running"}); e != nil {
					return context.Canceled
				}
				var current domain.Recording
				if e := tx.Get(&current, map[string]any{"id": r.ID, "deleted": false}); e != nil {
					return e
				}
				current.Status = "transcribed"
				if e := tx.Save(&current); e != nil {
					return e
				}
				var existing domain.Task
				if tx.Get(&existing, map[string]any{"id": r.ID + "-note"}) == nil {
					return nil
				}
				return tx.Save(&domain.Task{ID: r.ID + "-note", RecordingID: r.ID, Kind: "note", Status: "queued", CreatedAt: time.Now()})
			})
		}
		return nil
	}
	if t.Kind != "note" {
		return errors.New("未知任务类型")
	}
	if c.OpenAIKey == "" || c.Model == "" {
		return errConfig
	}
	// Persist prompt/config snapshot without credentials; retries keep the original instructions.
	if t.Snapshot != "" {
		key := c.OpenAIKey
		if err = json.Unmarshal([]byte(t.Snapshot), &c); err != nil {
			return err
		}
		c.OpenAIKey = key
	} else {
		var course domain.Course
		if err = s.DB.Get(&course, map[string]any{"id": r.CourseID}); err != nil {
			return err
		}
		c.NotePrompt += "\n课程：" + course.Name + "\n" + course.Prompt
		snap := c
		snap.OpenAIKey = ""
		snap.AudioKey = ""
		b, _ := json.Marshal(snap)
		t.Snapshot = string(b)
		if err = s.DB.Atomic(func(tx domain.Store) error {
			var current domain.Task
			if e := tx.Get(&current, map[string]any{"id": t.ID}); e != nil {
				return e
			}
			current.Snapshot = t.Snapshot
			return tx.Save(&current)
		}); err != nil {
			return err
		}
	}
	var segments []domain.Segment
	if err = s.DB.List(&segments, map[string]any{"recording_id": r.ID, "final": true}); err != nil {
		return err
	}
	sort.Slice(segments, func(i, j int) bool { return segments[i].Start < segments[j].Start })
	var transcript strings.Builder
	for _, p := range segments {
		fmt.Fprintf(&transcript, "[%.1fs–%.1fs] %s: %s\n", p.Start, p.End, p.Speaker, p.Text)
	}
	if transcript.Len() == 0 {
		return errors.New("没有可整理的最终转写")
	}
	text, err := s.Notes.Generate(ctx, c, transcript.String())
	if err != nil {
		return err
	}
	if ctx.Err() != nil {
		return ctx.Err()
	}
	return s.DB.Atomic(func(tx domain.Store) error {
		var task domain.Task
		if e := tx.Get(&task, map[string]any{"id": t.ID, "status": "running"}); e != nil {
			return context.Canceled
		}
		var current domain.Recording
		if e := tx.Get(&current, map[string]any{"id": r.ID, "deleted": false}); e != nil {
			return e
		}
		var existing domain.Note
		if tx.Get(&existing, map[string]any{"id": t.ID}) != nil {
			if e := tx.Save(&domain.Note{ID: t.ID, RecordingID: r.ID, Markdown: text, CreatedAt: time.Now()}); e != nil {
				return e
			}
		}
		current.Status = "ready"
		return tx.Save(&current)
	})
}
