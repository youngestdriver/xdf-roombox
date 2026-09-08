// 新东方云教室 API 服务 — Go 单体 (课表日历 + 回放 + 上课提醒)
package main

import (
	"embed"
	"log"
	"net/http"
	"os"
	"path/filepath"
)

//go:embed templates static
var assets embed.FS

func main() {
	port := envOr("PORT", "8080")
	dataDir := envOr("DATA_DIR", "./data")
	adminPass := os.Getenv("ADMIN_PASS")
	if adminPass == "" {
		log.Fatal("必须设置环境变量 ADMIN_PASS (访问本服务的密码)")
	}
	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		log.Fatal("创建数据目录失败: ", err)
	}

	app := NewApp(filepath.Join(dataDir, "xdf-api.db"), adminPass)
	defer app.db.Close()

	AppData = app // web.go 经全局引用

	// 定时任务
	app.cron.AddFunc("*/15 * * * *", func() { app.Sync() })              // 每15分钟同步课表/回放
	app.cron.AddFunc("* * * * *", func() { app.CheckNotify() })          // 每分钟检查上课提醒
	app.cron.Start()
	log.Println("[cron] 已启动: 课表/回放同步每15分钟, 上课提醒每分钟")

	// 启动即同步一次
	go app.Sync()

	mux := http.NewServeMux()
	mux.Handle("/api/", app.auth(http.HandlerFunc(app.handleAPI)))
	mux.Handle("/", app.auth(http.HandlerFunc(app.handlePage)))

	addr := ":" + port
	log.Println("[http] 监听 " + addr + " (密码: ADMIN_PASS)")
	log.Fatal(http.ListenAndServe(addr, mux))
}

func envOr(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}
