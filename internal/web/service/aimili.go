package service

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/mhsanaei/3x-ui/v3/internal/logger"
)

const (
	defaultAimiliServiceName  = "aimilivpn"
	defaultAimiliTargetScheme = "http"
	defaultAimiliTargetHost   = "127.0.0.1"
	defaultAimiliAuthFile     = "/opt/aimilivpn/vpngate_data/ui_auth.json"
	defaultAimiliStateFile    = "/opt/aimilivpn/vpngate_data/state.json"
	defaultAimiliLogFile      = "/opt/aimilivpn/vpngate_data/vpngate.log"
	defaultAimiliUIPort       = 8787
	defaultAimiliConsolePort  = 7928
	maxAimiliLogLines         = 500
)

type AimiliService struct{}

type AimiliConfig struct {
	Enabled         bool   `json:"enabled"`
	ControlMode     string `json:"controlMode"`
	UIMode          string `json:"uiMode"`
	ServiceName     string `json:"serviceName"`
	DockerContainer string `json:"dockerContainer"`
	TargetScheme    string `json:"targetScheme"`
	TargetHost      string `json:"targetHost"`
	AuthFile        string `json:"authFile"`
	StateFile       string `json:"stateFile"`
	LogFile         string `json:"logFile"`
	PublicURL       string `json:"publicUrl"`
}

type AimiliUIStatus struct {
	Host        string `json:"host"`
	Port        int    `json:"port"`
	ProxyPort   int    `json:"proxyPort"`
	SecretPath  string `json:"secretPath"`
	Username    string `json:"username"`
	PasswordSet bool   `json:"passwordSet"`
}

type AimiliRuntimeStatus struct {
	ActiveOpenVPNNodeID string `json:"activeOpenVPNNodeId"`
	LastCheckMessage    string `json:"lastCheckMessage"`
	IsConnecting        bool   `json:"isConnecting"`
	ActiveNodeLatency   string `json:"activeNodeLatency"`
	LocalProxy          string `json:"localProxy"`
	ProxyOK             bool   `json:"proxyOk"`
	ProxyIP             string `json:"proxyIp"`
	ProxyLatencyMS      int    `json:"proxyLatencyMs"`
	ProxyError          string `json:"proxyError"`
}

type AimiliIPHistoryEntry struct {
	Timestamp string `json:"timestamp"`
	Region    string `json:"region"`
	NodeID    string `json:"nodeId"`
	ExitIP    string `json:"exitIp"`
	LatencyMS int    `json:"latencyMs"`
	Trigger   string `json:"trigger"`
}

type AimiliStatus struct {
	Enabled             bool                   `json:"enabled"`
	ControlMode         string                 `json:"controlMode"`
	UIMode              string                 `json:"uiMode"`
	ServiceName         string                 `json:"serviceName"`
	DockerContainer     string                 `json:"dockerContainer,omitempty"`
	AuthFile            string                 `json:"authFile"`
	StateFile           string                 `json:"stateFile"`
	LogFile             string                 `json:"logFile"`
	AuthFileExists      bool                   `json:"authFileExists"`
	StateFileExists     bool                   `json:"stateFileExists"`
	LogFileExists       bool                   `json:"logFileExists"`
	ServiceState        string                 `json:"serviceState"`
	ServiceRunning      bool                   `json:"serviceRunning"`
	WebReachable        bool                   `json:"webReachable"`
	ConsoleProxyURL     string                 `json:"consoleProxyUrl"`
	ConsoleDirectURL    string                 `json:"consoleDirectUrl,omitempty"`
	PreferredConsoleURL string                 `json:"preferredConsoleUrl"`
	UI                  *AimiliUIStatus        `json:"ui,omitempty"`
	Runtime             *AimiliRuntimeStatus   `json:"runtime,omitempty"`
	History             []AimiliIPHistoryEntry `json:"history,omitempty"`
	Warnings            []string               `json:"warnings,omitempty"`
}

type AimiliActionResult struct {
	Action string        `json:"action"`
	Output string        `json:"output,omitempty"`
	Status *AimiliStatus `json:"status,omitempty"`
}

type AimiliLogResult struct {
	Lines  []string `json:"lines"`
	Source string   `json:"source"`
}

type aimiliUIAuthFile struct {
	Host       string `json:"host"`
	Port       int    `json:"port"`
	ProxyPort  int    `json:"proxy_port"`
	SecretPath string `json:"secret_path"`
	Username   string `json:"username"`
	Password   string `json:"password"`
}

type aimiliStateFile struct {
	ActiveOpenVPNNodeID string `json:"active_openvpn_node_id"`
	LastCheckMessage    string `json:"last_check_message"`
	IsConnecting        bool   `json:"is_connecting"`
	ActiveNodeLatency   string `json:"active_node_latency"`
	LocalProxy          string `json:"local_proxy"`
	ProxyOK             bool   `json:"proxy_ok"`
	ProxyIP             string `json:"proxy_ip"`
	ProxyLatencyMS      int    `json:"proxy_latency_ms"`
	ProxyError          string `json:"proxy_error"`
}

type aimiliStructuredLog struct {
	Timestamp string `json:"timestamp"`
	Level     string `json:"level"`
	Module    string `json:"module"`
	Message   string `json:"message"`
}

type pendingAimiliConnect struct {
	Timestamp string
	NodeID    string
	Trigger   string
}

var (
	aimiliVPNConnectStartPattern = regexp.MustCompile(`开始连接节点:\s*([A-Za-z0-9_.:-]+)`)
	aimiliVPNAutoSwitchPattern   = regexp.MustCompile(`自动切换至最佳备用节点:\s*([A-Za-z0-9_.:-]+)`)
	aimiliVPNSuccessPattern      = regexp.MustCompile(`节点\s+([A-Za-z0-9_.:-]+)\s+连接成功`)
	aimiliProxyReadyPattern      = regexp.MustCompile(`代理可用，IP:\s*([0-9a-fA-F:.]+),\s*延迟:\s*(\d+)\s*ms`)
)

func (s *AimiliService) LoadConfig() AimiliConfig {
	cfg := AimiliConfig{
		Enabled:         envBool("AIMILI_ENABLED", false),
		ControlMode:     strings.ToLower(strings.TrimSpace(envString("AIMILI_CONTROL_MODE", "systemd"))),
		UIMode:          strings.ToLower(strings.TrimSpace(envString("AIMILI_UI_MODE", "proxy"))),
		ServiceName:     strings.TrimSpace(envString("AIMILI_SERVICE_NAME", defaultAimiliServiceName)),
		DockerContainer: strings.TrimSpace(envString("AIMILI_DOCKER_CONTAINER", "")),
		TargetScheme:    strings.ToLower(strings.TrimSpace(envString("AIMILI_TARGET_SCHEME", defaultAimiliTargetScheme))),
		TargetHost:      strings.TrimSpace(envString("AIMILI_TARGET_HOST", defaultAimiliTargetHost)),
		AuthFile:        strings.TrimSpace(envString("AIMILI_AUTH_FILE", defaultAimiliAuthFile)),
		StateFile:       strings.TrimSpace(envString("AIMILI_STATE_FILE", defaultAimiliStateFile)),
		LogFile:         strings.TrimSpace(envString("AIMILI_LOG_FILE", defaultAimiliLogFile)),
		PublicURL:       strings.TrimSpace(envString("AIMILI_PUBLIC_URL", "")),
	}

	if cfg.ControlMode == "" {
		cfg.ControlMode = "systemd"
	}
	if cfg.UIMode == "" {
		cfg.UIMode = "proxy"
	}
	if cfg.ServiceName == "" {
		cfg.ServiceName = defaultAimiliServiceName
	}
	if cfg.TargetScheme != "http" && cfg.TargetScheme != "https" {
		cfg.TargetScheme = defaultAimiliTargetScheme
	}
	if cfg.TargetHost == "" {
		cfg.TargetHost = defaultAimiliTargetHost
	}
	if cfg.AuthFile == "" {
		cfg.AuthFile = defaultAimiliAuthFile
	}
	if cfg.StateFile == "" {
		cfg.StateFile = defaultAimiliStateFile
	}
	if cfg.LogFile == "" {
		cfg.LogFile = defaultAimiliLogFile
	}
	if cfg.ControlMode == "docker" && cfg.DockerContainer == "" {
		cfg.DockerContainer = cfg.ServiceName
	}

	return cfg
}

func (s *AimiliService) GetStatus(basePath string) (*AimiliStatus, error) {
	cfg := s.LoadConfig()

	status := &AimiliStatus{
		Enabled:         cfg.Enabled,
		ControlMode:     cfg.ControlMode,
		UIMode:          cfg.UIMode,
		ServiceName:     cfg.ServiceName,
		DockerContainer: cfg.DockerContainer,
		AuthFile:        cfg.AuthFile,
		StateFile:       cfg.StateFile,
		LogFile:         cfg.LogFile,
		ServiceState:    "unknown",
		ConsoleProxyURL: aimiliConsoleProxyURL(basePath),
	}

	if _, err := os.Stat(cfg.AuthFile); err == nil {
		status.AuthFileExists = true
	}
	if _, err := os.Stat(cfg.StateFile); err == nil {
		status.StateFileExists = true
	}
	if _, err := os.Stat(cfg.LogFile); err == nil {
		status.LogFileExists = true
	}

	auth, authErr := s.readUIAuth(cfg)
	if authErr == nil {
		status.UI = &AimiliUIStatus{
			Host:        auth.Host,
			Port:        auth.Port,
			ProxyPort:   auth.ProxyPort,
			SecretPath:  auth.SecretPath,
			Username:    auth.Username,
			PasswordSet: auth.Password != "",
		}
		status.WebReachable = s.isWebReachable(cfg, auth.Port)
		status.ConsoleDirectURL = buildAimiliDirectURL(cfg.PublicURL, auth.SecretPath)
	} else if !errors.Is(authErr, os.ErrNotExist) {
		status.Warnings = append(status.Warnings, fmt.Sprintf("failed to read Aimili auth file: %v", authErr))
	}

	if status.ConsoleDirectURL != "" && cfg.UIMode == "direct" {
		status.PreferredConsoleURL = status.ConsoleDirectURL
	} else {
		status.PreferredConsoleURL = status.ConsoleProxyURL
		if cfg.UIMode == "direct" {
			status.Warnings = append(status.Warnings, "AIMILI_UI_MODE=direct is set, but AIMILI_PUBLIC_URL is empty; falling back to the panel reverse proxy.")
		}
	}

	state, stateErr := s.readRuntimeState(cfg)
	if stateErr == nil {
		status.Runtime = state
	} else if !errors.Is(stateErr, os.ErrNotExist) {
		status.Warnings = append(status.Warnings, fmt.Sprintf("failed to read Aimili state file: %v", stateErr))
	}

	if history, historyErr := s.readIPHistory(cfg, 10); historyErr == nil {
		status.History = history
	} else if !errors.Is(historyErr, os.ErrNotExist) {
		status.Warnings = append(status.Warnings, fmt.Sprintf("failed to read Aimili IP history: %v", historyErr))
	}

	serviceState, running, err := s.queryServiceState(cfg)
	if err != nil {
		status.Warnings = append(status.Warnings, fmt.Sprintf("failed to query Aimili service state: %v", err))
	} else {
		status.ServiceState = serviceState
		status.ServiceRunning = running
	}

	if !cfg.Enabled {
		status.Warnings = append(status.Warnings, "Aimili integration is disabled. Set AIMILI_ENABLED=true in the x-ui service environment to enable panel management.")
	}
	if cfg.ControlMode == "none" {
		status.Warnings = append(status.Warnings, "Aimili control mode is read-only (AIMILI_CONTROL_MODE=none). Start/stop/restart actions are disabled.")
	}
	if authErr == nil && auth.SecretPath == "" {
		status.Warnings = append(status.Warnings, "Aimili secret path is empty; the reverse proxy cannot safely expose the management UI until ui_auth.json is repaired.")
	}

	return status, nil
}

func (s *AimiliService) RunAction(action, basePath string) (*AimiliActionResult, error) {
	action = strings.ToLower(strings.TrimSpace(action))
	switch action {
	case "start", "stop", "restart":
	default:
		return nil, fmt.Errorf("unsupported action %q", action)
	}

	cfg := s.LoadConfig()
	if cfg.ControlMode == "none" {
		return nil, errors.New("Aimili control mode is read-only")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	out, err := s.runControlCommand(ctx, cfg, action)
	result := &AimiliActionResult{
		Action: action,
		Output: strings.TrimSpace(out),
	}
	if err != nil {
		return result, err
	}

	status, statusErr := s.GetStatus(basePath)
	if statusErr == nil {
		result.Status = status
		return result, nil
	}
	logger.Warningf("Aimili action %s succeeded, but status refresh failed: %v", action, statusErr)
	return result, nil
}

func (s *AimiliService) GetLogs(lines int) (*AimiliLogResult, error) {
	cfg := s.LoadConfig()
	lines = clampAimiliLogLines(lines)

	if fileLines, err := tailFileLines(cfg.LogFile, lines); err == nil {
		return &AimiliLogResult{Lines: fileLines, Source: "file"}, nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return nil, err
	}

	switch cfg.ControlMode {
	case "systemd":
		out, err := exec.CommandContext(
			context.Background(),
			"journalctl",
			"-u",
			cfg.ServiceName,
			"--no-pager",
			"-n",
			strconv.Itoa(lines),
		).CombinedOutput()
		if err == nil {
			return &AimiliLogResult{Lines: splitLogOutput(string(out)), Source: "journalctl"}, nil
		}
	case "docker":
		if cfg.DockerContainer != "" {
			out, err := exec.CommandContext(
				context.Background(),
				"docker",
				"logs",
				"--tail",
				strconv.Itoa(lines),
				cfg.DockerContainer,
			).CombinedOutput()
			if err == nil {
				return &AimiliLogResult{Lines: splitLogOutput(string(out)), Source: "docker"}, nil
			}
		}
	}

	return nil, os.ErrNotExist
}

func (s *AimiliService) BuildReverseProxy(basePath string) (*httputil.ReverseProxy, error) {
	cfg := s.LoadConfig()
	auth, err := s.readUIAuth(cfg)
	if err != nil {
		return nil, err
	}
	if auth.SecretPath == "" {
		return nil, errors.New("Aimili secret path is empty")
	}

	targetURL := &url.URL{
		Scheme: cfg.TargetScheme,
		Host:   joinHostPort(cfg.TargetHost, auth.Port),
	}
	secretBase := "/" + strings.Trim(auth.SecretPath, "/") + "/"
	proxyBase := aimiliConsoleProxyURL(basePath)
	consoleCookie, err := s.issueConsoleSessionCookie(cfg, auth)
	if err != nil {
		return nil, err
	}

	proxy := httputil.NewSingleHostReverseProxy(targetURL)
	originalDirector := proxy.Director
	proxy.Director = func(req *http.Request) {
		originalDirector(req)
		req.Host = targetURL.Host
		req.URL.Path = joinURLPath(secretBase, stripPrefixOrRoot(req.URL.Path, strings.TrimRight(proxyBase, "/")))
		req.URL.RawPath = req.URL.EscapedPath()
		req.Header.Set("Cookie", consoleCookie)
		req.Header.Del("X-Forwarded-Proto")
		req.Header.Set("X-Forwarded-Host", req.Host)
	}
	proxy.ErrorHandler = func(rw http.ResponseWriter, req *http.Request, proxyErr error) {
		logger.Warningf("Aimili reverse proxy error: %v", proxyErr)
		http.Error(rw, "AimiliVPN console is unavailable", http.StatusBadGateway)
	}
	proxy.ModifyResponse = func(resp *http.Response) error {
		rewriteAimiliLocationHeader(resp, proxyBase, secretBase, targetURL)
		rewriteAimiliSetCookieHeaders(resp, proxyBase, secretBase)
		resp.Header.Set("Cache-Control", "no-store")
		resp.Header.Set("X-Content-Type-Options", "nosniff")
		resp.Header.Set("X-Frame-Options", "SAMEORIGIN")
		resp.Header.Set("Referrer-Policy", "same-origin")
		resp.Header.Set("Content-Security-Policy", "default-src 'self' data: blob:; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'; object-src 'none'; frame-ancestors 'self'; base-uri 'self'; form-action 'self'")
		return nil
	}
	return proxy, nil
}

func (s *AimiliService) issueConsoleSessionCookie(cfg AimiliConfig, auth *aimiliUIAuthFile) (string, error) {
	loginURL := (&url.URL{
		Scheme: cfg.TargetScheme,
		Host:   joinHostPort(cfg.TargetHost, auth.Port),
		Path:   "/" + strings.Trim(auth.SecretPath, "/") + "/api/login",
	}).String()

	payload, err := json.Marshal(map[string]string{
		"username": auth.Username,
		"password": auth.Password,
	})
	if err != nil {
		return "", err
	}

	req, err := http.NewRequestWithContext(context.Background(), http.MethodPost, loginURL, strings.NewReader(string(payload)))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 8 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		return "", fmt.Errorf("Aimili login failed with HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}

	for _, raw := range resp.Header.Values("Set-Cookie") {
		cookie, err := http.ParseSetCookie(raw)
		if err != nil {
			continue
		}
		if cookie.Name == "session" && cookie.Value != "" {
			return cookie.Name + "=" + cookie.Value, nil
		}
	}

	return "", errors.New("Aimili login did not return a session cookie")
}

func (s *AimiliService) readUIAuth(cfg AimiliConfig) (*aimiliUIAuthFile, error) {
	body, err := os.ReadFile(cfg.AuthFile)
	if err != nil {
		return nil, err
	}
	var auth aimiliUIAuthFile
	if err := json.Unmarshal(body, &auth); err != nil {
		return nil, err
	}
	if auth.Port <= 0 {
		auth.Port = defaultAimiliUIPort
	}
	if auth.ProxyPort <= 0 {
		auth.ProxyPort = defaultAimiliConsolePort
	}
	auth.SecretPath = strings.Trim(auth.SecretPath, "/")
	return &auth, nil
}

func (s *AimiliService) readRuntimeState(cfg AimiliConfig) (*AimiliRuntimeStatus, error) {
	body, err := os.ReadFile(cfg.StateFile)
	if err != nil {
		return nil, err
	}
	var raw aimiliStateFile
	if err := json.Unmarshal(body, &raw); err != nil {
		return nil, err
	}
	return &AimiliRuntimeStatus{
		ActiveOpenVPNNodeID: raw.ActiveOpenVPNNodeID,
		LastCheckMessage:    raw.LastCheckMessage,
		IsConnecting:        raw.IsConnecting,
		ActiveNodeLatency:   raw.ActiveNodeLatency,
		LocalProxy:          raw.LocalProxy,
		ProxyOK:             raw.ProxyOK,
		ProxyIP:             raw.ProxyIP,
		ProxyLatencyMS:      raw.ProxyLatencyMS,
		ProxyError:          raw.ProxyError,
	}, nil
}

func (s *AimiliService) readIPHistory(cfg AimiliConfig, limit int) ([]AimiliIPHistoryEntry, error) {
	logsDir := filepath.Join(filepath.Dir(cfg.LogFile), "logs")
	entries, err := os.ReadDir(logsDir)
	if err != nil {
		return nil, err
	}

	names := make([]string, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".json") {
			continue
		}
		names = append(names, filepath.Join(logsDir, entry.Name()))
	}
	sort.Strings(names)

	structured := make([]aimiliStructuredLog, 0, 256)
	for _, name := range names {
		f, err := os.Open(name)
		if err != nil {
			continue
		}

		scanner := bufio.NewScanner(f)
		buf := make([]byte, 0, 64*1024)
		scanner.Buffer(buf, 1024*1024)
		for scanner.Scan() {
			line := strings.TrimSpace(scanner.Text())
			if line == "" {
				continue
			}
			var row aimiliStructuredLog
			if err := json.Unmarshal([]byte(line), &row); err != nil {
				continue
			}
			structured = append(structured, row)
		}
		_ = f.Close()
	}

	history := buildAimiliIPHistory(structured, limit)
	if len(history) == 0 {
		return nil, os.ErrNotExist
	}
	return history, nil
}

func buildAimiliIPHistory(entries []aimiliStructuredLog, limit int) []AimiliIPHistoryEntry {
	lastTriggerByNode := map[string]string{}
	pending := make([]pendingAimiliConnect, 0, 8)
	history := make([]AimiliIPHistoryEntry, 0, limit)

	for _, entry := range entries {
		switch entry.Module {
		case "VPN":
			if m := aimiliVPNAutoSwitchPattern.FindStringSubmatch(entry.Message); len(m) == 2 {
				lastTriggerByNode[m[1]] = "自动切换"
				continue
			}
			if m := aimiliVPNConnectStartPattern.FindStringSubmatch(entry.Message); len(m) == 2 {
				if _, ok := lastTriggerByNode[m[1]]; !ok {
					lastTriggerByNode[m[1]] = "手动切换"
				}
				continue
			}
			if m := aimiliVPNSuccessPattern.FindStringSubmatch(entry.Message); len(m) == 2 {
				nodeID := m[1]
				trigger := lastTriggerByNode[nodeID]
				if trigger == "" {
					trigger = "连接成功"
				}
				pending = append(pending, pendingAimiliConnect{
					Timestamp: entry.Timestamp,
					NodeID:    nodeID,
					Trigger:   trigger,
				})
				delete(lastTriggerByNode, nodeID)
			}
		case "Proxy":
			if len(pending) == 0 {
				continue
			}
			m := aimiliProxyReadyPattern.FindStringSubmatch(entry.Message)
			if len(m) != 3 {
				continue
			}
			latency, _ := strconv.Atoi(m[2])
			current := pending[0]
			pending = pending[1:]
			history = append(history, AimiliIPHistoryEntry{
				Timestamp: current.Timestamp,
				Region:    aimiliRegionFromNodeID(current.NodeID),
				NodeID:    current.NodeID,
				ExitIP:    m[1],
				LatencyMS: latency,
				Trigger:   current.Trigger,
			})
		}
	}

	if len(history) == 0 {
		return nil
	}

	for left, right := 0, len(history)-1; left < right; left, right = left+1, right-1 {
		history[left], history[right] = history[right], history[left]
	}
	if limit > 0 && len(history) > limit {
		history = history[:limit]
	}
	return history
}

func aimiliRegionFromNodeID(nodeID string) string {
	parts := strings.Split(nodeID, "_")
	if len(parts) == 0 || strings.TrimSpace(parts[0]) == "" {
		return "-"
	}
	return strings.ToUpper(strings.TrimSpace(parts[0]))
}

func (s *AimiliService) queryServiceState(cfg AimiliConfig) (string, bool, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 6*time.Second)
	defer cancel()

	switch cfg.ControlMode {
	case "none":
		return "unmanaged", false, nil
	case "systemd":
		out, err := exec.CommandContext(ctx, "systemctl", "is-active", cfg.ServiceName).CombinedOutput()
		state := strings.TrimSpace(string(out))
		if state == "" {
			state = "unknown"
		}
		if err == nil {
			return state, state == "active", nil
		}
		if exitErr, ok := err.(*exec.ExitError); ok && exitErr.ExitCode() != 0 {
			return state, false, nil
		}
		return state, false, err
	case "openrc":
		out, err := exec.CommandContext(ctx, "rc-service", cfg.ServiceName, "status").CombinedOutput()
		state := strings.TrimSpace(string(out))
		lower := strings.ToLower(state)
		running := strings.Contains(lower, "started") || strings.Contains(lower, "running")
		if err == nil {
			if state == "" {
				state = "started"
			}
			return state, running, nil
		}
		if exitErr, ok := err.(*exec.ExitError); ok && exitErr.ExitCode() != 0 {
			if state == "" {
				state = "stopped"
			}
			return state, false, nil
		}
		return state, false, err
	case "docker":
		container := cfg.DockerContainer
		if container == "" {
			return "unknown", false, errors.New("AIMILI_DOCKER_CONTAINER is empty")
		}
		out, err := exec.CommandContext(ctx, "docker", "inspect", "-f", "{{if .State.Running}}running{{else}}stopped{{end}}", container).CombinedOutput()
		state := strings.TrimSpace(string(out))
		if err != nil {
			return state, false, err
		}
		if state == "" {
			state = "unknown"
		}
		return state, state == "running", nil
	default:
		return "unknown", false, fmt.Errorf("unsupported AIMILI_CONTROL_MODE %q", cfg.ControlMode)
	}
}

func (s *AimiliService) runControlCommand(ctx context.Context, cfg AimiliConfig, action string) (string, error) {
	var cmd *exec.Cmd
	switch cfg.ControlMode {
	case "systemd":
		cmd = exec.CommandContext(ctx, "systemctl", action, cfg.ServiceName)
	case "openrc":
		cmd = exec.CommandContext(ctx, "rc-service", cfg.ServiceName, action)
	case "docker":
		container := cfg.DockerContainer
		if container == "" {
			container = cfg.ServiceName
		}
		cmd = exec.CommandContext(ctx, "docker", "container", action, container)
	default:
		return "", fmt.Errorf("unsupported AIMILI_CONTROL_MODE %q", cfg.ControlMode)
	}

	out, err := cmd.CombinedOutput()
	if err != nil {
		return string(out), fmt.Errorf("%s Aimili service: %w: %s", action, err, strings.TrimSpace(string(out)))
	}
	return string(out), nil
}

func (s *AimiliService) isWebReachable(cfg AimiliConfig, port int) bool {
	ctx, cancel := context.WithTimeout(context.Background(), 1200*time.Millisecond)
	defer cancel()
	dialer := &net.Dialer{}
	conn, err := dialer.DialContext(ctx, "tcp", joinHostPort(cfg.TargetHost, port))
	if err != nil {
		return false
	}
	_ = conn.Close()
	return true
}

func aimiliConsoleProxyURL(basePath string) string {
	base := strings.TrimRight(basePath, "/")
	if base == "" {
		base = ""
	}
	return base + "/panel/aimili-console/"
}

func buildAimiliDirectURL(publicBase, secretPath string) string {
	publicBase = strings.TrimSpace(publicBase)
	secretPath = strings.Trim(secretPath, "/")
	if publicBase == "" || secretPath == "" {
		return ""
	}
	parsed, err := url.Parse(publicBase)
	if err != nil {
		return ""
	}
	parsed.Path = joinURLPath(parsed.Path, "/"+secretPath+"/")
	return parsed.String()
}

func rewriteAimiliLocationHeader(resp *http.Response, proxyBase, secretBase string, targetURL *url.URL) {
	location := strings.TrimSpace(resp.Header.Get("Location"))
	if location == "" {
		return
	}

	if strings.HasPrefix(location, secretBase) {
		resp.Header.Set("Location", joinURLPath(proxyBase, strings.TrimPrefix(location, secretBase)))
		return
	}

	parsed, err := url.Parse(location)
	if err != nil {
		return
	}
	if parsed.IsAbs() && parsed.Scheme == targetURL.Scheme && parsed.Host == targetURL.Host && strings.HasPrefix(parsed.Path, secretBase) {
		parsed.Scheme = ""
		parsed.Host = ""
		parsed.Path = joinURLPath(proxyBase, strings.TrimPrefix(parsed.Path, secretBase))
		resp.Header.Set("Location", parsed.String())
	}
}

func rewriteAimiliSetCookieHeaders(resp *http.Response, proxyBase, secretBase string) {
	values := resp.Header.Values("Set-Cookie")
	if len(values) == 0 {
		return
	}

	rewritten := make([]string, 0, len(values))
	for _, value := range values {
		cookie, err := http.ParseSetCookie(value)
		if err != nil {
			rewritten = append(rewritten, strings.ReplaceAll(value, "Path="+secretBase, "Path="+proxyBase))
			continue
		}
		if cookie.Path == secretBase || cookie.Path == strings.TrimRight(secretBase, "/") {
			cookie.Path = proxyBase
		}
		rewritten = append(rewritten, cookie.String())
	}

	resp.Header.Del("Set-Cookie")
	for _, value := range rewritten {
		resp.Header.Add("Set-Cookie", value)
	}
}

func joinURLPath(basePath, tail string) string {
	if tail == "" {
		if basePath == "" {
			return "/"
		}
		return basePath
	}
	if basePath == "" {
		if strings.HasPrefix(tail, "/") {
			return tail
		}
		return "/" + tail
	}
	return path.Clean(strings.TrimRight(basePath, "/")+"/"+strings.TrimLeft(tail, "/")) + trailingSlash(basePath, tail)
}

func stripPrefixOrRoot(value, prefix string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return "/"
	}
	if prefix != "" && strings.HasPrefix(value, prefix) {
		trimmed := strings.TrimPrefix(value, prefix)
		if trimmed == "" {
			return "/"
		}
		if !strings.HasPrefix(trimmed, "/") {
			return "/" + trimmed
		}
		return trimmed
	}
	return value
}

func trailingSlash(basePath, tail string) string {
	if tail == "" || tail == "/" || strings.HasSuffix(tail, "/") {
		return "/"
	}
	return ""
}

func tailFileLines(filePath string, lines int) ([]string, error) {
	f, err := os.Open(filePath)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	ring := make([]string, 0, lines)
	scanner := bufio.NewScanner(f)
	const maxCapacity = 1024 * 1024
	buf := make([]byte, 0, 64*1024)
	scanner.Buffer(buf, maxCapacity)

	for scanner.Scan() {
		line := scanner.Text()
		if len(ring) == lines {
			copy(ring, ring[1:])
			ring[len(ring)-1] = line
			continue
		}
		ring = append(ring, line)
	}
	if err := scanner.Err(); err != nil && !errors.Is(err, io.EOF) {
		return nil, err
	}
	return ring, nil
}

func splitLogOutput(output string) []string {
	lines := strings.Split(strings.ReplaceAll(output, "\r\n", "\n"), "\n")
	filtered := make([]string, 0, len(lines))
	for _, line := range lines {
		if strings.TrimSpace(line) == "" {
			continue
		}
		filtered = append(filtered, line)
	}
	return filtered
}

func clampAimiliLogLines(lines int) int {
	switch {
	case lines <= 0:
		return 100
	case lines > maxAimiliLogLines:
		return maxAimiliLogLines
	default:
		return lines
	}
}

func envString(name, fallback string) string {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return fallback
	}
	return value
}

func envBool(name string, fallback bool) bool {
	value := strings.TrimSpace(strings.ToLower(os.Getenv(name)))
	if value == "" {
		return fallback
	}
	switch value {
	case "1", "true", "yes", "on":
		return true
	case "0", "false", "no", "off":
		return false
	default:
		return fallback
	}
}

func joinHostPort(host string, port int) string {
	return net.JoinHostPort(host, strconv.Itoa(port))
}
