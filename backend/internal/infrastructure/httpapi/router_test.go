package httpapi

import (
	"blackbook/backend/internal/application"
	"blackbook/backend/internal/domain"
	"blackbook/backend/internal/infrastructure/database"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestRetranscriptionQueue(t *testing.T) {
	s, server := setup(t)
	id := uuid.NewString()
	path := filepath.Join(t.TempDir(), "recording.wav")
	if err := os.WriteFile(path, application.WAVHeader(0), 0600); err != nil {
		t.Fatal(err)
	}
	r := domain.Recording{ID: id, CourseID: "misc", Status: "transcribed", Path: path}
	if err := s.DB.Save(&r); err != nil {
		t.Fatal(err)
	}
	original := domain.Segment{ID: "original", RecordingID: id, Text: "用户修正", Final: true}
	s.DB.Save(&original)
	code, body := call(t, server, "POST", "/tasks", map[string]any{"recording_id": id, "kind": "transcribe"})
	if code != 200 {
		t.Fatalf("submit: %d %s", code, body)
	}
	var task domain.Task
	json.Unmarshal(body, &task)
	if task.Kind != "transcribe" || task.Status != "queued" {
		t.Fatal("wrong task", task.Kind, task.Status)
	}
	code, _ = call(t, server, "POST", "/tasks", map[string]any{"recording_id": id, "kind": "transcribe"})
	if code != 400 {
		t.Fatal("duplicate task allowed")
	}
	var retained domain.Segment
	if err := s.DB.Get(&retained, map[string]any{"id": "original"}); err != nil || retained.Text != "用户修正" {
		t.Fatal("submission changed original text")
	}
	code, _ = call(t, server, "POST", "/tasks", map[string]any{"recording_id": id, "kind": "shell"})
	if code != 400 {
		t.Fatal("invalid kind accepted")
	}
	r.Status = "recording"
	s.DB.Save(&r)
	code, _ = call(t, server, "POST", "/tasks", map[string]any{"recording_id": id, "kind": "transcribe"})
	if code != 400 {
		t.Fatal("unfinished recording accepted")
	}
	r.Status = "transcribed"
	r.Path = ""
	s.DB.Save(&r)
	code, _ = call(t, server, "POST", "/tasks", map[string]any{"recording_id": id, "kind": "transcribe"})
	if code != 400 {
		t.Fatal("missing audio accepted")
	}
}

type fakeAudio struct{}

func (fakeAudio) Transcribe(_ context.Context, _ domain.Config, _ string, r io.Reader, final bool, _ int64) ([]domain.Segment, error) {
	_, e := io.Copy(io.Discard, r)
	return []domain.Segment{{ID: "0", Text: "物料衡算：输入等于输出加累积。", Speaker: "说话人 1", End: 1, Final: final}}, e
}
func (fakeAudio) Control(context.Context, domain.Config, string) (map[string]any, error) {
	return map[string]any{"loaded": true}, nil
}

type fakeNotes struct{}

func (fakeNotes) Generate(_ context.Context, c domain.Config, input string) (string, error) {
	return "# 笔记\n" + c.NotePrompt + "\n" + input, nil
}

const testKey = "test-key-not-a-real-secret"

func setup(t *testing.T) (*application.Service, *httptest.Server) {
	t.Helper()
	root := t.TempDir()
	db, e := database.Open(filepath.Join(root, "test.db"))
	if e != nil {
		t.Fatal(e)
	}
	t.Cleanup(func() { db.Close() })
	s, e := application.New(db, root, fakeAudio{}, fakeNotes{})
	if e != nil {
		t.Fatal(e)
	}
	server := httptest.NewServer(Router(s, testKey))
	t.Cleanup(server.Close)
	return s, server
}
func call(t *testing.T, server *httptest.Server, method, path string, body any) (int, []byte) {
	t.Helper()
	var data []byte
	if body != nil {
		data, _ = json.Marshal(body)
	}
	req, _ := http.NewRequest(method, server.URL+"/api/v1"+path, bytes.NewReader(data))
	req.Header.Set("X-API-Key", testKey)
	req.Header.Set("Content-Type", "application/json")
	resp, e := http.DefaultClient.Do(req)
	if e != nil {
		t.Fatal(e)
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, b
}
func chunk(seq int, b []byte) map[string]any {
	sum := sha256.Sum256(b)
	return map[string]any{"seq": seq, "sha256": hex.EncodeToString(sum[:]), "data": base64.StdEncoding.EncodeToString(b)}
}
func TestUploadResumeRangeAndTasks(t *testing.T) {
	s, server := setup(t)
	resp, e := http.Get(server.URL + "/api/v1/courses")
	if e != nil {
		t.Fatal(e)
	}
	resp.Body.Close()
	if resp.StatusCode != 401 {
		t.Fatal("missing authentication")
	}
	id := uuid.NewString()
	code, b := call(t, server, "POST", "/recordings", map[string]any{"id": id, "course_id": "misc"})
	if code != 200 {
		t.Fatalf("create: %s", b)
	}
	// An out-of-order chunk must not cause a corrupt final WAV or duplicate bytes.
	for _, seq := range []int{1, 1} {
		code, b = call(t, server, "POST", "/recordings/"+id+"/chunks", chunk(seq, []byte{3, 4}))
		if code != 200 {
			t.Fatalf("chunk: %s", b)
		}
	}
	code, _ = call(t, server, "POST", "/recordings/"+id+"/complete", map[string]any{"total_chunks": 2})
	if code == 200 {
		t.Fatal("accepted missing chunk")
	}
	call(t, server, "POST", "/recordings/"+id+"/chunks", chunk(0, []byte{1, 2}))
	code, _ = call(t, server, "POST", "/recordings/"+id+"/chunks", chunk(0, []byte{9, 9}))
	if code == 200 {
		t.Fatal("accepted conflicting duplicate")
	}
	code, b = call(t, server, "POST", "/recordings/"+id+"/complete", map[string]any{"total_chunks": 2})
	if code != 200 {
		t.Fatalf("complete: %s", b)
	}
	code, _ = call(t, server, "POST", "/recordings/"+id+"/complete", map[string]any{"total_chunks": 2})
	if code != 200 {
		t.Fatal("completion not idempotent")
	}
	req, _ := http.NewRequest("GET", server.URL+"/api/v1/recordings/"+id+"/audio", nil)
	req.Header.Set("X-API-Key", testKey)
	req.Header.Set("Range", "bytes=44-47")
	resp, e = http.DefaultClient.Do(req)
	if e != nil {
		t.Fatal(e)
	}
	audio, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 206 || !bytes.Equal(audio, []byte{1, 2, 3, 4}) {
		t.Fatalf("range: %d %v", resp.StatusCode, audio)
	}
	cfg, _ := s.Config()
	cfg.OpenAIKey = "test"
	cfg.Model = "fake"
	s.DB.Save(&cfg)
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	defer func() { cancel(); <-done }()
	go func() { defer close(done); (&application.Worker{S: s}).Run(ctx) }()
	deadline := time.Now().Add(12 * time.Second)
	for time.Now().Before(deadline) {
		var notes []domain.Note
		s.DB.List(&notes, map[string]any{"recording_id": id})
		if len(notes) == 1 {
			if !strings.Contains(notes[0].Markdown, "物料衡算") {
				t.Fatal(notes)
			}
			return
		}
		time.Sleep(100 * time.Millisecond)
	}
	t.Fatal("pipeline did not create note")
}
func TestSettingsSecretsAndSyncPrompt(t *testing.T) {
	_, server := setup(t)
	call(t, server, "PATCH", "/settings", map[string]any{"openai_key": "private-key"})
	call(t, server, "PATCH", "/settings", map[string]any{"note_limit": 3})
	code, b := call(t, server, "GET", "/settings", nil)
	if code != 200 || bytes.Contains(b, []byte("private-key")) || !bytes.Contains(b, []byte(`"has_openai_key":true`)) {
		t.Fatalf("secret leak/loss %s", b)
	}
	call(t, server, "PATCH", "/settings", map[string]any{"openai_key": ""})
	_, b = call(t, server, "GET", "/settings", nil)
	if !bytes.Contains(b, []byte(`"has_openai_key":false`)) {
		t.Fatal(string(b))
	}
	id := uuid.NewString()
	payload := map[string]any{"semester": map[string]any{"id": "1", "name": "学期"}, "courses": []map[string]any{{"id": id, "name": "CON/../课程"}}}
	code, b = call(t, server, "POST", "/schedule/sync", payload)
	if code != 200 {
		t.Fatal(string(b))
	}
	call(t, server, "PATCH", "/courses/"+id, map[string]any{"prompt": "保留公式", "auto_record": false})
	call(t, server, "POST", "/schedule/sync", payload)
	_, b = call(t, server, "GET", "/courses", nil)
	if !bytes.Contains(b, []byte("保留公式")) || !bytes.Contains(b, []byte(`"auto_record":false`)) {
		t.Fatal(string(b))
	}
}
func TestWebSocketRecoveryAndDelete(t *testing.T) {
	s, server := setup(t)
	id := uuid.NewString()
	call(t, server, "POST", "/recordings", map[string]any{"id": id, "course_id": "misc"})
	s.SaveSegments(id, []domain.Segment{{ID: "a", Text: "第一段", Start: 0, End: 1}}, false)
	ws, _, e := websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(server.URL, "http")+"/api/v1/recordings/"+id+"/stream?cursor=0", http.Header{"X-Api-Key": []string{testKey}})
	if e != nil {
		t.Fatal(e)
	}
	defer ws.Close()
	ws.SetReadDeadline(time.Now().Add(4 * time.Second))
	var msg map[string]any
	if e = ws.ReadJSON(&msg); e != nil || msg["type"] != "resume" {
		t.Fatalf("resume %v %v", msg, e)
	}
	ws.WriteJSON(chunk(0, []byte{1, 2}))
	if e = ws.ReadJSON(&msg); e != nil || msg["type"] != "ack" {
		t.Fatalf("ack %v %v", msg, e)
	}
	var cursor float64
	for i := 0; i < 4; i++ {
		if e = ws.ReadJSON(&msg); e != nil {
			t.Fatal(e)
		}
		if msg["type"] == "segment" {
			cursor = msg["cursor"].(float64)
			if p, ok := msg["segment"].(map[string]any); ok && p["text"] == "第一段" {
				break
			}
		}
	}
	if cursor == 0 {
		t.Fatal("no replay events")
	}
	ws.Close()
	s.SaveSegments(id, []domain.Segment{{ID: "b", Text: "第二段", Start: 1, End: 2}}, false)
	resume, _, e := websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(server.URL, "http")+"/api/v1/recordings/"+id+"/stream?cursor="+fmt.Sprintf("%.0f", cursor), http.Header{"X-Api-Key": []string{testKey}})
	if e != nil {
		t.Fatal(e)
	}
	defer resume.Close()
	resume.SetReadDeadline(time.Now().Add(4 * time.Second))
	resume.ReadJSON(&msg)
	for i := 0; i < 4; i++ {
		if e = resume.ReadJSON(&msg); e != nil {
			t.Fatal(e)
		}
		if msg["type"] == "segment" {
			if msg["cursor"].(float64) <= cursor {
				t.Fatal("replayed old cursor")
			}
			if p, ok := msg["segment"].(map[string]any); ok && p["text"] == "第二段" {
				break
			}
		}
	}
	code, b := call(t, server, "DELETE", "/recordings/"+id, nil)
	if code != 200 {
		t.Fatal(string(b))
	}
	if e = s.SaveSegments(id, []domain.Segment{{ID: "b", Text: "late result"}}, true); e == nil {
		t.Fatal("deleted recording resurrected")
	}
	code, _ = call(t, server, "POST", "/recordings/"+id+"/chunks", chunk(1, []byte{1, 2}))
	if code == 200 {
		t.Fatal("accepted deleted upload")
	}
}

type blockingNotes struct {
	entered chan struct{}
	release chan struct{}
}

func (n blockingNotes) Generate(context.Context, domain.Config, string) (string, error) {
	close(n.entered)
	<-n.release
	return "late note", nil
}
func TestStoppingTaskDiscardsLateProviderResult(t *testing.T) {
	s, server := setup(t)
	id := uuid.NewString()
	r := domain.Recording{ID: id, CourseID: "misc"}
	if e := s.CreateRecording(&r); e != nil {
		t.Fatal(e)
	}
	r.Status = "transcribed"
	s.DB.Save(&r)
	s.SaveSegments(id, []domain.Segment{{ID: "0", Text: "原文", End: 1}}, true)
	cfg, _ := s.Config()
	cfg.OpenAIKey = "x"
	cfg.Model = "fake"
	s.DB.Save(&cfg)
	block := blockingNotes{entered: make(chan struct{}), release: make(chan struct{})}
	s.Notes = block
	_, b := call(t, server, "POST", "/tasks", map[string]any{"recording_id": id})
	var task domain.Task
	json.Unmarshal(b, &task)
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { defer close(done); (&application.Worker{S: s}).Run(ctx) }()
	defer func() { cancel(); <-done }()
	select {
	case <-block.entered:
	case <-time.After(5 * time.Second):
		close(block.release)
		t.Fatal("task did not start")
	}
	code, b := call(t, server, "POST", "/tasks/"+task.ID+"/stop", nil)
	close(block.release)
	if code != 200 {
		t.Fatal(string(b))
	}
	deadline := time.Now().Add(4 * time.Second)
	for time.Now().Before(deadline) {
		var current domain.Task
		s.DB.Get(&current, map[string]any{"id": task.ID})
		if current.Status == "stopped" {
			var notes []domain.Note
			s.DB.List(&notes, map[string]any{"recording_id": id})
			if len(notes) != 0 {
				t.Fatal("late result saved")
			}
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatal("task failed to stop")
}
