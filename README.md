# xdf_roombox — 新东方云教室工具集

三块内容：**接口逆向资产**（课表/课堂 API、前端 bundle、抓包脚本）、**Windows 桌面助手**（进教室/签到/退出/评价全自动）、**配套服务 xdf-api**（课表日历 / 回放 / 上课提醒）。

## 目录结构

**桌面助手**

| 文件 | 说明 |
|---|---|
| `app/` | **云教室助手（.NET 8 WPF）**：上课全流程自动化，见下节 |
| `class_watch.ps1` | PowerShell 版全天监听（助手的前身）：进教室 / 退出 / 评价 / 连堂 |
| `auto_enter.ps1` | 更早的单功能脚本：课前自动点「进入教室」 |

**接口逆向**

| 文件 | 说明 |
|---|---|
| `endpoints.md` / `endpoints_raw.json` | 课表侧 API 清单（人读 / 机读）：域名、REST 路径、日志 URL、实测接口 |
| `extract_endpoints.ps1` | 重新提取（应用发新版后重跑） |
| `endpoints_classroom.md` / `endpoints_classroom_raw.json` | 课上（课堂/白板）接口清单：96 路径 + 108 条实时 XHR 快照 |
| `extract_classroom_apis.ps1` | 课上接口抓取脚本（需在课堂中运行） |
| `ws_capture.ps1` | WebSocket 信令捕获：`-Mode Now` 反查当前连接 / `-Mode Watch` 订阅 Network 事件流抓帧 |
| `comment_page.html` / `evaluation_capture.json` | 课后评价页源码（含内联提交逻辑）与抓包快照 |
| `watch_evaluation.ps1` / `submit_evaluation.ps1` | 评价窗口监听（只观察）/ 自动提交 |
| `js/` `js_coursetable/` | 课表 webapp 前端 bundle（反编译参考） |
| `js_wb/` `js_wbtools/` `js_sdk/` | 课堂主应用 / 互动工具(点名/签到/抢答) / IM+白板 SDK 的 bundle |

**配套服务**

| 文件 | 说明 |
|---|---|
| `server/` | **xdf-api 服务（Go 单体, Docker）**：课表日历 + 课程分类 + 回放（在线观看/下载）+ 上课提醒 Webhook，见 `server/README.md` |
| `TEST_RECORDS.md` | 实战测试记录（首次自动进教室、课上接口抓取、WS 信令、评价提交等） |

相关工具（不在本目录）：CDP 驱动脚本 `C:\Users\PaperCrane\xdf-cdp\cdp.ps1`，
用法 `.\cdp.ps1 -Expr '<JS>'` 可向正在运行的云教室页面注入任意 JS。

## 桌面助手（app/）

.NET 8 WPF 应用，把上课全流程自动化：

- **进教室**：课前 15 分钟（可配）在课表页找匹配「课程名 + 开始时间」的「进入教室」按钮并点击，开课后 10 分钟内仍可补进；页面失效（按钮整片不存在 / 状态停在过去）时自动强制刷新课表页自愈
- **签到 + 清理弹窗**：进入课堂后点「签到」，并关掉摄像头/麦克风权限提示
- **下课退出**：下课后 5 分钟（可配）关闭课堂窗口；弹出的 Qt 原生「确定要退出吗？」确认框用 PostMessage 后台点「确定」（不需要窗口在前台、不移动鼠标）
- **课后评价**：评价窗口弹出后按配置档位自动选项并提交
- **连堂**：退出后接着处理下一节课

运行前提：云教室以 `--remote-debugging-port=9222` 启动。助手检测到它没在跑时，会自己带上调试参数和防后台节流参数启动它。

配置与状态都在 `%APPDATA%\XdfRoombox\`：

| 文件 | 说明 |
|---|---|
| `config.json` | 云教室路径、调试端口、四个自动化开关、时间参数、评价档位 |
| `state.json` | 每节课的 entered / exited / evaluated 记录，保证每节课只动作一次 |
| `app.log` | 运行日志（界面里也有一份） |

构建与运行（需 .NET 8 SDK）：

```powershell
dotnet publish app/XdfRoombox.csproj -c Release -r win-x64 -p:PublishSingleFile=true --self-contained false -o app/bin/Release/net8.0-windows/win-x64/publish
```

运行 `app/bin/Release/net8.0-windows/win-x64/publish/XdfRoombox.exe`。注意**单实例保护**：重复启动会弹「已在运行中」提示，要重启请先关掉主窗口。

排错：日志里 `NOBUTTON all=N clickable=N vis=… ready=…` 是进教室时的页面状态——`all=0` 页面空了（会自动刷新，刷新 3 次仍无效会报错提示人工检查），`all>0 clickable=0` 是课表页还没放行。

## 认证

API 用 JWT（HS512，`sub`=用户ID），通过 URL 查询参数 `token=` 传递，有效期约 14 天。
获取方式二选一：

- 课表页地址栏（应用以 `--remote-debugging-port=9222` 启动后看 `http://127.0.0.1:9222/json`）
- 应用日志 `%APPDATA%\RoomboxData\logs\<pid>\Roombox_*.log` 里的 `fetchToken/<jwt>`

## 调用示例（PowerShell）

```powershell
$token = '<JWT>'  # 见上
$uid = '<UID>'
$start = ([DateTimeOffset]::Parse('2026-09-08T00:00:00+08:00')).ToUnixTimeSeconds()
$end   = ([DateTimeOffset]::Parse('2026-09-15T00:00:00+08:00')).ToUnixTimeSeconds()
Invoke-RestMethod "https://api.roombox.xdf.cn/api/schedule/my?userId=$uid&queryType=1&startDate=$start&endDate=$end&token=$token"
```

## 旧脚本

`auto_enter.ps1` —— 只做「课前自动进教室」：

```powershell
pwsh -File auto_enter.ps1 -Loop             # 常驻监控（每30秒查一次）
pwsh -File auto_enter.ps1 -CheckNow -DryRun # 演练：只报告不点击
pwsh -File auto_enter.ps1 -RestartIfNoDebug -Loop  # 应用已开但没带调试口时，自动重启带调试口
```

`class_watch.ps1` 是它的升级版（全天监听 + 退出 + 评价 + 连堂），功能已被 `app/` 的助手覆盖。

开机自启（任务计划程序，登录时运行；把程序换成助手同理）：

```
schtasks /create /tn "xdf-auto-enter" /tr "pwsh -NoProfile -File C:\Users\PaperCrane\Desktop\code\xdf_roombox\auto_enter.ps1 -Loop" /sc onlogon
```

注意：默认要求云教室以 `--remote-debugging-port=9222` 启动，否则只有 `-RestartIfNoDebug` 模式会自动重启它。

## 盲区

- 桌面主窗体 UI（localhtml / webapps.roombox.xdf.cn）的前端 bundle 在 CEF 缓存与 resources.pak 中，
  本清单尚未覆盖 —— 需要时可用 `RoomboxData\Cache\<UID>\` 下的 CEF 缓存或直接抓包补齐。
- 课上信令已定位到 `wss://im-tx-sh8.roombox.xdf.cn/ws`（腾讯云上海节点），私有二进制 protobuf 封装、
  心跳约 30s —— 帧结构尚未还原，需协议定义（protoc 逆向或多种帧比对）。
- ⚠️ 课后评价窗口 URL 的 `commit` 参数含**本机 MAC 地址**，该 URL 不要外发。
