package domain

import (
	"context"
	"io"
	"time"
)

type Semester struct {
	ID    string `json:"id" gorm:"primaryKey"`
	Name  string `json:"name"`
	Start string `json:"start"`
	End   string `json:"end"`
}
type Course struct {
	ID         string `json:"id" gorm:"primaryKey"`
	SemesterID string `json:"semester_id" gorm:"index"`
	Name       string `json:"name" validate:"required,max=160"`
	Teachers   string `json:"teachers"`
	AutoRecord bool   `json:"auto_record"`
	Prompt     string `json:"prompt"`
	Directory  string `json:"-"`
	Deleted    bool   `json:"-" gorm:"index"`
}
type Occurrence struct {
	ID       string    `json:"id" gorm:"primaryKey"`
	CourseID string    `json:"course_id" gorm:"index"`
	Start    time.Time `json:"start"`
	End      time.Time `json:"end"`
}
type Recording struct {
	ID           string    `json:"id" gorm:"primaryKey"`
	CourseID     string    `json:"course_id" gorm:"index"`
	Title        string    `json:"title"`
	StartedAt    time.Time `json:"started_at"`
	Status       string    `json:"status"`
	Samples      int64     `json:"samples"`
	TotalChunks  int       `json:"total_chunks"`
	Interrupted  bool      `json:"interrupted"`
	CaptureError string    `json:"capture_error"`
	Gaps         string    `json:"gaps"`
	Path         string    `json:"-"`
	Deleted      bool      `json:"-" gorm:"index"`
}
type Chunk struct {
	RecordingID string `json:"recording_id" gorm:"primaryKey"`
	Seq         int    `json:"seq" gorm:"primaryKey"`
	Samples     int64  `json:"samples"`
	SHA256      string `json:"sha256"`
	Path        string `json:"-"`
}
type Segment struct {
	ID          string  `json:"id" gorm:"primaryKey"`
	RecordingID string  `json:"recording_id" gorm:"index"`
	Start       float64 `json:"start"`
	End         float64 `json:"end"`
	Text        string  `json:"text"`
	Speaker     string  `json:"speaker"`
	Version     int     `json:"version"`
	Final       bool    `json:"final"`
}
type Event struct {
	ID          uint64 `json:"id" gorm:"primaryKey;autoIncrement"`
	RecordingID string `json:"recording_id" gorm:"index"`
	Payload     string `json:"payload"`
}
type Note struct {
	ID          string    `json:"id" gorm:"primaryKey"`
	RecordingID string    `json:"recording_id" gorm:"index"`
	Markdown    string    `json:"markdown"`
	Edited      bool      `json:"edited"`
	CreatedAt   time.Time `json:"created_at"`
}
type Task struct {
	ID          string    `json:"id" gorm:"primaryKey"`
	RecordingID string    `json:"recording_id" gorm:"index"`
	Kind        string    `json:"kind"`
	Status      string    `json:"status" gorm:"index"`
	Attempts    int       `json:"attempts"`
	Progress    float64   `json:"progress"`
	Checkpoint  int       `json:"checkpoint"`
	Error       string    `json:"error"`
	Lease       time.Time `json:"lease"`
	Snapshot    string    `json:"-"`
	CreatedAt   time.Time `json:"created_at"`
}
type Config struct {
	ID                  int    `json:"-" gorm:"primaryKey"`
	AudioURL            string `json:"audio_url"`
	AudioKey            string `json:"audio_key,omitempty"`
	OpenAIURL           string `json:"openai_url"`
	OpenAIKey           string `json:"openai_key,omitempty"`
	Model               string `json:"model"`
	Protocol            string `json:"protocol"`
	Reasoning           string `json:"reasoning"`
	InputBudget         int    `json:"input_budget"`
	GPULimit            int    `json:"gpu_limit"`
	NoteLimit           int    `json:"note_limit"`
	TranscriptionPrompt string `json:"transcription_prompt"`
	NotePrompt          string `json:"note_prompt"`
}

// Store is implemented by persistence adapters. Atomic serializes read/modify/write operations.
type Store interface {
	Get(any, map[string]any) error
	List(any, map[string]any) error
	Save(any) error
	Delete(any, map[string]any) error
	Atomic(func(Store) error) error
}
type AudioService interface {
	Transcribe(context.Context, Config, string, io.Reader, bool, int64) ([]Segment, error)
	Control(context.Context, Config, string) (map[string]any, error)
}
type NoteService interface {
	Generate(context.Context, Config, string) (string, error)
}
