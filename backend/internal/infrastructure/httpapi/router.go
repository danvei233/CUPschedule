package httpapi

import (
	"blackbook/backend/internal/application"
	"blackbook/backend/internal/domain"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/gin-gonic/gin"
	"github.com/go-playground/validator/v10"
	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"io"
	"net/http"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"time"
)

type api struct {
	s        *application.Service
	validate *validator.Validate
}

func Router(s *application.Service, key string) *gin.Engine {
	r := gin.New()
	// Gin's default recovery dumps request headers, including a custom API key.
	r.Use(gin.RecoveryWithWriter(io.Discard))
	a := api{s: s, validate: validator.New()}
	r.Use(func(c *gin.Context) {
		if subtle.ConstantTimeCompare([]byte(c.GetHeader("X-API-Key")), []byte(key)) != 1 || key == "" {
			c.AbortWithStatusJSON(401, gin.H{"error": "invalid API key"})
			return
		}
		c.Next()
	})
	v := r.Group("/api/v1")
	v.GET("/health", func(c *gin.Context) { c.JSON(200, gin.H{"status": "ok"}) })
	v.GET("/semesters", func(c *gin.Context) { var rows []domain.Semester; respond(c, rows, a.s.DB.List(&rows, nil), &rows) })
	v.GET("/courses", a.courses)
	v.POST("/courses", a.createCourse)
	v.PATCH("/courses/:id", a.updateCourse)
	v.DELETE("/courses/:id", a.deleteCourse)
	v.POST("/schedule/sync", a.syncSchedule)
	v.GET("/recordings", func(c *gin.Context) {
		q := map[string]any{"deleted": false}
		if id := c.Query("course_id"); id != "" {
			q["course_id"] = id
		}
		var rows []domain.Recording
		respond(c, nil, s.DB.List(&rows, q), &rows)
	})
	v.POST("/recordings", func(c *gin.Context) {
		var in struct {
			ID        string    `json:"id"`
			CourseID  string    `json:"course_id"`
			Title     string    `json:"title"`
			StartedAt time.Time `json:"started_at"`
		}
		if !bind(c, &in) {
			return
		}
		record := domain.Recording{ID: in.ID, CourseID: in.CourseID, Title: in.Title, StartedAt: in.StartedAt}
		respond(c, nil, s.CreateRecording(&record), record)
	})
	v.GET("/recordings/:id", func(c *gin.Context) { r, e := s.Recording(c.Param("id")); respond(c, nil, e, r) })
	v.PATCH("/recordings/:id", func(c *gin.Context) {
		var in struct {
			Title        *string `json:"title"`
			Interrupted  *bool   `json:"interrupted"`
			CaptureError *string `json:"capture_error"`
			Gaps         *string `json:"gaps"`
		}
		if !bind(c, &in) {
			return
		}
		r, e := s.EditRecording(c.Param("id"), func(r *domain.Recording) {
			if in.Title != nil {
				r.Title = *in.Title
			}
			if in.Interrupted != nil {
				r.Interrupted = *in.Interrupted
			}
			if in.CaptureError != nil {
				r.CaptureError = *in.CaptureError
			}
			if in.Gaps != nil {
				r.Gaps = *in.Gaps
			}
		})
		respond(c, nil, e, r)
	})
	v.DELETE("/recordings/:id", func(c *gin.Context) { respond(c, nil, s.DeleteRecording(c.Param("id")), gin.H{"deleted": true}) })
	v.POST("/recordings/:id/chunks", a.chunk)
	v.GET("/recordings/:id/chunks", func(c *gin.Context) { rows, e := s.Chunks(c.Param("id")); respond(c, nil, e, gin.H{"chunks": rows}) })
	v.POST("/recordings/:id/complete", func(c *gin.Context) {
		var in struct {
			Total int `json:"total_chunks"`
		}
		if !bind(c, &in) {
			return
		}
		r, e := s.Complete(c.Param("id"), in.Total)
		respond(c, nil, e, r)
	})
	v.PUT("/recordings/:id/audio", func(c *gin.Context) {
		c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 2<<30)
		r, e := s.UploadWAV(c.Param("id"), c.Request.Body)
		respond(c, nil, e, r)
	})
	v.GET("/recordings/:id/audio", a.audio)
	v.HEAD("/recordings/:id/audio", a.audio)
	v.GET("/recordings/:id/stream", a.stream)
	v.GET("/recordings/:id/transcript", func(c *gin.Context) {
		var rows []domain.Segment
		e := s.DB.List(&rows, map[string]any{"recording_id": c.Param("id")})
		sort.Slice(rows, func(i, j int) bool { return rows[i].Start < rows[j].Start })
		respond(c, nil, e, rows)
	})
	v.PATCH("/recordings/:id/transcript/:segment", func(c *gin.Context) {
		var in struct {
			Text    *string `json:"text"`
			Speaker *string `json:"speaker"`
		}
		if !bind(c, &in) {
			return
		}
		var p domain.Segment
		if e := s.DB.Get(&p, map[string]any{"id": c.Param("segment"), "recording_id": c.Param("id")}); e != nil {
			fail(c, e)
			return
		}
		if in.Text != nil {
			p.Text = *in.Text
		}
		if in.Speaker != nil {
			p.Speaker = *in.Speaker
		}
		p.Version++
		respond(c, nil, s.DB.Save(&p), p)
	})
	v.GET("/notes", func(c *gin.Context) {
		var rows []domain.Note
		q := map[string]any{}
		if id := c.Query("recording_id"); id != "" {
			q["recording_id"] = id
		}
		respond(c, nil, s.DB.List(&rows, q), &rows)
	})
	v.POST("/notes", func(c *gin.Context) {
		var n domain.Note
		if !bind(c, &n) {
			return
		}
		if _, e := s.Recording(n.RecordingID); e != nil {
			fail(c, e)
			return
		}
		n.ID = uuid.NewString()
		n.Edited = true
		n.CreatedAt = time.Now()
		respond(c, nil, s.DB.Save(&n), n)
	})
	v.PATCH("/notes/:id", func(c *gin.Context) {
		var in struct {
			Markdown string `json:"markdown"`
		}
		if !bind(c, &in) {
			return
		}
		var n domain.Note
		if e := s.DB.Get(&n, map[string]any{"id": c.Param("id")}); e != nil {
			fail(c, e)
			return
		}
		n.Markdown = in.Markdown
		n.Edited = true
		respond(c, nil, s.DB.Save(&n), n)
	})
	v.DELETE("/notes/:id", func(c *gin.Context) {
		respond(c, nil, s.DB.Delete(&domain.Note{}, map[string]any{"id": c.Param("id")}), gin.H{"deleted": true})
	})
	v.GET("/tasks", func(c *gin.Context) { var rows []domain.Task; respond(c, nil, s.DB.List(&rows, nil), &rows) })
	v.POST("/tasks", func(c *gin.Context) {
		var in struct {
			RecordingID string `json:"recording_id"`
			Kind        string `json:"kind"`
		}
		if !bind(c, &in) {
			return
		}
		t, e := s.QueueReprocess(in.RecordingID, in.Kind)
		respond(c, nil, e, t)
	})
	v.POST("/tasks/:id/:action", a.taskAction)
	v.GET("/settings", func(c *gin.Context) {
		cfg, e := s.Config()
		has := cfg.OpenAIKey != ""
		audioHas := cfg.AudioKey != ""
		cfg.OpenAIKey = ""
		cfg.AudioKey = ""
		respond(c, nil, e, gin.H{"settings": cfg, "has_openai_key": has, "has_audio_key": audioHas})
	})
	v.PATCH("/settings", a.settings)
	v.POST("/settings/test", func(c *gin.Context) {
		cfg, e := s.Config()
		if e != nil {
			fail(c, e)
			return
		}
		out, e := s.Notes.Generate(c.Request.Context(), cfg, "请回复：连接成功")
		respond(c, nil, e, gin.H{"result": out})
	})
	v.GET("/audio-service", func(c *gin.Context) {
		cfg, e := s.Config()
		if e != nil {
			fail(c, e)
			return
		}
		out, e := s.Audio.Control(c.Request.Context(), cfg, "status")
		respond(c, nil, e, out)
	})
	v.POST("/audio-service/:action", func(c *gin.Context) {
		action := c.Param("action")
		if action != "load" && action != "unload" && action != "reload" {
			fail(c, errors.New("无效操作"))
			return
		}
		cfg, e := s.Config()
		if e != nil {
			fail(c, e)
			return
		}
		out, e := s.Audio.Control(c.Request.Context(), cfg, action)
		respond(c, nil, e, out)
	})
	return r
}
func bind(c *gin.Context, v any) bool {
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 4<<20)
	if e := c.ShouldBindJSON(v); e != nil {
		fail(c, e)
		return false
	}
	return true
}
func fail(c *gin.Context, e error) { c.JSON(400, gin.H{"error": e.Error()}) }
func respond(c *gin.Context, _ any, e error, v any) {
	if e != nil {
		fail(c, e)
	} else {
		c.JSON(200, v)
	}
}
func (a api) courses(c *gin.Context) {
	var rows []domain.Course
	q := map[string]any{"deleted": false}
	if id := c.Query("semester_id"); id != "" {
		q["semester_id"] = id
	}
	if e := a.s.DB.List(&rows, q); e != nil {
		fail(c, e)
		return
	}
	out := []gin.H{}
	for _, course := range rows {
		var recs []domain.Recording
		a.s.DB.List(&recs, map[string]any{"course_id": course.ID, "deleted": false})
		var samples int64
		for _, r := range recs {
			samples += r.Samples
		}
		out = append(out, gin.H{"course": course, "recording_count": len(recs), "duration_seconds": float64(samples) / 16000})
	}
	c.JSON(200, out)
}
func (a api) createCourse(c *gin.Context) {
	var row domain.Course
	if !bind(c, &row) {
		return
	}
	if e := a.validate.Struct(row); e != nil {
		fail(c, e)
		return
	}
	row.AutoRecord = true
	respond(c, nil, a.s.CreateCourse(&row), row)
}
func (a api) updateCourse(c *gin.Context) {
	var row domain.Course
	if e := a.s.DB.Get(&row, map[string]any{"id": c.Param("id"), "deleted": false}); e != nil {
		fail(c, e)
		return
	}
	var in struct {
		Name     *string `json:"name"`
		Teachers *string `json:"teachers"`
		Prompt   *string `json:"prompt"`
		Auto     *bool   `json:"auto_record"`
	}
	if !bind(c, &in) {
		return
	}
	if in.Name != nil {
		row.Name = *in.Name
	}
	if in.Teachers != nil {
		row.Teachers = *in.Teachers
	}
	if in.Prompt != nil {
		row.Prompt = *in.Prompt
	}
	if in.Auto != nil {
		row.AutoRecord = *in.Auto
	}
	if row.ID == "misc" {
		row.AutoRecord = false
	}
	if e := a.validate.Struct(row); e != nil {
		fail(c, e)
		return
	}
	respond(c, nil, a.s.DB.Save(&row), row)
}
func (a api) deleteCourse(c *gin.Context) {
	if c.Param("id") == "misc" {
		fail(c, errors.New("不能删除 misc"))
		return
	}
	var row domain.Course
	if e := a.s.DB.Get(&row, map[string]any{"id": c.Param("id")}); e != nil {
		fail(c, e)
		return
	}
	var recs []domain.Recording
	a.s.DB.List(&recs, map[string]any{"course_id": row.ID, "deleted": false})
	if c.Query("cascade") != "true" {
		c.JSON(409, gin.H{"error": "请确认级联删除", "recording_count": len(recs)})
		return
	}
	respond(c, nil, a.s.DeleteCourse(row.ID), gin.H{"deleted": true})
}
func (a api) syncSchedule(c *gin.Context) {
	var in struct {
		Semester    domain.Semester     `json:"semester"`
		Courses     []domain.Course     `json:"courses"`
		Occurrences []domain.Occurrence `json:"occurrences"`
	}
	if !bind(c, &in) {
		return
	}
	if in.Semester.ID == "" {
		fail(c, errors.New("学期 ID 不能为空"))
		return
	}
	e := a.s.DB.Atomic(func(tx domain.Store) error {
		if e := tx.Save(&in.Semester); e != nil {
			return e
		}
		for _, course := range in.Courses {
			if e := a.validate.Struct(course); e != nil {
				return e
			}
			if _, e := uuid.Parse(course.ID); e != nil {
				return e
			}
			var existing domain.Course
			if tx.Get(&existing, map[string]any{"id": course.ID}) == nil {
				if existing.Deleted {
					continue
				}
				existing.Name = course.Name
				existing.Teachers = course.Teachers
				course = existing
			} else {
				course.AutoRecord = true
				course.Directory = application.SafeName(course.Name) + "-" + course.ID[:8]
			}
			course.SemesterID = in.Semester.ID
			if e := tx.Save(&course); e != nil {
				return e
			}
			if e := tx.Delete(&domain.Occurrence{}, map[string]any{"course_id": course.ID}); e != nil {
				return e
			}
		}
		for _, o := range in.Occurrences {
			if !o.End.After(o.Start) {
				return errors.New("课程结束时间无效")
			}
			var course domain.Course
			if tx.Get(&course, map[string]any{"id": o.CourseID, "deleted": false}) != nil {
				continue
			}
			if e := tx.Save(&o); e != nil {
				return e
			}
		}
		return nil
	})
	respond(c, nil, e, gin.H{"synced": true})
}

type chunkInput struct {
	Seq  int    `json:"seq"`
	SHA  string `json:"sha256"`
	Data string `json:"data"`
}

func (a api) chunk(c *gin.Context) {
	var in chunkInput
	if !bind(c, &in) {
		return
	}
	b, e := base64.StdEncoding.DecodeString(in.Data)
	if e == nil {
		e = a.s.AddChunk(c.Param("id"), in.Seq, in.SHA, b)
	}
	respond(c, nil, e, gin.H{"ack": in.Seq})
}
func (a api) audio(c *gin.Context) {
	r, e := a.s.Recording(c.Param("id"))
	if e != nil {
		fail(c, e)
		return
	}
	if r.Status == "recording" {
		c.JSON(409, gin.H{"error": "录制尚未完成"})
		return
	}
	c.Header("Content-Type", "audio/wav")
	c.Header("Cache-Control", "private, no-store")
	c.File(r.Path)
}
func (a api) taskAction(c *gin.Context) {
	e := a.s.DB.Atomic(func(tx domain.Store) error {
		var t domain.Task
		if e := tx.Get(&t, map[string]any{"id": c.Param("id")}); e != nil {
			return e
		}
		switch c.Param("action") {
		case "stop":
			if t.Status == "running" {
				t.Status = "stopping"
			} else if t.Status != "succeeded" {
				t.Status = "stopped"
			}
		case "start", "retry":
			if t.Status == "running" || t.Status == "stopping" {
				return errors.New("任务尚未停止")
			}
			if t.Status == "succeeded" {
				return errors.New("请创建新任务以重新生成")
			}
			t.Status = "queued"
			t.Attempts = 0
			t.Error = ""
		default:
			return errors.New("无效任务操作")
		}
		return tx.Save(&t)
	})
	respond(c, nil, e, gin.H{"ok": true})
}
func (a api) settings(c *gin.Context) {
	cfg, e := a.s.Config()
	if e != nil {
		fail(c, e)
		return
	}
	var patch map[string]json.RawMessage
	if !bind(c, &patch) {
		return
	}
	// Decode onto the existing configuration so omitted secrets are kept; empty string explicitly clears.
	b, _ := json.Marshal(patch)
	if e = json.Unmarshal(b, &cfg); e != nil {
		fail(c, e)
		return
	}
	cfg.ID = 1
	if cfg.GPULimit < 1 || cfg.GPULimit > 8 || cfg.NoteLimit < 1 || cfg.NoteLimit > 32 || cfg.InputBudget < 1000 || cfg.InputBudget > 200000 {
		fail(c, errors.New("并发或输入预算超出范围"))
		return
	}
	if cfg.Protocol != "chat" && cfg.Protocol != "responses" {
		fail(c, errors.New("协议必须为 chat 或 responses"))
		return
	}
	for _, raw := range []string{cfg.AudioURL, cfg.OpenAIURL} {
		u, e := url.Parse(raw)
		if e != nil || u.Host == "" || (u.Scheme != "http" && u.Scheme != "https") || u.RawQuery != "" || u.Fragment != "" {
			fail(c, errors.New("服务地址必须为 http(s) 基地址"))
			return
		}
	}
	respond(c, nil, a.s.DB.Save(&cfg), gin.H{"saved": true})
}
func (a api) stream(c *gin.Context) {
	id := c.Param("id")
	if _, e := a.s.Recording(id); e != nil {
		fail(c, e)
		return
	}
	up := websocket.Upgrader{CheckOrigin: func(r *http.Request) bool {
		origin := r.Header.Get("Origin")
		if origin == "" {
			return true
		}
		u, e := url.Parse(origin)
		return e == nil && u.Host == r.Host
	}}
	ws, e := up.Upgrade(c.Writer, c.Request, nil)
	if e != nil {
		return
	}
	defer ws.Close()
	ws.SetReadLimit(1 << 20)
	cursor, _ := strconv.ParseUint(c.Query("cursor"), 10, 64)
	incoming := make(chan chunkInput, 8)
	done := make(chan struct{})
	defer close(done)
	go func() {
		defer close(incoming)
		for {
			var in chunkInput
			if ws.ReadJSON(&in) != nil {
				return
			}
			select {
			case incoming <- in:
			case <-done:
				return
			}
		}
	}()
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	chunks, _ := a.s.Chunks(id)
	if ws.WriteJSON(gin.H{"type": "resume", "chunks": chunks}) != nil {
		return
	}
	for {
		select {
		case in, ok := <-incoming:
			if !ok {
				return
			}
			b, e := base64.StdEncoding.DecodeString(in.Data)
			if e == nil {
				e = a.s.AddChunk(id, in.Seq, in.SHA, b)
			}
			out := gin.H{"type": "ack", "seq": in.Seq}
			if e != nil {
				out = gin.H{"type": "error", "error": e.Error()}
			}
			ws.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if ws.WriteJSON(out) != nil {
				return
			}
		case <-ticker.C:
			var events []domain.Event
			if a.s.DB.List(&events, map[string]any{"recording_id": id}) != nil {
				return
			}
			sort.Slice(events, func(i, j int) bool { return events[i].ID < events[j].ID })
			ws.SetWriteDeadline(time.Now().Add(10 * time.Second))
			for _, event := range events {
				if event.ID <= cursor {
					continue
				}
				if ws.WriteJSON(gin.H{"type": "segment", "cursor": event.ID, "segment": json.RawMessage(event.Payload)}) != nil {
					return
				}
				cursor = event.ID
			}
			if ws.WriteJSON(gin.H{"type": "heartbeat", "cursor": cursor}) != nil {
				return
			}
		}
	}
}

var _ = fmt.Sprintf
var _ = strings.TrimSpace
