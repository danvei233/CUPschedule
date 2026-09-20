// Package config owns bootstrap configuration, outside application business logic.
package config

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"

	"github.com/pelletier/go-toml/v2"
)

type Config struct {
	APIKey  string `toml:"api_key"`
	Listen  string `toml:"listen"`
	DataDir string `toml:"data_dir"`
}

// Load creates missing configuration and persists a generated key before serving.
// Environment variables override existing file values for this process only.
func Load(path string) (Config, error) {
	var result Config
	absolute, err := filepath.Abs(path)
	if err != nil {
		return result, err
	}
	doc := map[string]any{}
	data, err := os.ReadFile(absolute)
	missing := errors.Is(err, os.ErrNotExist)
	if err != nil && !missing {
		return result, err
	}
	if !missing {
		if err = toml.Unmarshal(data, &doc); err != nil {
			return result, fmt.Errorf("配置文件 %s 不是有效的 TOML，请检查格式", absolute)
		}
	}
	changed := missing
	for k, v := range map[string]string{"listen": "127.0.0.1:8090", "data_dir": "data", "api_key": ""} {
		if _, exists := doc[k]; !exists {
			doc[k] = v
			changed = true
		}
		if _, ok := doc[k].(string); !ok {
			return result, fmt.Errorf("config.toml 的 %s 必须是字符串", k)
		}
	}
	if strings.TrimSpace(doc["api_key"].(string)) == "" {
		key := strings.TrimSpace(os.Getenv("BLACKBOOK_API_KEY"))
		if key == "" {
			bytes := make([]byte, 32)
			if _, err = rand.Read(bytes); err != nil {
				return result, err
			}
			key = "bb_" + hex.EncodeToString(bytes)
		}
		doc["api_key"] = key
		changed = true
	}
	result = Config{APIKey: doc["api_key"].(string), Listen: doc["listen"].(string), DataDir: doc["data_dir"].(string)}
	for name, target := range map[string]*string{"BLACKBOOK_API_KEY": &result.APIKey, "BLACKBOOK_LISTEN": &result.Listen, "BLACKBOOK_DATA_DIR": &result.DataDir} {
		if value := strings.TrimSpace(os.Getenv(name)); value != "" {
			*target = value
		}
	}
	if len(strings.TrimSpace(result.APIKey)) < 16 {
		return result, errors.New("api_key 至少需要 16 个字符；留空可自动生成。请同时检查 BLACKBOOK_API_KEY 环境变量")
	}
	if _, _, err = net.SplitHostPort(result.Listen); err != nil {
		return result, errors.New("listen 必须是 host:port 格式，例如 0.0.0.0:8090")
	}
	if strings.TrimSpace(result.DataDir) == "" {
		return result, errors.New("data_dir 不能为空")
	}
	if changed {
		data, err = toml.Marshal(doc)
		if err != nil {
			return result, err
		}
		if err = os.MkdirAll(filepath.Dir(absolute), 0700); err != nil {
			return result, err
		}
		file, err := os.CreateTemp(filepath.Dir(absolute), ".config-*.tmp")
		if err != nil {
			return result, err
		}
		defer os.Remove(file.Name())
		if _, err = file.Write(data); err != nil {
			file.Close()
			return result, err
		}
		if err = file.Sync(); err != nil {
			file.Close()
			return result, err
		}
		if err = file.Close(); err != nil {
			return result, err
		}
		if err = os.Rename(file.Name(), absolute); err != nil {
			return result, fmt.Errorf("保存 config.toml 失败: %w", err)
		}
	}
	if !filepath.IsAbs(result.DataDir) {
		result.DataDir = filepath.Join(filepath.Dir(absolute), result.DataDir)
	}
	return result, nil
}
