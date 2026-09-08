package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
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
	LessonID      string `json:"lesson_id"`
	ClassroomName string `json:"classroom_name"`
	StartTime     string `json:"start_time"`
	EndTime       string `json:"end_time"`
	MainID        any    `json:"mainId"`
	ClassID       any    `json:"class_id"`
	RoomCode      string `json:"room_code"`
	Record        int    `json:"record"`
	Teacher       struct {
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
		return fmt.Sprintf("%.0f", v)
	}
	return ""
}

// FetchSchedule 拉课表并转行
func FetchSchedule(token, uid string, fromSec, toSec int64) ([]*LessonRow, error) {
	u := fmt.Sprintf("%s/api/schedule/my?userId=%s&queryType=1&startDate=%d&endDate=%d&token=%s",
		apiBase, url.QueryEscape(uid), fromSec, toSec, url.QueryEscape(token))
	req, _ := http.NewRequest("GET", u, nil)
	req.Header.Set("User-Agent", "xdf-api/1.0")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 32<<20))
	var r struct {
		Code int         `json:"code"`
		Msg  string      `json:"msg"`
		Data []rbxLesson `json:"data"`
	}
	if err := json.Unmarshal(body, &r); err != nil {
		return nil, err
	}
	if r.Code != 0 {
		return nil, fmt.Errorf("接口返回 code=%d msg=%s", r.Code, r.Msg)
	}
	var out []*LessonRow
	for _, it := range r.Data {
		st, err1 := strconv.ParseInt(it.StartTime, 10, 64)
		et, err2 := strconv.ParseInt(it.EndTime, 10, 64)
		if err1 != nil || err2 != nil {
			continue
		}
		row := &LessonRow{
			LessonID:       it.LessonID,
			StartTime:      st,
			EndTime:        et,
			ClassroomName:  it.ClassroomName,
			Teacher:        it.Teacher.TeacherName,
			ClassID:        fmt.Sprintf("%v", it.ClassID),
			MainID:         it.MainIDStr(),
			RoomCode:       it.RoomCode,
			Record:         it.Record,
			PlaybackStatus: it.Playback.Status,
		}
		if len(it.Playback.URLs) > 0 {
			row.PlaybackURL = it.Playback.URLs[0]
			row.AuthExp = authKeyExpire(row.PlaybackURL)
		}
		if len(it.Playback.MediaID) > 0 {
			row.MediaID = it.Playback.MediaID[0]
		}
		b, _ := json.Marshal(it)
		row.Raw = string(b)
		out = append(out, row)
	}
	return out, nil
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

// ---- 同步 ----
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
	now := time.Now()
	// 过去窗口取 90 天(回放直链会随每次查询重新签发, 老课回放仍可看); 未来 30 天足够排课
	rows, err := FetchSchedule(token, info.Sub, now.AddDate(0, -3, 0).Unix(), now.AddDate(0, 0, 30).Unix())
	if err != nil {
		a.db.SetSetting("last_sync_err", err.Error())
		log.Println("[sync] ", err)
		return
	}
	n := 0
	for _, r := range rows {
		if err := a.db.UpsertLesson(r); err == nil {
			n++
		}
	}
	a.db.SetSetting("last_sync", fmt.Sprintf("%d", time.Now().Unix()))
	a.db.SetSetting("last_sync_err", "")
	log.Printf("[sync] 完成: %d 节课 (共 %d 条记录)", n, len(rows))
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
