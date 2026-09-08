# xdf-api — 新东方云教室配套服务（Go 单体）

课表日历 + 课程回放 + 上课提醒，跑在 Linux 服务器上的 Docker 容器里。

## 功能

- **日历视图**：月/周视图展示课表（时间、课程、主讲），点击课程看详情；有录像的课程可直接"在线观看 / 下载"
- **回放**：自动检测回放生成（每 15 分钟同步）；在线播放（后端流式代理，支持拖动/Range）或点击下载；签名过期自动提示并等待刷新
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

## 定时任务

- 每 15 分钟：同步课表（含回放状态/直链刷新，窗口 ±30 天）
- 每分钟：检查上课提醒并推送

## API 一览

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/status` | token 剩余天数/上次同步/统计 |
| POST | `/api/settings` | 保存 token、webhook、提醒分钟 |
| POST | `/api/sync` | 手动触发同步 |
| GET | `/api/lessons?from=&to=` | 课表(epoch 秒) |
| GET | `/api/playbacks` | 回放列表(状态/过期) |
| GET | `/api/playback/{lesson_id}/media` | 302 跳转在线播放 |
| GET | `/api/playback/{lesson_id}/dl` | 流式代理下载 |
| POST | `/api/notify/test` | 推送测试通知 |

## 开发

```bash
go build ./...   # 本地编译（本机无 Go 时直接 docker build）
```
