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
			updated_at INTEGER,
			class_code TEXT DEFAULT '',
			report_url TEXT DEFAULT ''
		)`,
		`CREATE INDEX IF NOT EXISTS idx_lessons_start ON lessons(start_time)`,
		`CREATE INDEX IF NOT EXISTS idx_lessons_class ON lessons(class_id)`,
		`CREATE TABLE IF NOT EXISTS classes(
			class_id TEXT PRIMARY KEY,
			name TEXT DEFAULT '',
			code TEXT DEFAULT '',
			teacher TEXT DEFAULT '',
			source TEXT DEFAULT '',
			updated_at INTEGER
		)`,
	}
	for _, q := range stmts {
		if _, err := s.db.Exec(q); err != nil {
			return err
		}
	}
	// 旧库补列 (列已存在时报错, 忽略)
	_, _ = s.db.Exec(`ALTER TABLE lessons ADD COLUMN class_code TEXT DEFAULT ''`)
	_, _ = s.db.Exec(`ALTER TABLE lessons ADD COLUMN report_url TEXT DEFAULT ''`)
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
	ClassCode      string
	MainID         string
	RoomCode       string
	Record         int
	PlaybackStatus int
	PlaybackURL    string
	MediaID        string
	AuthExp        int64
	Notified       int
	Raw            string
	ReportURL      string
}

const lessonCols = `lesson_id,start_time,end_time,classroom_name,teacher,class_id,main_id,room_code,record,playback_status,playback_url,media_id,auth_exp,notified,raw,class_code,report_url`

type rowScanner interface{ Scan(dest ...any) error }

func scanLesson(sc rowScanner) (LessonRow, error) {
	var l LessonRow
	err := sc.Scan(&l.LessonID, &l.StartTime, &l.EndTime, &l.ClassroomName, &l.Teacher,
		&l.ClassID, &l.MainID, &l.RoomCode, &l.Record, &l.PlaybackStatus,
		&l.PlaybackURL, &l.MediaID, &l.AuthExp, &l.Notified, &l.Raw, &l.ClassCode, &l.ReportURL)
	return l, err
}

func (s *DB) UpsertLesson(l *LessonRow) error {
	_, err := s.db.Exec(`INSERT INTO lessons(lesson_id,start_time,end_time,classroom_name,teacher,class_id,main_id,room_code,record,playback_status,playback_url,media_id,auth_exp,raw,class_code,report_url,updated_at)
		VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
		ON CONFLICT(lesson_id) DO UPDATE SET
			start_time=excluded.start_time, end_time=excluded.end_time,
			classroom_name=excluded.classroom_name, teacher=excluded.teacher,
			class_id=excluded.class_id, main_id=excluded.main_id, room_code=excluded.room_code,
			record=excluded.record, playback_status=excluded.playback_status,
			playback_url=excluded.playback_url, media_id=excluded.media_id,
			auth_exp=excluded.auth_exp, raw=excluded.raw,
			class_code=excluded.class_code, report_url=excluded.report_url,
			updated_at=excluded.updated_at`,
		l.LessonID, l.StartTime, l.EndTime, l.ClassroomName, l.Teacher, l.ClassID, l.MainID,
		l.RoomCode, l.Record, l.PlaybackStatus, l.PlaybackURL, l.MediaID, l.AuthExp, l.Raw,
		l.ClassCode, l.ReportURL, time.Now().Unix())
	return err
}

func (s *DB) ListLessons(fromSec, toSec int64) ([]LessonRow, error) {
	rows, err := s.db.Query(`SELECT `+lessonCols+` FROM lessons WHERE start_time>=? AND start_time<? ORDER BY start_time`, fromSec, toSec)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []LessonRow
	for rows.Next() {
		l, err := scanLesson(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, l)
	}
	return out, nil
}

// 回放列表: record=1 的课 (过去已发生), 按时间倒序
func (s *DB) ListPlaybacks() ([]LessonRow, error) {
	rows, err := s.db.Query(`SELECT `+lessonCols+` FROM lessons WHERE record=1 AND start_time<=? ORDER BY start_time DESC LIMIT 500`, time.Now().Unix())
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []LessonRow
	for rows.Next() {
		l, err := scanLesson(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, l)
	}
	return out, nil
}

// 某课程(班级)的全部讲次, 按时间正序
func (s *DB) ListClassLessons(classID string) ([]LessonRow, error) {
	rows, err := s.db.Query(`SELECT `+lessonCols+` FROM lessons WHERE class_id=? ORDER BY start_time`, classID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []LessonRow
	for rows.Next() {
		l, err := scanLesson(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, l)
	}
	return out, nil
}

func (s *DB) GetLesson(id string) (*LessonRow, error) {
	row := s.db.QueryRow(`SELECT `+lessonCols+` FROM lessons WHERE lesson_id=?`, id)
	l, err := scanLesson(row)
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

// ---- classes ----
type ClassSummary struct {
	ClassID       string
	Name          string
	Code          string
	Teacher       string
	LessonCount   int
	PlaybackCount int
	FirstTime     int64
	LastTime      int64
	FirstLesson   string // 无权威班级名时, 从首个讲次名推导
}

// UpsertClass 写入班级元数据; my-classes 来源的名称优先级最高
func (s *DB) UpsertClass(classID, name, code, teacher, source string) {
	if classID == "" {
		return
	}
	_, err := s.db.Exec(`INSERT INTO classes(class_id,name,code,teacher,source,updated_at) VALUES(?,?,?,?,?,?)
		ON CONFLICT(class_id) DO UPDATE SET
			name    = CASE WHEN excluded.name!='' AND (excluded.source='my-classes' OR classes.name='') THEN excluded.name ELSE classes.name END,
			code    = CASE WHEN excluded.code!='' THEN excluded.code ELSE classes.code END,
			teacher = CASE WHEN excluded.teacher!='' THEN excluded.teacher ELSE classes.teacher END,
			source  = CASE WHEN excluded.source='my-classes' THEN 'my-classes' ELSE classes.source END,
			updated_at = excluded.updated_at`,
		classID, name, code, teacher, source, time.Now().Unix())
	if err != nil {
		log.Println("[db] UpsertClass", err)
	}
}

// ListClasses 按班级聚合全部讲次 (含未在 my-classes 中的历史班级)
func (s *DB) ListClasses() ([]ClassSummary, error) {
	rows, err := s.db.Query(`SELECT l.class_id,
			COALESCE(c.name,''), COALESCE(c.code,''), COALESCE(c.teacher,''),
			COUNT(*),
			COALESCE(SUM(CASE WHEN l.playback_status=1 AND l.playback_url!='' THEN 1 ELSE 0 END),0),
			MIN(l.start_time), MAX(l.end_time),
			(SELECT x.classroom_name FROM lessons x WHERE x.class_id=l.class_id ORDER BY x.start_time LIMIT 1)
		FROM lessons l LEFT JOIN classes c ON c.class_id=l.class_id
		WHERE l.class_id!=''
		GROUP BY l.class_id
		ORDER BY MAX(l.end_time) DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []ClassSummary
	for rows.Next() {
		var c ClassSummary
		var firstLesson sql.NullString
		if err := rows.Scan(&c.ClassID, &c.Name, &c.Code, &c.Teacher, &c.LessonCount,
			&c.PlaybackCount, &c.FirstTime, &c.LastTime, &firstLesson); err != nil {
			return nil, err
		}
		c.FirstLesson = firstLesson.String
		out = append(out, c)
	}
	return out, nil
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
