package main

import (
	"crypto/subtle"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"
)

var cst = time.FixedZone("CST", 8*3600) // 北京时间, 无需系统时区数据

type ctxKey int

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(v)
}

// ---- 基本认证 (ADMIN_PASS) ----
func (a *App) auth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, pass, ok := r.BasicAuth()
		if !ok || subtle.ConstantTimeCompare([]byte(pass), []byte(a.adminPass)) != 1 {
			w.Header().Set("WWW-Authenticate", `Basic realm="xdf-api"`)
			http.Error(w, "需要登录", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// ---- 页面/静态 ----
func (a *App) handlePage(w http.ResponseWriter, r *http.Request) {
	staticFS, _ := fs.Sub(assets, "static")
	if strings.HasPrefix(r.URL.Path, "/static/") {
		http.StripPrefix("/static/", http.FileServer(http.FS(staticFS))).ServeHTTP(w, r)
		return
	}
	idx, err := assets.ReadFile("templates/index.html")
	if err != nil {
		http.Error(w, "missing template", 500)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write(idx)
}

// ---- API ----
func (a *App) handleAPI(w http.ResponseWriter, r *http.Request) {
	p := strings.TrimPrefix(r.URL.Path, "/api")
	seg := strings.Split(strings.Trim(p, "/"), "/")

	switch {
	case r.Method == "GET" && p == "/status":
		a.apiStatus(w)
	case r.Method == "POST" && p == "/settings":
		a.apiSaveSettings(w, r)
	case r.Method == "POST" && p == "/sync":
		go a.Sync()
		writeJSON(w, 200, map[string]string{"ok": "同步已在后台执行"})
	case r.Method == "GET" && p == "/lessons":
		a.apiLessons(w, r)
	case r.Method == "GET" && p == "/playbacks":
		a.apiPlaybacks(w)
	case (r.Method == "GET" || r.Method == "HEAD") && len(seg) == 3 && seg[0] == "playback" && seg[2] == "media":
		a.apiPlaybackRedirect(w, r, seg[1])
	case (r.Method == "GET" || r.Method == "HEAD") && len(seg) == 3 && seg[0] == "playback" && seg[2] == "dl":
		a.apiPlaybackProxy(w, r, seg[1])
	case r.Method == "POST" && p == "/notify/test":
		a.apiNotifyTest(w)
	default:
		writeJSON(w, 404, map[string]string{"err": "not found"})
	}
}

func (a *App) apiStatus(w http.ResponseWriter) {
	token := a.db.GetSetting("token")
	info, _ := ParseJWT(token)
	lastSyncStr := a.db.GetSetting("last_sync")
	lastSync, _ := strconv.ParseInt(lastSyncStr, 10, 64)
	lessons, playbacks := a.db.Counts()
	mask := ""
	expLeft := int64(-1)
	if token != "" {
		if len(token) > 12 {
			mask = token[:8] + "..." + token[len(token)-6:]
		} else {
			mask = "***"
		}
		if info != nil && info.Exp > 0 {
			expLeft = info.Exp - time.Now().Unix()
		}
	}
	writeJSON(w, 200, map[string]any{
		"token_mask":    mask,
		"token_exp":     expLeft, // 剩余秒, -1=未知/未配置
		"last_sync":     lastSync,
		"last_sync_err": a.db.GetSetting("last_sync_err"),
		"lesson_count":  lessons,
		"playback_count": playbacks,
	})
}

func (a *App) apiSaveSettings(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Token         string `json:"token"`
		WebhookURL    string `json:"webhook_url"`
		WebhookType   string `json:"webhook_type"`
		NotifyMinutes int    `json:"notify_minutes"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeJSON(w, 400, map[string]string{"err": "参数解析失败"})
		return
	}
	if in.Token != "" {
		if _, err := ParseJWT(in.Token); err != nil {
			writeJSON(w, 400, map[string]string{"err": "token 格式不正确"})
			return
		}
		a.db.SetSetting("token", strings.TrimSpace(in.Token))
	}
	if in.WebhookURL != "" {
		a.db.SetSetting("webhook_url", strings.TrimSpace(in.WebhookURL))
	}
	if in.WebhookType != "" {
		a.db.SetSetting("webhook_type", in.WebhookType)
	}
	if in.NotifyMinutes > 0 {
		a.db.SetSetting("notify_minutes", strconv.Itoa(in.NotifyMinutes))
	}
	go a.Sync()
	writeJSON(w, 200, map[string]string{"ok": "已保存"})
}

func (a *App) apiLessons(w http.ResponseWriter, r *http.Request) {
	fromSec := at8(time.Now().Unix()).AddDate(0, 0, -30).Unix()
	toSec := at8(time.Now().Unix()).AddDate(0, 0, 30).Unix()
	if v := r.URL.Query().Get("from"); v != "" {
		if n, err := strconv.ParseInt(v, 10, 64); err == nil {
			fromSec = n
		}
	}
	if v := r.URL.Query().Get("to"); v != "" {
		if n, err := strconv.ParseInt(v, 10, 64); err == nil {
			toSec = n
		}
	}
	rows, err := a.db.ListLessons(fromSec, toSec)
	if err != nil {
		writeJSON(w, 500, map[string]string{"err": err.Error()})
		return
	}
	events := []map[string]any{}
	for _, l := range rows {
		title := fmt.Sprintf("%s %s", at8(l.StartTime).Format("15:04"), l.ClassroomName)
		events = append(events, map[string]any{
			"id":    l.LessonID,
			"title": title,
			"start": at8(l.StartTime).Format(time.RFC3339),
			"end":   at8(l.EndTime).Format(time.RFC3339),
			"extendedProps": map[string]any{
				"lessonId":  l.LessonID,
				"teacher":   l.Teacher,
				"roomCode":  l.RoomCode,
				"record":    l.Record,
				"playbackStatus": l.PlaybackStatus,
			},
		})
	}
	writeJSON(w, 200, events)
}

func (a *App) apiPlaybacks(w http.ResponseWriter) {
	rows, err := a.db.ListPlaybacks()
	if err != nil {
		writeJSON(w, 500, map[string]string{"err": err.Error()})
		return
	}
	now := time.Now().Unix()
	out := []map[string]any{}
	for _, l := range rows {
		expired := l.AuthExp > 0 && now > l.AuthExp
		out = append(out, map[string]any{
			"lesson_id":   l.LessonID,
			"start":       l.StartTime,
			"title":       l.ClassroomName,
			"teacher":     l.Teacher,
			"main_id":     l.MainID,
			"status":      l.PlaybackStatus, // 0=未生成 1=已生成
			"has_url":     l.PlaybackURL != "",
			"expired":     expired,
			"auth_exp":    l.AuthExp,
			"media_id":    l.MediaID,
		})
	}
	writeJSON(w, 200, out)
}

func (a *App) apiPlaybackRedirect(w http.ResponseWriter, r *http.Request, id string) {
	l, err := a.db.GetLesson(id)
	if err != nil || l.PlaybackURL == "" {
		http.Error(w, "回放不存在或未生成", 404)
		return
	}
	if l.AuthExp > 0 && time.Now().Unix() > l.AuthExp {
		http.Error(w, "回放签名已过期, 等待同步刷新后重试", 410)
		return
	}
	http.Redirect(w, r, l.PlaybackURL, http.StatusFound)
}

// apiPlaybackProxy 流式代理下载 (支持 Range/断点)
func (a *App) apiPlaybackProxy(w http.ResponseWriter, r *http.Request, id string) {
	l, err := a.db.GetLesson(id)
	if err != nil || l.PlaybackURL == "" {
		http.Error(w, "回放不存在或未生成", 404)
		return
	}
	if l.AuthExp > 0 && time.Now().Unix() > l.AuthExp {
		http.Error(w, "回放签名已过期, 等待同步刷新后重试", 410)
		return
	}
	req, err := http.NewRequest("GET", l.PlaybackURL, nil)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	if rng := r.Header.Get("Range"); rng != "" {
		req.Header.Set("Range", rng)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		http.Error(w, "获取上游失败: "+err.Error(), 502)
		return
	}
	defer resp.Body.Close()
	h := w.Header()
	if ct := resp.Header.Get("Content-Type"); ct != "" {
		h.Set("Content-Type", ct)
	}
	if cl := resp.Header.Get("Content-Length"); cl != "" {
		h.Set("Content-Length", cl)
	}
	if ar := resp.Header.Get("Accept-Ranges"); ar != "" {
		h.Set("Accept-Ranges", ar)
	}
	name := fmt.Sprintf("%s_%s.mp4", at8(l.StartTime).Format("20060102_1504"), l.MainID)
	h.Set("Content-Disposition", fmt.Sprintf(`attachment; filename="%s"`, name))
	w.WriteHeader(resp.StatusCode)
	if _, err := io.Copy(w, resp.Body); err != nil {
		log.Println("[proxy] 传输中断: ", err)
	}
}

func (a *App) apiNotifyTest(w http.ResponseWriter) {
	kind := a.db.GetSetting("webhook_type")
	hook := a.db.GetSetting("webhook_url")
	title := "xdf-api 测试通知"
	content := fmt.Sprintf("这是一条测试通知 (%s)", time.Now().In(cst).Format("2006-01-02 15:04:05"))
	if err := SendWebhook(kind, hook, title, content); err != nil {
		writeJSON(w, 500, map[string]string{"err": err.Error()})
		return
	}
	writeJSON(w, 200, map[string]string{"ok": "已发送"})
}
