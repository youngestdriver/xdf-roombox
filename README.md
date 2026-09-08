# xdf_roombox — 新东方云教室 API 接口收藏

## 目录结构

| 文件 | 说明 |
|---|---|
| `endpoints.md` | API 清单（人读）：域名、REST 路径、日志 URL、实测接口 |
| `endpoints_raw.json` | 原始提取数据（机读）：`js_api_paths` / `domains` / `js_full_urls` / `log_urls` |
| `extract_endpoints.ps1` | 重新提取脚本（应用发新版后重跑：`powershell -File extract_endpoints.ps1`） |
| `TEST_RECORDS.md` | 实战测试记录（2026-09-07 自动进教室首次实战：通过；课上接口抓取） |
| `endpoints_classroom.md` / `endpoints_classroom_raw.json` | 课上（课堂/白板）接口清单：96 路径 + 108 条实时 XHR 快照 |
| `extract_classroom_apis.ps1` | 课上接口抓取脚本（需在课堂中运行） |
| `js_wb/` `js_wbtools/` `js_sdk/` | 课堂主应用 / 互动工具(点名/签到/抢答) / IM+白板 SDK 的 bundle |
| `ws_capture.ps1` | WebSocket 信令捕获：`-Mode Now` 反查当前连接 / `-Mode Watch` 订阅 Network 事件流抓帧 |
| `server/` | **xdf-api 服务（Go 单体, Docker）**：课表日历 + 回放（在线观看/下载）+ 上课提醒 Webhook，见 server/README.md |
| `js/` | 课表 webapp 前端 bundle 源文件（main / 3 / vendors chunk，反编译参考） |
| `raw/` | index.html |

相关工具（不在本目录）：CDP 驱动脚本 `C:\Users\PaperCrane\xdf-cdp\cdp.ps1`，
用法 `.\cdp.ps1 -Expr '<JS>'` 可向正在运行的云教室页面注入任意 JS。

## 认证

API 用 JWT（HS512，`sub`=用户ID），通过 URL 查询参数 `token=` 传递，有效期约 14 天。
获取方式二选一：

- 课表页地址栏（app 以 `--remote-debugging-port=9222` 启动后看 `http://127.0.0.1:9222/json`）
- 应用日志 `%APPDATA%\RoomboxData\logs\<pid>\Roombox_*.log` 里的 `fetchToken/<jwt>`

## 调用示例（PowerShell）

```powershell
$token = '<JWT>'  # 见上
$uid = '25527722'
$start = ([DateTimeOffset]::Parse('2026-09-08T00:00:00+08:00')).ToUnixTimeSeconds()
$end   = ([DateTimeOffset]::Parse('2026-09-15T00:00:00+08:00')).ToUnixTimeSeconds()
Invoke-RestMethod "https://api.roombox.xdf.cn/api/schedule/my?userId=$uid&queryType=1&startDate=$start&endDate=$end&token=$token"
```

## 自动进教室（auto_enter.ps1）

上课前 5 分钟自动点击课表页「进入教室」按钮。它自己会：确认/启动带调试口的云教室 → 从页面 URL 取 token → REST 拉课表 → 找到临近开课的课 → 在课表页找到匹配「课程名+开始时间」的按钮并点击 → 验证是否进入并记录状态（`auto_enter_state.json`，每节课只自动进一次；检测到已有课堂窗口时会让位不重复进）。

```powershell
pwsh -File auto_enter.ps1 -Loop            # 常驻监控（每30秒查一次）
pwsh -File auto_enter.ps1 -CheckNow -DryRun   # 演练：只报告不点击
pwsh -File auto_enter.ps1 -RestartIfNoDebug -Loop  # 应用已开但没带调试口时，自动重启带调试口
```

开机自启（任务计划程序，登录时运行）：

```
schtasks /create /tn "xdf-auto-enter" /tr "pwsh -NoProfile -File C:\Users\PaperCrane\Desktop\code\xdf_roombox\auto_enter.ps1 -Loop" /sc onlogon
```

注意：默认要求云教室以 `--remote-debugging-port=9222` 启动，否则只有 `-RestartIfNoDebug` 模式会自动重启它。

## 盲区

- 桌面主窗体 UI（localhtml / webapps.roombox.xdf.cn）的前端 bundle 在 CEF 缓存与 resources.pak 中，
  本清单尚未覆盖 —— 需要时可用 `RoomboxData\Cache\25527722\` 下的 CEF 缓存或直接抓包补齐。
- 课上信令 `im.roombox.xdf.cn/polaris/v1/tcp_*` 是私有二进制协议，需 CDP Network 监听或 mitmproxy 还原。
