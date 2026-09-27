# xdf-api — 新东方云教室配套服务（Go 单体）

课表日历 + 课程分类列表 + 回放 + 上课提醒，跑在 Linux 服务器上的 Docker 容器里。

## 功能

- **日历视图**：月/周视图展示课表（时间、课程、主讲），点击课程看详情；有录像的课程可直接"在线观看 / 下载"
- **课程（按班级分类）**：左侧班级列表（课程名、起止日期、班级编码、主讲、已开课/已结课状态），右侧该班级全部讲次（含历史班级——自动发现全量历史，含早已从"我的课程"消失的导学班/基础阶段班），每讲可选"观看 / 下载 / 学习报告"
- **回放**：自动检测回放生成（每 15 分钟同步）；在线播放（后端流式代理，支持拖动/Range）或下载；签名过期自动提示并等待刷新
- **下载双模式**：默认服务器代理（文件名规范 `20250709_0830_571145398.mp4`、支持断点续传）；勾选"CDN 直连"后 302 跳转 CDN（不占服务器流量，文件名由 CDN 决定）
- **上课提醒**：课前 N 分钟（默认 5）推送 Webhook（钉钉/企业微信/飞书/通用 JSON），每节课只推一次
- **鉴权**：界面访问用 `ADMIN_PASS`（Basic Auth）；云 API 凭证在"设置"页手动粘贴 token（JWT，约 14 天有效，到期页面会提示、同步会报错——去课表页拿新 token 更新即可）

## 快速开始（服务器上）

```bash
cd xdf-api
cp docker-compose.yml docker-compose.yml.bak   # 或直接编辑
# 编辑 docker-compose.yml, 把 ADMIN_PASS 改成你的密码
docker compose up -d --build
```

然后浏览器访问 `http://服务器IP:8080`（输入 ADMIN_PASS），到**设置**页粘贴 token 保存——课表自动同步，全程无需其他配置。

> token 获取：Windows 上云教室用 `--remote-debugging-port=9222` 启动后，`http://127.0.0.1:9222/json` 里课表页 URL 的 `token=` 参数即 JWT（也可以在设置页看当前 token 剩余天数，提前更新）。

## 同步机制

- **全量历史扫描**（每次同步）：按年分片拉取 `schedule/my`，覆盖 `SYNC_FROM`（默认 2024-01-01）至今+180 天——这是发现历史班级（不在"我的课程"里的导学班等）和刷新全部回放直链的主通道
- **班级元数据**：`my-classes` 提供权威班级名/编码；历史班级从讲次名推导（`XX课第N讲` → `XX课`）
- **现有班级讲次**：`class/lessons` 补全远期排课与学习报告链接等字段

## 部署注意事项

- **建议放内网或加反代 + HTTPS**：服务本身只有 Basic Auth，公网裸奔有风险
- 数据在 `./data/xdf-api.db`（SQLite），备份这一个文件即可
- 回放直链带 CDN 签名（约 7.7 天有效），服务每 15 分钟自动从接口拿新链接；`/api/playbacks` 里 `expired` 字段标识签名过期

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `ADMIN_PASS` | （必填） | 访问密码 |
| `PORT` | 8080 | 监听端口 |
| `DATA_DIR` | /data | SQLite 数据目录 |
| `SYNC_FROM` | 2024-01-01 | 历史扫描起点（`YYYY-MM-DD`），更早的课从此日期起拉取 |

## 定时任务

- 每 15 分钟：全量同步（历史扫描 + 班级讲次 + 回放状态/直链刷新）
- 每分钟：检查上课提醒并推送

## API 一览

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/status` | token 剩余天数/上次同步/统计 |
| POST | `/api/settings` | 保存 token、webhook、提醒分钟 |
| POST | `/api/sync` | 手动触发同步 |
| GET | `/api/lessons?from=&to=` | 课表(epoch 秒) |
| GET | `/api/playbacks` | 回放列表(状态/过期) |
| GET | `/api/classes` | 课程分类列表(按班级聚合, 含历史班级) |
| GET | `/api/classes/{class_id}/lessons` | 某班级全部讲次(含学习报告链接) |
| GET | `/api/playback/{lesson_id}/media` | 302 跳转在线播放 |
| GET | `/api/playback/{lesson_id}/dl` | 下载（默认代理；`?mode=direct` 为 CDN 直连 302） |
| POST | `/api/notify/test` | 推送测试通知 |

## 开发

```bash
go build ./...   # 本地编译（本机无 Go 时直接 docker build）
```
