package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func cleanEnv(t *testing.T) {
	for _, key := range []string{"BLACKBOOK_API_KEY", "BLACKBOOK_LISTEN", "BLACKBOOK_DATA_DIR"} {
		t.Setenv(key, "")
	}
}
func TestGenerateAndReuse(t *testing.T) {
	cleanEnv(t)
	path := filepath.Join(t.TempDir(), "config.toml")
	first, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(first.APIKey) != 67 {
		t.Fatal("expected 256-bit random key")
	}
	data, _ := os.ReadFile(path)
	if !strings.Contains(string(data), first.APIKey) {
		t.Fatal("key not persisted")
	}
	next, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	if first != next {
		t.Fatal("configuration changed on restart")
	}
}
func TestEmptyKeyPreservesOtherSettings(t *testing.T) {
	cleanEnv(t)
	path := filepath.Join(t.TempDir(), "config.toml")
	os.WriteFile(path, []byte("api_key = ''\nlisten = '0.0.0.0:57002'\ndata_dir = 'my-data'\ncustom = 'keep'\n"), 0600)
	cfg, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Listen != "0.0.0.0:57002" || cfg.DataDir != filepath.Join(filepath.Dir(path), "my-data") {
		t.Fatal(cfg.Listen, cfg.DataDir)
	}
	data, _ := os.ReadFile(path)
	if !strings.Contains(string(data), "keep") {
		t.Fatal("unknown settings removed")
	}
}
func TestEnvironmentOverrideDoesNotRotateFileKey(t *testing.T) {
	cleanEnv(t)
	path := filepath.Join(t.TempDir(), "config.toml")
	first, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	t.Setenv("BLACKBOOK_API_KEY", "override-key-at-least-16")
	cfg, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.APIKey != "override-key-at-least-16" {
		t.Fatal("override ignored")
	}
	t.Setenv("BLACKBOOK_API_KEY", "")
	cfg, err = Load(path)
	if err != nil || cfg.APIKey != first.APIKey {
		t.Fatal("file key changed")
	}
}
func TestInvalidConfigIsNotOverwritten(t *testing.T) {
	cleanEnv(t)
	for _, text := range []string{"not toml!", "api_key='short'", "api_key=42"} {
		path := filepath.Join(t.TempDir(), "config.toml")
		os.WriteFile(path, []byte(text), 0600)
		if _, err := Load(path); err == nil {
			t.Fatal("invalid config accepted")
		}
		data, _ := os.ReadFile(path)
		if string(data) != text {
			t.Fatal("invalid config overwritten")
		}
	}
}
