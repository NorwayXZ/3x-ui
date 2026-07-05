package service

import (
	"fmt"
	"os/exec"
	"strings"

	"github.com/mhsanaei/3x-ui/v3/internal/database"
	"github.com/mhsanaei/3x-ui/v3/internal/database/model"
	"github.com/mhsanaei/3x-ui/v3/internal/logger"
)

// ensureInboundFirewallOpen best-effort opens the local inbound's listen port in
// UFW when the host firewall is active. It intentionally does not try to close
// ports on disable/delete because that requires cross-checking every remaining
// inbound/protocol pair and can surprise operators who manage rules manually.
func ensureInboundFirewallOpen(inbound *model.Inbound) {
	if inbound == nil || !inbound.Enable || inbound.NodeID != nil || inbound.Port <= 0 {
		return
	}

	active, err := ufwIsActive()
	if err != nil {
		logger.Debug("ufw status check failed:", err)
		return
	}
	if !active {
		return
	}

	bits := inboundTransports(inbound.Protocol, inbound.StreamSettings, inbound.Settings)
	if bits&transportTCP != 0 {
		ufwAllowPort("tcp", inbound.Port)
	}
	if bits&transportUDP != 0 {
		ufwAllowPort("udp", inbound.Port)
	}
}

func ufwIsActive() (bool, error) {
	out, err := exec.Command("ufw", "status").CombinedOutput()
	if err != nil {
		// ufw is optional; if it is not installed or the status command fails,
		// treat that as "firewall integration unavailable" rather than fatal.
		if _, ok := err.(*exec.Error); ok {
			return false, nil
		}
		// Some distros still print status on stderr while returning non-zero.
		// If the output says active, honor it.
		if strings.Contains(string(out), "Status: active") {
			return true, nil
		}
		return false, err
	}
	return strings.Contains(string(out), "Status: active"), nil
}

func ufwAllowPort(proto string, port int) {
	spec := fmt.Sprintf("%d/%s", port, proto)
	out, err := exec.Command("ufw", "allow", spec).CombinedOutput()
	if err != nil {
		logger.Warning("ufw allow", spec, "failed:", err, string(out))
		return
	}
	logger.Debug("ufw allow", spec, ":", strings.TrimSpace(string(out)))
}

// SyncInboundFirewallRules scans all enabled local inbounds and best-effort opens
// their TCP/UDP listen ports in UFW when the firewall is active. Returns the
// number of inbounds scanned so the CLI can report useful feedback.
func SyncInboundFirewallRules() (int, error) {
	active, err := ufwIsActive()
	if err != nil {
		return 0, err
	}
	if !active {
		return 0, nil
	}

	db := database.GetDB()
	var inbounds []*model.Inbound
	if err := db.Where("enable = ? AND node_id IS NULL", true).Find(&inbounds).Error; err != nil {
		return 0, err
	}
	for _, ib := range inbounds {
		ensureInboundFirewallOpen(ib)
	}
	return len(inbounds), nil
}
