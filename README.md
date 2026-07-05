[English](/README.md) | [فارسی](/README.fa_IR.md) | [العربية](/README.ar_EG.md) | [中文](/README.zh_CN.md) | [Español](/README.es_ES.md) | [Русский](/README.ru_RU.md) | [Türkçe](/README.tr_TR.md)

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="./media/3x-ui-dark.png">
    <img alt="3x-ui" src="./media/3x-ui-light.png">
  </picture>
</p>

<p align="center">
  <a href="https://github.com/MHSanaei/3x-ui/releases"><img src="https://img.shields.io/github/v/release/mhsanaei/3x-ui" alt="Release"></a>
  <a href="https://github.com/MHSanaei/3x-ui/actions"><img src="https://img.shields.io/github/actions/workflow/status/mhsanaei/3x-ui/release.yml.svg" alt="Build"></a>
  <a href="#"><img src="https://img.shields.io/github/go-mod/go-version/mhsanaei/3x-ui.svg" alt="GO Version"></a>
  <a href="https://github.com/MHSanaei/3x-ui/releases/latest"><img src="https://img.shields.io/github/downloads/mhsanaei/3x-ui/total.svg" alt="Downloads"></a>
  <a href="https://www.gnu.org/licenses/gpl-3.0.en.html"><img src="https://img.shields.io/badge/license-GPL%20V3-blue.svg?longCache=true" alt="License"></a>
  <a href="https://pkg.go.dev/github.com/mhsanaei/3x-ui/v3"><img src="https://pkg.go.dev/badge/github.com/mhsanaei/3x-ui/v3.svg" alt="Go Reference"></a>
  <a href="https://goreportcard.com/report/github.com/mhsanaei/3x-ui/v3"><img src="https://goreportcard.com/badge/github.com/mhsanaei/3x-ui/v3" alt="Go Report Card"></a>
</p>

**3X-UI** is an advanced, open-source web control panel for managing [Xray-core](https://github.com/XTLS/Xray-core) servers. It provides a clean, multi-language interface for deploying, configuring, and monitoring a wide range of proxy and VPN protocols — from a single VPS to multi-node deployments.

Built as an enhanced fork of the original X-UI project, 3X-UI adds broader protocol support, improved stability, per-client traffic accounting, and many quality-of-life features.

> [!IMPORTANT]
> This project is intended for personal use only. Please do not use it for illegal purposes or in a production environment.

## Features

- **Multi-protocol inbounds** — VLESS, VMess, Trojan, Shadowsocks, WireGuard, Hysteria2, HTTP, SOCKS (Mixed), Dokodemo-door / Tunnel, and TUN.
- **Modern transports & security** — TCP (Raw), mKCP, WebSocket, gRPC, HTTPUpgrade, and XHTTP, secured with TLS, XTLS, and REALITY.
- **Fallbacks** — serve multiple protocols on a single port (e.g. VLESS and Trojan on 443) using Xray's fallback support.
- **Per-client management** — traffic quotas, expiry dates, IP limits, live online status, and one-click share links, QR codes, and subscriptions.
- **Traffic statistics** — per inbound, per client, and per outbound, with reset controls.
- **Multi-node support** — manage and scale across multiple servers from a single panel.
- **Outbound & routing** — WARP, NordVPN, custom routing rules, load balancers, and outbound proxy chaining.
- **Built-in subscription server** with multiple output formats and [custom page templates](docs/custom-subscription-templates.md).
- **Telegram bot** for remote monitoring and management.
- **RESTful API** with in-panel Swagger documentation.
- **Flexible storage** — SQLite (default) or PostgreSQL.
- **13 UI languages** with dark and light themes.
- **Fail2ban integration** for enforcing per-client IP limits.

## Screenshots

<details>
<summary>Click to expand</summary>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="./media/01-overview-dark.png">
  <img alt="Overview" src="./media/01-overview-light.png">
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="./media/02-add-inbound-dark.png">
  <img alt="Inbounds" src="./media/02-add-inbound-light.png">
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="./media/03-add-client-dark.png">
  <img alt="Add client" src="./media/03-add-client-light.png">
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="./media/05-add-nodes-dark.png">
  <img alt="Configs" src="./media/05-add-nodes-light.png">
</picture>

</details>

## Quick Start

```bash
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
```

### Residential IP Stable Branch

This repository also ships a stable Residential IP / Aimili integration branch:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/NorwayXZ/3x-ui/release/residential-ip-v1/install-residential-ip.sh)
```

What you get from that installer:

- normal `3x-ui` panel
- built-in `Residential IP` page inside the panel
- independent `aimili-vpngate` service managed by the panel
- same-origin `Open Console` reverse proxy
- native `x-ui` terminal command with both original panel operations and Aimili controls

See [docs/aimili-integration.md](docs/aimili-integration.md) for the full deployment guide.

To install a specific version, append its tag (e.g. `v3.4.0`):

```bash
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) v3.4.0
```

To install the rolling **dev** build (latest per-commit pre-release from `main`, not a stable release), pass `dev-latest`:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) dev-latest
```

During installation a random username, password, and access path are generated. After installation, run `x-ui` to open the management menu, where you can start/stop the service, view or reset your login credentials, manage SSL certificates, and more.

For full documentation, please visit the [project Wiki](https://github.com/MHSanaei/3x-ui/wiki).

### Unattended install

The installer also runs **non-interactively** for cloud-init.
Set `XUI_NONINTERACTIVE=1` (or pipe with no TTY) and it installs end-to-end with
zero prompts, generating random credentials and writing them to
`/etc/x-ui/install-result.env`. See [`deploy/`](deploy/) for:

- [Cloud-init user-data](deploy/cloud-init/) — unattended install on any cloud (Hetzner/AWS/DO/Vultr/GCP/Azure/Oracle)
- [Hetzner Cloud notes](deploy/marketplace/hetzner/) — cloud-init deployment on Hetzner

## Supported Platforms

**Operating systems:** Ubuntu, Debian, Armbian, Fedora, CentOS, RHEL, AlmaLinux, Rocky Linux, Oracle Linux, Amazon Linux, Virtuozzo, Arch, Manjaro, Parch, openSUSE (Tumbleweed / Leap), Alpine, and Windows.

**Architectures:** `amd64` · `386` · `arm64` (aarch64) · `armv7` · `armv6` · `armv5` · `s390x`.

### Residential IP Branch Requirements

For the `release/residential-ip-v1` installer, use these requirements:

- **Recommended:** `2 vCPU`, `2 GB RAM`, `20 GB` free disk, `TUN/TAP enabled`
- **Minimum verified:** `1 vCPU`, `1 GB RAM`, `2 GB swap`, `10 GB` free disk, `TUN/TAP enabled`
- **Best architecture:** `amd64`
- **Best OS:** `Ubuntu 24.04` or recent `Debian`

Notes:

- Low-memory VPS nodes are supported by the installer through a temporary build swap file.
- Small-disk VPS nodes are supported on `amd64` by downloading a prebuilt runtime instead of compiling locally.
- `arm64` may still require a source build path, so it is less forgiving on very small machines.

## Post-install CLI

After installation, connect to the VPS and run:

```bash
x-ui
```

Useful commands:

```bash
x-ui info
x-ui status
x-ui aimili-status
x-ui aimili
```

What they provide:

- current panel URL, port, and base path
- recorded panel username and password
- Residential IP entry and console URLs
- Aimili username and password
- Aimili service state, current exit IP, node, and latency
- native x-ui operations such as port changes, BBR, firewall, start/stop/restart

## Uninstall / Reinstall

To reinstall the Residential IP branch on a fresh Debian/Ubuntu VPS:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/NorwayXZ/3x-ui/release/residential-ip-v1/install-residential-ip.sh)
```

To uninstall manually:

```bash
x-ui uninstall
systemctl stop aimilivpn 2>/dev/null || true
systemctl disable aimilivpn 2>/dev/null || true
rm -rf /opt/aimilivpn
rm -f /etc/default/aimilivpn /usr/bin/ml /etc/sysctl.d/99-aimilivpn.conf
```

If you only want to remove the Residential IP integration and keep the panel:

- delete the `AIMILI_*` variables from `/etc/default/x-ui`
- restart `x-ui`
- stop and disable `aimilivpn`

## Database Options

3X-UI supports two backends, chosen during the install:

- **SQLite** (default) — a single file at `/etc/x-ui/x-ui.db`. Zero setup, ideal for small and medium deployments.
- **PostgreSQL** — recommended for high client counts or multi-node setups. The installer can install PostgreSQL locally for you, or accept a DSN to an existing server.

At runtime the backend is selected via environment variables (the installer writes these to `/etc/default/x-ui` for you):

```
XUI_DB_TYPE=postgres
XUI_DB_DSN=postgres://xui:password@127.0.0.1:5432/xui?sslmode=disable
```

### Migrating an existing SQLite install to PostgreSQL

```bash
x-ui migrate-db --dsn "postgres://xui:password@127.0.0.1:5432/xui?sslmode=disable"
# then set XUI_DB_TYPE and XUI_DB_DSN in /etc/default/x-ui and restart:
systemctl restart x-ui
```

The source SQLite file is left untouched; remove it manually once you have verified the new backend.

### Docker

The default `docker compose up -d` keeps using SQLite. To run with the bundled PostgreSQL service, uncomment the two `XUI_DB_*` env lines in `docker-compose.yml` and start with the profile:

```bash
docker compose --profile postgres up -d
```

The image bundles Fail2ban (enabled by default) to enforce per-client **IP limits**. Fail2ban bans offenders with `iptables`, which requires the `NET_ADMIN` capability. `docker-compose.yml` already grants it via `cap_add`; if you start the container with `docker run` instead, add the capabilities yourself, otherwise bans are logged but never applied:

```bash
docker run -d --cap-add=NET_ADMIN --cap-add=NET_RAW ... ghcr.io/mhsanaei/3x-ui
```

## Environment Variables

| Variable | Description | Default |
| --- | --- | --- |
| `XUI_DB_TYPE` | Database backend: `sqlite` or `postgres` | `sqlite` |
| `XUI_DB_DSN` | PostgreSQL connection string (when `XUI_DB_TYPE=postgres`) | — |
| `XUI_DB_FOLDER` | Directory for the SQLite database file | `/etc/x-ui` |
| `XUI_DB_MAX_OPEN_CONNS` | Maximum open connections (PostgreSQL pool) | — |
| `XUI_DB_MAX_IDLE_CONNS` | Maximum idle connections (PostgreSQL pool) | — |
| `XUI_INIT_WEB_BASE_PATH` | The initial URI path for the web panel | `/` |
| `XUI_ENABLE_FAIL2BAN` | Enable Fail2ban-based IP-limit enforcement | `true` |
| `XUI_LOG_LEVEL` | Log verbosity (`debug`, `info`, `warning`, `error`) | `info` |
| `XUI_DEBUG` | Enable debug mode | `false` |
| `XUI_TUNNEL_HEALTH_MONITOR` | Enable the tunnel health monitor (probes a URL and restarts xray after repeated failures; a restart drops all clients) | `false` |
| `XUI_TUNNEL_HEALTH_PROXY` | Proxy the probe is sent through; point it at a local xray inbound so the probe tests the tunnel (e.g. `socks5://127.0.0.1:1080`). Empty means the probe only checks host connectivity | — |
| `XUI_TUNNEL_HEALTH_URL` | URL probed for tunnel health | `https://www.cloudflare.com/cdn-cgi/trace` |
| `XUI_TUNNEL_HEALTH_INTERVAL` | Interval between probes | `30s` |
| `XUI_TUNNEL_HEALTH_TIMEOUT` | Per-probe timeout | `10s` |
| `XUI_TUNNEL_HEALTH_FAILURES` | Consecutive failures before a restart is triggered | `3` |
| `XUI_TUNNEL_HEALTH_COOLDOWN` | Minimum delay between consecutive restarts | `5m` |

## Supported Languages

The panel UI is available in 13 languages:

English · فارسی · العربية · 中文（简体） · 中文（繁體） · Español · Русский · Українська · Türkçe · Tiếng Việt · 日本語 · Bahasa Indonesia · Português (Brasil)

## Contributing

Contributions are welcome. Please read the [Contributing Guide](/CONTRIBUTING.md) before opening an issue or pull request.

## A Special Thanks to

- [alireza0](https://github.com/alireza0/)

## Acknowledgment

- [Iran v2ray rules](https://github.com/chocolate4u/Iran-v2ray-rules) (License: **GPL-3.0**): _Enhanced v2ray/xray and v2ray/xray-clients routing rules with built-in Iranian domains and a focus on security and adblocking._
- [Russia v2ray rules](https://github.com/runetfreedom/russia-v2ray-rules-dat) (License: **GPL-3.0**): _This repository contains automatically updated V2Ray routing rules based on data on blocked domains and addresses in Russia._

## Community Tools

Tools and integrations built by the community around 3x-ui.

- [terraform-provider-3x-ui](https://github.com/batonogov/terraform-provider-threexui) (License: **MIT**): _Manage inbounds, clients, panel settings, and Xray configuration as code with Terraform / OpenTofu._

## Support project

**If this project is helpful to you, you may wish to give it a**:star2:

<a href="https://www.buymeacoffee.com/MHSanaei" target="_blank">
<img src="./media/default-yellow.png" alt="Buy Me A Coffee" style="height: 70px !important;width: 277px !important;" >
</a>

</br>
<a href="https://nowpayments.io/donation/hsanaei" target="_blank" rel="noreferrer noopener">
   <img src="./media/donation-button-black.svg" alt="Crypto donation button by NOWPayments">
</a>

## Stargazers over Time

[![Stargazers over time](https://starchart.cc/MHSanaei/3x-ui.svg?variant=adaptive)](https://starchart.cc/MHSanaei/3x-ui)
