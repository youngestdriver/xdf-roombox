package main

import (
	"database/sql"
	"log"
	"sync"
	"time"

	"github.com/robfig/cron/v3"
	_ "modernc.org/sqlite"
)

type DB struct{ db *sql.DB }

func (s *DB) Close() { s.db.Close() }

func NewDB(path string) (*DB, error) {
	dsn := "file:" + path + "?_pragma=busy_timeout(5000)&_pragma=journal_mode(WAL)"
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1) // modernc/sqlite 写并发限制, 单连接最稳
	s := &DB{db: db}
	if err := s.migrate(); err != nil {
		return nil, err
	}
	return s, nil
}

func (s *DB) migrate() error {
	stmts := []string{
		`CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT)`,
		`CREATE TABLE IF NOT EXISTS lessons(
			lesson_id TEXT PRIMARY KEY,
			start_time INTEGER NOT NULL,
			end_time INTEGER NOT NULL,
			classroom_name TEXT,
			teacher TEXT,
			class_id TEXT,
			main_id TEXT,
			room_code TEXT,
			record INTEGER DEFAULT 0,
			playback_status INTEGER DEFAULT 0,
			playback_url TEXT DEFAULT '',
			media_id TEXT DEFAULT '',
			auth_exp INTEGER DEFAULT 0,
			notified INTEGER DEFAULT 0,
			raw TEXT,
			updated_at INTEGER
		)`,
		`CREATE INDEX IF NOT EXISTS idx_lessons_start ON lessons(start_time)`,
	}
	for _, q := range stmts {
		if _, err := s.db.Exec(q); err != nil {
			return err
		}
	}
	return nil
}

// ---- settings ----
func (s *DB) GetSetting(k string) string {
	var v string
	if err := s.db.QueryRow(`SELECT value FROM settings WHERE key=?`, k).Scan(&v); err != nil {
		return ""
	}
	return v
}
func (s *DB) SetSetting(k, v string) {
	if _, err := s.db.Exec(`INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value`, k, v); err != nil {
		log.Println("[db] SetSetting", k, err)
	}
}

// ---- lessons ----
type LessonRow struct {
	LessonID       string
	StartTime      int64  `json:"start"`
	EndTime        int64  `json:"end"`
	ClassroomName  string `json:"title"`
	Teacher        string
	ClassID        string
	MainID         string
	RoomCode       string
	Record         int
	PlaybackStatus int
	PlaybackURL    string
	MediaID        string
	AuthExp        int64
	Notified       int
	Raw            string
}

func (s *DB) UpsertLesson(l *LessonRow) error {
	_, err := s.db.Exec(`INSERT INTO lessons(lesson_id,start_time,end_time,classroom_name,teacher,class_id,main_id,room_code,record,playback_status,playback_url,media_id,auth_exp,raw,updated_at)
		VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
		ON CONFLICT(lesson_id) DO UPDATE SET
			start_time=excluded.start_time, end_time=excluded.end_time,
			classroom_name=excluded.classroom_name, teacher=excluded.teacher,
			class_id=excluded.class_id, main_id=excluded.main_id, room_code=excluded.room_code,
			record=excluded.record, playback_status=excluded.playback_status,
			playback_url=excluded.playback_url, media_id=excluded.media_id,
			auth_exp=excluded.auth_exp, raw=excluded.raw, updated_at=excluded.updated_at`,
		l.LessonID, l.StartTime, l.EndTime, l.ClassroomName, l.Teacher, l.ClassID, l.MainID,
		l.RoomCode, l.Record, l.PlaybackStatus, l.PlaybackURL, l.MediaID, l.AuthExp, l.Raw,
		time.Now().Unix())
	return err
}

func (s *DB) ListLessons(fromSec, toSec int64) ([]LessonRow, error) {
	rows, err := s.db.Query(`SELECT lesson_id,start_time,end_time,classroom_name,teacher,class_id,main_id,room_code,record,playback_status,playback_url,media_id,auth_exp,notified,raw
		FROM lessons WHERE start_time>=? AND start_time<? ORDER BY start_time`, fromSec, toSec)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []LessonRow
	for rows.Next() {
		var l LessonRow
		if err := rows.Scan(&l.LessonID, &l.StartTime, &l.EndTime, &l.ClassroomName, &l.Teacher,
			&l.ClassID, &l.MainID, &l.RoomCode, &l.Record, &l.PlaybackStatus,
			&l.PlaybackURL, &l.MediaID, &l.AuthExp, &l.Notified, &l.Raw); err != nil {
			return nil, err
		}
		out = append(out, l)
	}
	return out, nil
}

// 回放列表: record=1 的课 (过去已发生), 按时间倒序
func (s *DB) ListPlaybacks() ([]LessonRow, error) {
	rows, err := s.db.Query(`SELECT lesson_id,start_time,end_time,classroom_name,teacher,class_id,main_id,room_code,record,playback_status,playback_url,media_id,auth_exp,notified,raw
		FROM lessons WHERE record=1 AND start_time<=? ORDER BY start_time DESC LIMIT 300`, time.Now().Unix())
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []LessonRow
	for rows.Next() {
		var l LessonRow
		if err := rows.Scan(&l.LessonID, &l.StartTime, &l.EndTime, &l.ClassroomName, &l.Teacher,
			&l.ClassID, &l.MainID, &l.RoomCode, &l.Record, &l.PlaybackStatus,
			&l.PlaybackURL, &l.MediaID, &l.AuthExp, &l.Notified, &l.Raw); err != nil {
			return nil, err
		}
		out = append(out, l)
	}
	return out, nil
}

func (s *DB) GetLesson(id string) (*LessonRow, error) {
	var l LessonRow
	err := s.db.QueryRow(`SELECT lesson_id,start_time,end_time,classroom_name,teacher,class_id,main_id,room_code,record,playback_status,playback_url,media_id,auth_exp,notified,raw
		FROM lessons WHERE lesson_id=?`, id).Scan(&l.LessonID, &l.StartTime, &l.EndTime,
		&l.ClassroomName, &l.Teacher, &l.ClassID, &l.MainID, &l.RoomCode, &l.Record,
		&l.PlaybackStatus, &l.PlaybackURL, &l.MediaID, &l.AuthExp, &l.Notified, &l.Raw)
	return &l, err
}

func (s *DB) MarkNotified(id string) {
	s.db.Exec(`UPDATE lessons SET notified=1 WHERE lesson_id=?`, id)
}

func (s *DB) Counts() (lessons, playbacks int) {
	s.db.QueryRow(`SELECT COUNT(*) FROM lessons`).Scan(&lessons)
	s.db.QueryRow(`SELECT COUNT(*) FROM lessons WHERE playback_status=1 AND playback_url!=''`).Scan(&playbacks)
	return
}

// ---- 应用全局状态 ----
type App struct {
	db        *DB
	cron      *cron.Cron
	mu        sync.Mutex
	adminPass string
}

var AppData *App // 供 web.go 引用

func NewApp(dbPath, adminPass string) *App {
	db, err := NewDB(dbPath)
	if err != nil {
		log.Fatal("[db] ", err)
	}
	return &App{db: db, cron: cron.New(), adminPass: adminPass}
}
