package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

// SendWebhook 按平台类型发送通知
func SendWebhook(kind, hookURL, title, content string) error {
	if hookURL == "" {
		return fmt.Errorf("未配置 webhook 地址")
	}
	var payload any
	switch kind {
	case "dingtalk": // 钉钉/企业微信机器人: text 消息
		payload = map[string]any{"msgtype": "text", "text": map[string]string{"content": content}}
	case "wecom":
		payload = map[string]any{"msgtype": "text", "text": map[string]string{"content": content}}
	case "feishu":
		payload = map[string]any{"msg_type": "text", "content": map[string]string{"text": content}}
	default: // generic: 自定义 JSON {"title","content"}
		payload = map[string]string{"title": title, "content": content}
	}
	b, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	req, err := http.NewRequest("POST", hookURL, bytes.NewReader(b))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return fmt.Errorf("webhook HTTP %d", resp.StatusCode)
	}
	return nil
}

// ---- 时间/小工具 ----
func at8(sec int64) time.Time {
	return time.Unix(sec, 0).In(cst)
}

func orDash(s string) string {
	if s == "" {
		return "-"
	}
	return s
}
