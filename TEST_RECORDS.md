# 测试记录

## 2026-09-07 — 自动进教室首次实战（✅ 通过）

**环境**
- 应用: 新东方云教室 Roombox 2.74.3.2063（Qt + CEF），以 `--remote-debugging-port=9222` 运行
- 脚本: `auto_enter.ps1`（`-CheckNow` 单次模式，非 DryRun）
- 目标课程: lesson `762706268398689` 「27考研专业课一对一150（30小时）」 2026-09-07 19:30 直播课（主讲: 顾存存）

**时间线**
- `19:35:22` 脚本判定临课（开课后 5 分 23 秒，处于 `[now-10min, now+5min]` 宽限窗），在课表页定位到匹配「课程名 + 19:30」的 `button.enter`，执行点击（日志: `CLICKED@19:30 enter`）
- `19:35:34` 教室以**新窗口**打开：「直播」页 `assets.coursebox.xdf.cn/wb/<hash>/index.html#/?language=cn&uid=...`（前端 bundle 中 `window.open` 模式印证）
- 同刻脚本首次验证误报「页面未见变化」——验证规则未识别 `/wb/` 课堂 URL，且等待仅 12s

**结果**
- 19:40 前进入教室 ✔
- 仅一次 ✔（`auto_enter_state.json` 中 `status: entered`，后续运行对该 lesson 一律跳过）
- 状态文件: `auto_enter_state.json`（lesson_id/name/start/status/entered_at）

**修复（已合入 `auto_enter.ps1`）**
- 课堂页识别规则扩展: `quickLive|classroom|/web/|/wb/|coursebox\.xdf\.cn/wb`（「已有课堂窗口则让位」+「进教室验证」两处）
- 进教室后验证等待: 12s → 20s

**复现**
```
pwsh -File auto_enter.ps1 -CheckNow -DryRun   # 演练
pwsh -File auto_enter.ps1 -CheckNow           # 真执行
pwsh -File auto_enter.ps1 -Loop               # 常驻
```

**遗留 / 下一步**
- 课堂页（`assets.coursebox.xdf.cn/wb/...`）是独立 Web 应用，可抓其前端 bundle 补全「课上」接口（聊天、白板、成员列表等）
- `im.roombox.xdf.cn/polaris/v1/tcp_*` 信令协议待还原（CDP Network/Frame 监听）

## 2026-09-07 — 课上接口抓取（✅ 完成）

**环境**: 课堂直播中（19:30 一对一，wb 白板页打开），CDP 9222 连通。

**成果**
- 实时 XHR 快照 108 条（含 `_mode=dev` 等真实参数，token 已打码）→ `endpoints_classroom_raw.json`
- 下载 35 个前端 bundle：课堂主应用（`js_wb/`，白板+主界面）、互动工具（`js_wbtools/`，点名/抢答/红包/签到）、`js_sdk/`（wbSdk + im.sdk 1.1.13）
- 提取课上 API 路径 **96 条**：签到（`matrix/classroom/sign-in/*`）、答题（`/quiz/api/v1/*`、`/api/v1/quiz/*`）、投票（`/api/vote/*`）、白板（`blackboard/*`）、魔法教师（`magic-teacher/*`）、课件、学生管理、OSS 上传等
- 域名: bundle 内为 `*.yclassroom.com`（生产镜像 `*.roombox.xdf.cn`，运行时按映射互换）

**未决**
- `im.roombox.xdf.cn/polaris/v1/ws_servers` 实测 404（err_code 600104，需 SDK 层鉴权头；页面 SDK 同样收到 404 后回退默认服务器）——真实 WS 连接地址待 CDP Network 域 `webSocketCreated` 事件补全

## 2026-09-07 20:20 — WebSocket 信令捕获（✅ 完成，未决点关闭）

**环境**: 课堂直播中（20:20–20:30 之间），CDP 9222 连通。

**成果**
- `ws_capture.ps1 -Mode Now`（Runtime.queryObjects 反查 WebSocket 实例）→ 抓到课堂页活跃连接: **`wss://im-tx-sh8.roombox.xdf.cn/ws`**（OPEN, 腾讯云上海节点）
- `ws_capture.ps1 -Mode Watch -Seconds 30`（Network.enable 订阅事件流）→ 30 秒内 4 帧（SEND×2 / RECV×2, opcode=2 二进制, 30–183B），protobuf 风格: 帧前缀 `ce 01` + 长度/序号字段 + protobuf wire 字段（`72`=field14, `28`=field5 varint 等），呈心跳/状态同步节奏
- 工具留档: `ws_capture.ps1`（cdp Network 域监听 + queryObjects 双模式）

**结论**
- IM 信令协议为私有二进制 protobuf 封装, 反序列化需协议定义(可用 protoc 逆向或对比多种帧); 心跳约 30s 周期

## 2026-09-07 20:32 — 课后评价窗口抓取（✅ 完成）

**环境**: 20:30 下课后「课后评价」窗口自动弹出（新 CEF 窗口, `d.roombox.xdf.cn/comment/`）。

**成果**
- 监听器 watch_evaluation.ps1 自动发现并快照（窗口 URL/正文/XHR/脚本清单）→ `evaluation_capture.json`
- 全量页面源码落盘 → `comment_page.html`（含内联提交逻辑）
- **挖到提交接口: `POST /api/comment/add?token=`**（JSON: classroomId / userinfo / commentAspects{1,2,3: 3=优..1=差} / commentText）
- 窗口关闭机制: 提交成功后经原生桥 `Sac_jsCallC('commentbtnclick','ok')` 关闭; 取消走 `cancel`
- ⚠️ 窗口 URL 的 commit 参数含**本机 MAC 地址**, 该 URL 勿外发

**未做**: 未自动提交（评价内容涉及用户主观选择, 待用户确认后再说）

## 2026-09-08 — xdf-api 服务落地（✅ 编译+端到端测试通过）

- **技术栈**: Go 单二进制（net/http + robfig/cron + modernc/sqlite 纯 Go 无 cgo）+ FullCalendar v6 内嵌前端, Docker 多阶段构建（alpine, ~20MB 镜像）
- **功能**: 课表日历(月/周)、回放列表(生成状态/签名过期检测)、在线观看(302)/下载(流式代理+Range+Content-Disposition)、上课提醒(钉钉/企微/飞书/通用 webhook, 每课一次)、token 手动填写(设置页, 到期检测)
- **本机端到端验证**: 本地编译 OK(16MB exe) → 起服务 → Basic Auth 401/200 → 保存 token 触发同步 → **同步 86 节课/51 回放** → 日历 events 正常 → 回放代理 Range 请求返回 **206 + 1024B + video/mp4**, HEAD 200 + `Content-Disposition: attachment; filename="20260907_1930_623589057.mp4"` → 回放列表无未来课
- **部署**: 服务器 `cd server && docker compose up -d --build`（ADMIN_PASS 必填）

## 2026-09-07 20:39 — 课后评价自动提交（✅ 成功）

- 脚本: `submit_evaluation.ps1`（三组全部点击 `data-option="1"`（最左/最高档），不动 textarea，点击 `.submit-btn`）
- 结果: `CLICKED groups=3 -> SUBMIT`，4 秒后窗口被原生层关闭——成功路径特征（code=200 → toast → 1s → `Sac_jsCallC('commentbtnclick','ok')` → 关闭窗口）✔
- 以后自动处理: `pwsh -File submit_evaluation.ps1 -WaitMinutes 30`（课后窗口弹出时自动提交）
