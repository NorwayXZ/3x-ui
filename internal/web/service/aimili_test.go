package service

import (
	"net/http"
	"strings"
	"testing"
)

func TestBuildAimiliDirectURL(t *testing.T) {
	got := buildAimiliDirectURL("https://panel.example.com/aimili", "Secret123")
	want := "https://panel.example.com/aimili/Secret123/"
	if got != want {
		t.Fatalf("buildAimiliDirectURL() = %q, want %q", got, want)
	}
}

func TestStripPrefixOrRoot(t *testing.T) {
	got := stripPrefixOrRoot("/base/panel/aimili-console/api/login", "/base/panel/aimili-console")
	if got != "/api/login" {
		t.Fatalf("stripPrefixOrRoot() = %q, want %q", got, "/api/login")
	}
}

func TestJoinURLPath(t *testing.T) {
	got := joinURLPath("/Secret123/", "/api/login")
	if got != "/Secret123/api/login" {
		t.Fatalf("joinURLPath() = %q, want %q", got, "/Secret123/api/login")
	}
}

func TestRewriteAimiliSetCookieHeaders(t *testing.T) {
	resp := &http.Response{Header: make(http.Header)}
	resp.Header.Add("Set-Cookie", "session=abc; Path=/Secret123/; HttpOnly; SameSite=Lax")

	rewriteAimiliSetCookieHeaders(resp, "/panel/aimili-console/", "/Secret123/")

	got := resp.Header.Get("Set-Cookie")
	if got == "" {
		t.Fatal("expected rewritten Set-Cookie header")
	}
	if want := "Path=/panel/aimili-console/"; !strings.Contains(got, want) {
		t.Fatalf("rewritten cookie = %q, want substring %q", got, want)
	}
}

func TestBuildAimiliIPHistory(t *testing.T) {
	entries := []aimiliStructuredLog{
		{Timestamp: "2026-07-05 05:33:52", Module: "VPN", Message: "当前连接已失效或代理连通性检测失败，正在自动切换至最佳备用节点: US_104.59.34.114_443_tcp"},
		{Timestamp: "2026-07-05 05:33:52", Module: "VPN", Message: "开始连接节点: US_104.59.34.114_443_tcp"},
		{Timestamp: "2026-07-05 05:34:03", Module: "VPN", Message: "节点 US_104.59.34.114_443_tcp 连接成功，出口网卡 tun0 已启用"},
		{Timestamp: "2026-07-05 05:34:09", Module: "Proxy", Message: "代理可用，IP: 104.59.34.114, 延迟: 2041 ms"},
		{Timestamp: "2026-07-05 05:38:26", Module: "VPN", Message: "开始连接节点: TH_184.22.182.162_1631_udp"},
		{Timestamp: "2026-07-05 05:38:42", Module: "VPN", Message: "节点 TH_184.22.182.162_1631_udp 连接成功，出口网卡 tun0 已启用"},
		{Timestamp: "2026-07-05 05:39:14", Module: "Proxy", Message: "代理可用，IP: 184.22.182.162, 延迟: 1148 ms"},
	}

	history := buildAimiliIPHistory(entries, 10)
	if len(history) != 2 {
		t.Fatalf("history length = %d, want 2", len(history))
	}
	if history[0].ExitIP != "184.22.182.162" || history[0].Region != "TH" {
		t.Fatalf("latest history = %+v", history[0])
	}
	if history[1].Trigger != "自动切换" {
		t.Fatalf("older trigger = %q, want 自动切换", history[1].Trigger)
	}
}
