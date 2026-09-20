package remote

import (
	"blackbook/backend/internal/domain"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestOpenAIProtocolsAndOptionalReasoning(t *testing.T) {
	for _, protocol := range []string{"chat", "responses"} {
		t.Run(protocol, func(t *testing.T) {
			calls := 0
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.Header.Get("Authorization") != "Bearer secret" {
					t.Error("missing auth")
				}
				var body map[string]any
				if e := json.NewDecoder(r.Body).Decode(&body); e != nil {
					t.Error(e)
				}
				if calls == 0 {
					if _, ok := body["reasoning_effort"]; ok {
						t.Error("must omit unset reasoning")
					}
					if _, ok := body["reasoning"]; ok {
						t.Error("must omit unset reasoning")
					}
				}
				if calls == 1 {
					if protocol == "chat" && body["reasoning_effort"] != "high" {
						t.Error(body)
					}
					if protocol == "responses" && body["reasoning"] == nil {
						t.Error(body)
					}
				}
				calls++
				w.Header().Set("Content-Type", "application/json")
				if protocol == "chat" {
					if r.URL.Path != "/v1/chat/completions" {
						t.Error(r.URL.Path)
					}
					w.Write([]byte(`{"choices":[{"message":{"content":"# 中文笔记"}}]}`))
				} else {
					if r.URL.Path != "/v1/responses" {
						t.Error(r.URL.Path)
					}
					w.Write([]byte(`{"output":[{"content":[{"type":"output_text","text":"# 中文笔记"}]}]}`))
				}
			}))
			defer server.Close()
			cfg := domain.Config{Protocol: protocol, OpenAIURL: server.URL + "/v1", OpenAIKey: "secret", Model: "configured-model", InputBudget: 1000}
			for _, reasoning := range []string{"", "high"} {
				cfg.Reasoning = reasoning
				out, e := (OpenAI{}).Generate(context.Background(), cfg, "课堂原文")
				if e != nil || !strings.Contains(out, "中文笔记") {
					t.Fatalf("%s %v", out, e)
				}
			}
		})
	}
}

func TestOpenAIErrorIsNotSilentlyRetriedWithAnotherModel(t *testing.T) {
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		w.WriteHeader(400)
		w.Write([]byte(`{"error":"unsupported reasoning_effort"}`))
	}))
	defer server.Close()
	_, e := (OpenAI{}).Generate(context.Background(), domain.Config{OpenAIURL: server.URL, Model: "chosen", Reasoning: "high"}, "text")
	if e == nil || !strings.Contains(e.Error(), "unsupported reasoning_effort") || calls != 1 {
		t.Fatalf("%v %d", e, calls)
	}
}
