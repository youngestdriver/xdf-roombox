package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"
)

const apiBase = "https://api.roombox.xdf.cn"

// ---- JWT 解析 (只读 payload, 不验签) ----
type JWTInfo struct {
	Sub string `json:"sub"`
	Exp int64  `json:"exp"`
	Iat int64  `json:"iat"`
}

func ParseJWT(token string) (*JWTInfo, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return nil, fmt.Errorf("非法 JWT 格式")
	}
	b, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return nil, err
	}
	var info JWTInfo
	if err := json.Unmarshal(b, &info); err != nil {
		return nil, err
	}
	return &info, nil
}

// ---- schedule API ----
type rbxLesson struct {
	LessonID       string `json:"lesson_id"`
	ClassroomName  string `json:"classroom_name"`
	StartTime      string `json:"start_time"`
	EndTime        string `json:"end_time"`
	MainID         any    `json:"mainId"`
	ClassID        any    `json:"class_id"`
	ClassCode      string `json:"class_code"`
	RoomCode       string `json:"room_code"`
	Record         int    `json:"record"`
	StudyReportURL string `json:"studyReportUrl"`
	Teacher        struct {
		TeacherName string `json:"teacherName"`
	} `json:"teacher"`
	Playback struct {
		Status  int      `json:"status"`
		URLs    []string `json:"urls"`
		MediaID []string `json:"mediaIds"`
	} `json:"playback"`
}

func (l *rbxLesson) MainIDStr() string {
	switch v := l.MainID.(type) {
	case string:
		return v
	case float64:
		return strconv.FormatInt(int64(v), 10)
	}
	return ""
}

func (l *rbxLesson) ClassIDStr() string {
	switch v := l.ClassID.(type) {
	case string:
		return v
	case float64:
		return strconv.FormatInt(int64(v), 10)
	}
	return ""
}

// ToRow 把接口讲次转成数据库行 (schedule/my 与 class/lessons 结构一致)
func (l *rbxLesson) ToRow() *LessonRow {
	st, err1 := strconv.ParseInt(l.StartTime, 10, 64)
	et, err2 := strconv.ParseInt(l.EndTime, 10, 64)
	if err1 != nil || err2 != nil {
		return nil
	}
	row := &LessonRow{
		LessonID:       l.LessonID,
		StartTime:      st,
		EndTime:        et,
		ClassroomName:  l.ClassroomName,
		Teacher:        l.Teacher.TeacherName,
		ClassID:        l.ClassIDStr(),
		ClassCode:      l.ClassCode,
		MainID:         l.MainIDStr(),
		RoomCode:       l.RoomCode,
		Record:         l.Record,
		PlaybackStatus: l.Playback.Status,
		ReportURL:      l.StudyReportURL,
	}
	if len(l.Playback.URLs) > 0 {
		row.PlaybackURL = l.Playback.URLs[0]
		row.AuthExp = authKeyExpire(row.PlaybackURL)
	}
	if len(l.Playback.MediaID) > 0 {
		row.MediaID = l.Playback.MediaID[0]
	}
	b, _ := json.Marshal(l)
	row.Raw = string(b)
	return row
}

// FetchSchedule 按时间窗拉课表 (全量历史扫描的基础)
func FetchSchedule(token, uid string, fromSec, toSec int64) ([]*LessonRow, error) {
	u := fmt.Sprintf("%s/api/schedule/my?userId=%s&queryType=1&startDate=%d&endDate=%d&token=%s",
		apiBase, url.QueryEscape(uid), fromSec, toSec, url.QueryEscape(token))
	var r struct {
		Code int         `json:"code"`
		Msg  string      `json:"msg"`
		Data []rbxLesson `json:"data"`
	}
	if err := callXdfAPI(u, &r); err != nil {
		return nil, err
	}
	if r.Code != 0 {
		return nil, fmt.Errorf("接口返回 code=%d msg=%s", r.Code, r.Msg)
	}
	var out []*LessonRow
	for i := range r.Data {
		if row := r.Data[i].ToRow(); row != nil {
			out = append(out, row)
		}
	}
	return out, nil
}

// ---- 课程/讲次 ----
type rbxClass struct {
	ClassID     any    `json:"classId"`
	ClassName   string `json:"className"`
	ClassCode   string `json:"classCode"`
	Channel     int    `json:"channel"`
	StartTime   string `json:"startTime"`
	EndTime     string `json:"endTime"`
	ExpiredTime string `json:"expiredTime"`
	Teacher     struct {
		TeacherName string `json:"teacherName"`
	} `json:"teacher"`
}

func (c *rbxClass) ClassIDStr() string {
	switch v := c.ClassID.(type) {
	case string:
		return v
	case float64:
		return strconv.FormatInt(int64(v), 10)
	}
	return ""
}

// FetchClasses 返回"我的课程"列表 (仅当前有效班级, pageSize 2000)
func FetchClasses(token string) ([]rbxClass, error) {
	u := fmt.Sprintf("%s/api/schedule/my-classes?pageSize=2000&version=2.74.3.2063&token=%s",
		apiBase, url.QueryEscape(token))
	var r struct {
		Code int `json:"code"`
		Data struct {
			List  []rbxClass `json:"list"`
			Total int        `json:"total"`
		} `json:"data"`
	}
	if err := callXdfAPI(u, &r); err != nil {
		return nil, err
	}
	if r.Code != 200 {
		return nil, fmt.Errorf("接口返回 code=%d", r.Code)
	}
	return r.Data.List, nil
}

// FetchClassLessons 返回某班级的全部讲次 (含历史与未来; 回放直链每次重新签发)
func FetchClassLessons(token, classID string) ([]*LessonRow, error) {
	u := fmt.Sprintf("%s/api/schedule/class/lessons?classId=%s&version=2.74.3.2063&token=%s",
		apiBase, url.QueryEscape(classID), url.QueryEscape(token))
	var r struct {
		Code int `json:"code"`
		Data struct {
			List []rbxLesson `json:"list"`
		} `json:"data"`
	}
	if err := callXdfAPI(u, &r); err != nil {
		return nil, err
	}
	if r.Code != 200 {
		return nil, fmt.Errorf("接口返回 code=%d", r.Code)
	}
	var out []*LessonRow
	for i := range r.Data.List {
		if row := r.Data.List[i].ToRow(); row != nil {
			out = append(out, row)
		}
	}
	return out, nil
}

func callXdfAPI(u string, out any) error {
	req, _ := http.NewRequest("GET", u, nil)
	req.Header.Set("User-Agent", "xdf-api/1.0")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 32<<20))
	return json.Unmarshal(body, out)
}

// authKeyExpire 从 auth_key=exp-rand-uid-sig 中取过期时间
func authKeyExpire(uri string) int64 {
	if i := strings.Index(uri, "auth_key="); i >= 0 {
		v := uri[i+len("auth_key="):]
		if j := strings.Index(v, "-"); j > 0 {
			if e, err := strconv.ParseInt(v[:j], 10, 64); err == nil {
				return e
			}
		}
	}
	return 0
}

// ---- 班级名推导 ----
var lessonNoRe = regexp.MustCompile(`第[0-9]+([\-—~、][0-9]+)*讲.*$`)

// deriveClassName 从讲次名推导班级名: "XX课第3讲" -> "XX课"
func deriveClassName(lessonName string) string {
	s := strings.TrimSpace(lessonNoRe.ReplaceAllString(lessonName, ""))
	if s == "" {
		return lessonName
	}
	return s
}

// syncFromTime 全量扫描起点 (SYNC_FROM 环境变量, 默认 2024-01-01)
func syncFromTime() time.Time {
	def := time.Date(2024, 1, 1, 0, 0, 0, 0, time.Local)
	s := strings.TrimSpace(os.Getenv("SYNC_FROM"))
	if s == "" {
		return def
	}
	t, err := time.ParseInLocation("2006-01-02", s, time.Local)
	if err != nil {
		log.Printf("[sync] SYNC_FROM=%q 解析失败, 使用默认 %s", s, def.Format("2006-01-02"))
		return def
	}
	return t
}

// ---- 同步 (全量: 元数据 + 全历史窗口扫描 + 现有班级讲次) ----
func (a *App) Sync() {
	a.mu.Lock()
	defer a.mu.Unlock()
	token := a.db.GetSetting("token")
	if token == "" {
		a.db.SetSetting("last_sync_err", "未配置 token")
		return
	}
	info, err := ParseJWT(token)
	if err != nil || info.Sub == "" {
		a.db.SetSetting("last_sync_err", "token 无法解析")
		return
	}
	if info.Exp > 0 && time.Now().Unix() > info.Exp {
		a.db.SetSetting("last_sync_err", "token 已过期, 请到设置页更新")
		return
	}

	// 1) 当前课程元数据 (权威班级名/编码)
	classes, err := FetchClasses(token)
	if err != nil {
		log.Println("[sync] my-classes:", err)
	}
	for _, c := range classes {
		a.db.UpsertClass(c.ClassIDStr(), c.ClassName, c.ClassCode, c.Teacher.TeacherName, "my-classes")
	}

	// 2) 全历史窗口扫描 (按年分片): 发现全部班级(含已从课程列表消失的历史班)并刷新回放直链
	from := syncFromTime()
	to := time.Now().AddDate(0, 0, 180)
	total, okChunks, chunks := 0, 0, 0
	earliest := map[string]*LessonRow{}
	for start := from; start.Before(to); {
		end := start.AddDate(0, 0, 365)
		if end.After(to) {
			end = to
		}
		chunks++
		rows, err := FetchSchedule(token, info.Sub, start.Unix(), end.Unix())
		if err != nil {
			log.Printf("[sync] 窗口 %s~%s: %v", start.Format("2006-01-02"), end.Format("2006-01-02"), err)
		} else {
			okChunks++
			for _, r := range rows {
				if err := a.db.UpsertLesson(r); err == nil {
					total++
				}
				if r.ClassID != "" {
					if cur, ok := earliest[r.ClassID]; !ok || r.StartTime < cur.StartTime {
						earliest[r.ClassID] = r
					}
				}
			}
		}
		start = end
	}

	// 3) 派生班级元数据 (仅填补无名班级, 不覆盖 my-classes 权威名)
	for cid, r := range earliest {
		a.db.UpsertClass(cid, deriveClassName(r.ClassroomName), r.ClassCode, r.Teacher, "derived")
	}

	// 4) 现有班级全部讲次 (含远期排课与学习报告链接等富字段)
	full := 0
	for _, c := range classes {
		rows, err := FetchClassLessons(token, c.ClassIDStr())
		if err != nil {
			log.Println("[sync] class/lessons", c.ClassIDStr(), err)
			continue
		}
		for _, r := range rows {
			if err := a.db.UpsertLesson(r); err == nil {
				full++
			}
		}
	}

	if okChunks == 0 {
		a.db.SetSetting("last_sync_err", fmt.Sprintf("课表接口失败 (0/%d 窗口成功)", chunks))
		return
	}
	a.db.SetSetting("last_sync", fmt.Sprintf("%d", time.Now().Unix()))
	a.db.SetSetting("last_sync_err", "")
	log.Printf("[sync] 完成: 窗口 %d/%d, 扫描 %d 讲次, 班级 %d 个, 现有班讲次 %d", okChunks, chunks, total, len(earliest), full)
}

// ---- 上课提醒 ----
func (a *App) CheckNotify() {
	a.mu.Lock()
	defer a.mu.Unlock()
	wh := a.db.GetSetting("webhook_url")
	if wh == "" {
		return
	}
	token := a.db.GetSetting("token")
	if token == "" {
		return
	}
	minStr := a.db.GetSetting("notify_minutes")
	if minStr == "" {
		minStr = "5"
	}
	minutes, _ := strconv.Atoi(minStr)
	if minutes <= 0 {
		minutes = 5
	}
	now := time.Now()
	rows, err := a.db.ListLessons(now.Add(-30*time.Minute).Unix(), now.Add(2*24*time.Hour).Unix())
	if err != nil {
		return
	}
	for _, l := range rows {
		if l.Notified == 1 {
			continue
		}
		diff := l.StartTime - now.Unix()
		if diff > 0 && diff <= int64(minutes*60) {
			title := fmt.Sprintf("上课提醒: %s", l.ClassroomName)
			content := fmt.Sprintf("「%s」%s 开课: %s 主讲: %s",
				l.ClassroomName, at8(l.StartTime).Format("2006-01-02 15:04"),
				at8(l.EndTime).Format("15:04"),
				orDash(l.Teacher))
			if err := SendWebhook(a.db.GetSetting("webhook_type"), wh, title, content); err != nil {
				log.Println("[notify] 失败(稍后重试): ", err)
				continue // 不标记, 下分钟重试
			}
			a.db.MarkNotified(l.LessonID)
			log.Println("[notify] 已推送: ", title)
		}
	}
}
