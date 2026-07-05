# AimiliVPN Integration

This integration keeps `3x-ui` and `aimili-vpngate` isolated:

- `3x-ui` stays the main panel for Xray, users, traffic, subscriptions, and API.
- `aimili-vpngate` stays an external Python service that owns its own OpenVPN/TUN logic, proxy port, logs, and web UI.
- `3x-ui` only adds a small control plane:
  - status
  - start / stop / restart
  - log tail
  - same-origin reverse proxy to the original Aimili web UI

## One-click install

For a fresh Debian/Ubuntu VPS, use the installer from this branch:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/NorwayXZ/3x-ui/feature/embed-aimili-vpngate-restart/install-residential-ip.sh)
```

Optional: install from another branch by passing it as the first argument:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/NorwayXZ/3x-ui/feature/embed-aimili-vpngate-restart/install-residential-ip.sh) main
```

Optional environment overrides:

```bash
PANEL_PORT=2053 \
PANEL_USERNAME=adminxui \
PANEL_PASSWORD='TempXui123' \
PANEL_BASE_PATH='my-panel-path' \
bash <(curl -fsSL https://raw.githubusercontent.com/NorwayXZ/3x-ui/feature/embed-aimili-vpngate-restart/install-residential-ip.sh)
```

Before you run it, keep at least `512 MiB` free for the prebuilt install path. If you force a source build, plan for about `4 GiB` free because the frontend build cache and temporary swap file need extra room.

## Low disk space

If the installer stops with `No space left on device`, free some space and rerun it:

```bash
df -h
du -xhd1 / /var /usr /tmp 2>/dev/null | sort -h
apt-get clean
journalctl --vacuum-size=100M
```

## 3x-ui environment

Add these variables to the `x-ui` service environment file (`/etc/default/x-ui`, `/etc/conf.d/x-ui`, or `/etc/sysconfig/x-ui` depending on distro):

```env
AIMILI_ENABLED=true
AIMILI_CONTROL_MODE=systemd
AIMILI_UI_MODE=proxy
AIMILI_SERVICE_NAME=aimilivpn
AIMILI_TARGET_SCHEME=http
AIMILI_TARGET_HOST=127.0.0.1
AIMILI_AUTH_FILE=/opt/aimilivpn/vpngate_data/ui_auth.json
AIMILI_STATE_FILE=/opt/aimilivpn/vpngate_data/state.json
AIMILI_LOG_FILE=/opt/aimilivpn/vpngate_data/vpngate.log
# Optional when you prefer a direct jump instead of the reverse proxy:
# AIMILI_PUBLIC_URL=https://aimili.example.com
```

Then restart `x-ui`:

```bash
systemctl restart x-ui
```

## Recommended host deployment

Keep Aimili bound to loopback unless you explicitly want a public standalone UI:

```env
UI_HOST=127.0.0.1
UI_PORT=8787
LOCAL_PROXY_HOST=127.0.0.1
LOCAL_PROXY_PORT=7928
VPNGATE_DATA_DIR=/opt/aimilivpn/vpngate_data
```

Recommended separation:

- `3x-ui` service name: `x-ui`
- Aimili service name: `aimilivpn`
- `3x-ui` data: `/etc/x-ui`
- Aimili data: `/opt/aimilivpn/vpngate_data`
- `3x-ui` logs: `/var/log/x-ui`
- Aimili logs: `/opt/aimilivpn/vpngate_data/vpngate.log`

## Docker / sidecar deployment

Use two containers instead of baking Aimili into the `3x-ui` image:

- `3x-ui` container for the panel
- `aimili` sidecar for OpenVPN/TUN/proxy logic

Important points:

- give the Aimili container `NET_ADMIN`, `NET_RAW`, and `/dev/net/tun`
- do not publish the Aimili UI port publicly by default
- keep a shared volume for Aimili state/log files if `3x-ui` needs to read them
- set `AIMILI_TARGET_HOST` in `3x-ui` to the Docker service name, for example `aimili`
- `AIMILI_CONTROL_MODE=docker` only works when the `3x-ui` runtime can call `docker`

## Reverse proxy route

When `AIMILI_UI_MODE=proxy`, the panel exposes:

```text
<basePath>/panel/aimili-console/
```

The proxy rewrites:

- upstream secret path `/<secret>/...`
- `Location` headers
- `Set-Cookie Path`

This avoids exposing the real Aimili secret path on the public panel URL.

## Post-install CLI

After installation, run:

```bash
x-ui
```

The CLI keeps the native x-ui operations such as:

- panel start / stop / restart
- port changes
- BBR management
- firewall management

And also adds Residential IP / Aimili visibility:

- current panel URL, username, and password
- Residential IP entry and console URLs
- Aimili username and password
- Aimili start / stop / restart
- Aimili log tail

## Rollback

To remove the integration from `3x-ui` only:

1. Remove the `AIMILI_*` variables from the `x-ui` environment file.
2. Restart `x-ui`.

Aimili keeps running independently unless you stop it yourself.

To remove Aimili too:

1. Stop and disable `aimilivpn`.
2. Remove its environment file and service unit.
3. Remove `/opt/aimilivpn` after backing up `vpngate_data`.
