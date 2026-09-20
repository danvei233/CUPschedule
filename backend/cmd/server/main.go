package main

import (
	"blackbook/backend/internal/application"
	"blackbook/backend/internal/infrastructure/config"
	"blackbook/backend/internal/infrastructure/database"
	"blackbook/backend/internal/infrastructure/httpapi"
	"blackbook/backend/internal/infrastructure/remote"
	"context"
	"flag"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"time"
)

func env(k, fallback string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return fallback
}
func main() {
	configPath := flag.String("config", env("BLACKBOOK_CONFIG", "config.toml"), "配置文件路径")
	initOnly := flag.Bool("init-config", false, "创建或检查配置后退出")
	flag.Parse()
	cfg, err := config.Load(*configPath)
	if err != nil {
		log.Fatal(err)
	}
	absoluteConfig, _ := filepath.Abs(*configPath)
	log.Printf("配置文件：%s（API key 请在文件的 api_key 中查看）", absoluteConfig)
	if *initOnly {
		return
	}
	root := cfg.DataDir
	if err = os.MkdirAll(root, 0700); err != nil {
		log.Fatal(err)
	}
	db, err := database.Open(filepath.Join(root, "blackbook.db"))
	if err != nil {
		log.Fatal(err)
	}
	s, err := application.New(db, root, remote.Audio{}, remote.OpenAI{})
	if err != nil {
		log.Fatal(err)
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	worker := &application.Worker{S: s}
	workerDone := make(chan struct{})
	go func() { defer close(workerDone); worker.Run(ctx) }()
	server := &http.Server{Addr: cfg.Listen, Handler: httpapi.Router(s, cfg.APIKey), ReadHeaderTimeout: 10 * time.Second, IdleTimeout: 60 * time.Second}
	go func() {
		<-ctx.Done()
		shutdown, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		server.Shutdown(shutdown)
	}()
	log.Printf("blackbook listening on %s", server.Addr)
	if err = server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatal(err)
	}
	stop()
	<-workerDone
	db.Close()
}
