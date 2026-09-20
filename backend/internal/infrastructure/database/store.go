package database

import (
	"blackbook/backend/internal/domain"
	"github.com/glebarez/sqlite"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
	"sync"
)

type Store struct {
	db *gorm.DB
	mu *sync.Mutex
}

func Open(path string) (*Store, error) {
	db, err := gorm.Open(sqlite.Open(path), &gorm.Config{Logger: logger.Default.LogMode(logger.Silent)})
	if err != nil {
		return nil, err
	}
	sql, err := db.DB()
	if err != nil {
		return nil, err
	}
	sql.SetMaxOpenConns(1)
	if err = db.Exec("PRAGMA journal_mode=WAL").Error; err != nil {
		return nil, err
	}
	db.Exec("PRAGMA busy_timeout=5000")
	// Versioned migrations are forward-only; future schema changes add another version.
	type Migration struct {
		Version int `gorm:"primaryKey"`
	}
	if err = db.AutoMigrate(&Migration{}); err != nil {
		return nil, err
	}
	var count int64
	db.Model(&Migration{}).Where("version = ?", 1).Count(&count)
	if count == 0 {
		err = db.Transaction(func(tx *gorm.DB) error {
			if e := tx.AutoMigrate(&domain.Semester{}, &domain.Course{}, &domain.Occurrence{}, &domain.Recording{}, &domain.Chunk{}, &domain.Segment{}, &domain.Event{}, &domain.Note{}, &domain.Task{}, &domain.Config{}); e != nil {
				return e
			}
			return tx.Create(&Migration{Version: 1}).Error
		})
		if err != nil {
			return nil, err
		}
	}
	return &Store{db: db, mu: &sync.Mutex{}}, nil
}
func (s *Store) Close() error {
	db, e := s.db.DB()
	if e != nil {
		return e
	}
	return db.Close()
}
func (s *Store) Get(v any, q map[string]any) error    { return s.db.Where(q).First(v).Error }
func (s *Store) List(v any, q map[string]any) error   { return s.db.Where(q).Find(v).Error }
func (s *Store) Save(v any) error                     { return s.db.Save(v).Error }
func (s *Store) Delete(v any, q map[string]any) error { return s.db.Where(q).Delete(v).Error }
func (s *Store) Atomic(f func(domain.Store) error) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.db.Transaction(func(tx *gorm.DB) error { return f(&Store{db: tx, mu: s.mu}) })
}
