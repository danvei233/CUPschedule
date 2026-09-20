package remote

import (
	"blackbook/backend/internal/domain"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

type Audio struct{}

func (Audio) Transcribe(ctx context.Context, c domain.Config, id string, r io.Reader, final bool, offset int64) ([]domain.Segment, error) {
	u := strings.TrimRight(c.AudioURL, "/") + "/transcribe?recording_id=" + url.QueryEscape(id) + fmt.Sprintf("&final=%t&offset=%d", final, offset)
	req, e := http.NewRequestWithContext(ctx, "POST", u, r)
	if e != nil {
		return nil, e
	}
	req.Header.Set("X-Service-Key", c.AudioKey)
	req.Header.Set("Content-Type", "audio/wav")
	req.Header.Set("X-Transcription-Prompt", url.QueryEscape(c.TranscriptionPrompt))
	resp, e := (&http.Client{Timeout: 30 * time.Minute}).Do(req)
	if e != nil {
		return nil, e
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 2000))
		return nil, fmt.Errorf("audio service %d: %s", resp.StatusCode, b)
	}
	var out struct {
		Segments []domain.Segment `json:"segments"`
	}
	e = json.NewDecoder(resp.Body).Decode(&out)
	return out.Segments, e
}
func (Audio) Control(ctx context.Context, c domain.Config, action string) (map[string]any, error) {
	method := "POST"
	if action == "status" {
		method = "GET"
	}
	req, e := http.NewRequestWithContext(ctx, method, strings.TrimRight(c.AudioURL, "/")+"/models/"+action, nil)
	if e != nil {
		return nil, e
	}
	req.Header.Set("X-Service-Key", c.AudioKey)
	resp, e := (&http.Client{Timeout: 60 * time.Second}).Do(req)
	if e != nil {
		return nil, e
	}
	defer resp.Body.Close()
	var out map[string]any
	e = json.NewDecoder(resp.Body).Decode(&out)
	if resp.StatusCode != 200 {
		return out, fmt.Errorf("audio service %d", resp.StatusCode)
	}
	return out, e
}

type OpenAI struct{}

func (o OpenAI) Generate(ctx context.Context, c domain.Config, input string) (string, error) {
	// Conservative character budget for predominantly Chinese transcripts. Chunk at newlines.
	budget := max(1000, c.InputBudget)
	runes := []rune(input)
	if len(runes) <= budget {
		return o.call(ctx, c, input)
	}
	var summaries []string
	for start := 0; start < len(runes); {
		end := min(start+budget, len(runes))
		if end < len(runes) {
			for j := end; j > start+budget/2; j-- {
				if runes[j-1] == '\n' {
					end = j
					break
				}
			}
		}
		text, e := o.call(ctx, c, "以下是课堂的一个片段，请保留时间戳整理：\n"+string(runes[start:end]))
		if e != nil {
			return "", e
		}
		summaries = append(summaries, text)
		start = end
	}
	merged := strings.Join(summaries, "\n\n")
	if len([]rune(merged)) >= len(runes) {
		return "", errors.New("分段整理未缩短内容，请增加输入预算或调整提示词")
	}
	return o.Generate(ctx, c, "合并以下分段笔记，去除重复但保留原文时间戳：\n"+merged)
}
func (OpenAI) call(ctx context.Context, c domain.Config, input string) (string, error) {
	body := map[string]any{"model": c.Model}
	path := "/chat/completions"
	if c.Protocol == "responses" {
		path = "/responses"
		body["instructions"] = c.NotePrompt
		body["input"] = input
		if c.Reasoning != "" {
			body["reasoning"] = map[string]string{"effort": c.Reasoning}
		}
	} else {
		body["messages"] = []map[string]string{{"role": "system", "content": c.NotePrompt}, {"role": "user", "content": input}}
		if c.Reasoning != "" {
			body["reasoning_effort"] = c.Reasoning
		}
	}
	data, _ := json.Marshal(body)
	req, e := http.NewRequestWithContext(ctx, "POST", strings.TrimRight(c.OpenAIURL, "/")+path, bytes.NewReader(data))
	if e != nil {
		return "", e
	}
	req.Header.Set("Authorization", "Bearer "+c.OpenAIKey)
	req.Header.Set("Content-Type", "application/json")
	resp, e := (&http.Client{Timeout: 10 * time.Minute}).Do(req)
	if e != nil {
		return "", e
	}
	defer resp.Body.Close()
	b, e := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	if e != nil {
		return "", e
	}
	if resp.StatusCode != 200 {
		return "", fmt.Errorf("OpenAI HTTP %d: %s", resp.StatusCode, string(b[:min(len(b), 1000)]))
	}
	var out struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
		Output []struct {
			Content []struct {
				Text string `json:"text"`
			} `json:"content"`
		} `json:"output"`
	}
	if e = json.Unmarshal(b, &out); e != nil {
		return "", e
	}
	var text strings.Builder
	if c.Protocol == "responses" {
		for _, o := range out.Output {
			for _, v := range o.Content {
				text.WriteString(v.Text)
			}
		}
	} else if len(out.Choices) > 0 {
		text.WriteString(out.Choices[0].Message.Content)
	}
	if strings.TrimSpace(text.String()) == "" {
		return "", errors.New("OpenAI 返回空笔记")
	}
	return text.String(), nil
}
