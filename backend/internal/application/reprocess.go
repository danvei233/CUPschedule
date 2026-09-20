package application

import (
	"blackbook/backend/internal/domain"
	"errors"
	"github.com/google/uuid"
	"os"
	"time"
)

// QueueReprocess keeps existing transcripts and notes until inference succeeds.
func (s *Service) QueueReprocess(id, kind string) (domain.Task, error) {
	if kind == "" {
		kind = "note"
	}
	var result domain.Task
	if kind != "note" && kind != "transcribe" {
		return result, errors.New("任务类型必须为 note 或 transcribe")
	}
	err := s.DB.Atomic(func(tx domain.Store) error {
		var r domain.Recording
		if err := tx.Get(&r, map[string]any{"id": id, "deleted": false}); err != nil {
			return err
		}
		if r.Status == "recording" {
			return errors.New("录制尚未完成，请先结束录音并完成上传")
		}
		if kind == "transcribe" {
			file, err := os.Stat(r.Path)
			if err != nil || file.IsDir() || file.Size() < 44 {
				return errors.New("完整音频文件尚不可用，无法重新转写")
			}
		}
		var tasks []domain.Task
		if err := tx.List(&tasks, map[string]any{"recording_id": id}); err != nil {
			return err
		}
		for _, t := range tasks {
			if (t.Kind == kind || (kind == "transcribe" && t.Kind == "live")) && (t.Status == "queued" || t.Status == "running" || t.Status == "stopping" || t.Status == "waiting_config") {
				return errors.New("已有同类任务正在处理，请等待完成或先停止任务")
			}
		}
		result = domain.Task{ID: uuid.NewString(), RecordingID: id, Kind: kind, Status: "queued", CreatedAt: time.Now()}
		return tx.Save(&result)
	})
	return result, err
}
