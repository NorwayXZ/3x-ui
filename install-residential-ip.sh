#!/usr/bin/env bash
set -euo pipefail

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
plain='\033[0m'

REPO_OWNER="${REPO_OWNER:-NorwayXZ}"
REPO_NAME="${REPO_NAME:-3x-ui}"
REPO_BRANCH="${1:-${REPO_BRANCH:-feature/embed-aimili-vpngate-restart}}"

GO_VERSION="${GO_VERSION:-1.26.4}"
INSTALL_ROOT="${INSTALL_ROOT:-/usr/local/x-ui}"
SRC_ROOT="${SRC_ROOT:-/usr/local/src/3x-ui-residential}"
SERVICE_NAME="${SERVICE_NAME:-x-ui}"
ENV_FILE="${ENV_FILE:-/etc/default/x-ui}"

PANEL_PORT="${PANEL_PORT:-2053}"
PANEL_BASE_PATH="${PANEL_BASE_PATH:-}"
PANEL_USERNAME="${PANEL_USERNAME:-}"
PANEL_PASSWORD="${PANEL_PASSWORD:-}"
FORCE_PANEL_RESET="${FORCE_PANEL_RESET:-0}"
XUI_ENABLE_FAIL2BAN="${XUI_ENABLE_FAIL2BAN:-false}"

AIMILI_INSTALL="${AIMILI_INSTALL:-true}"
AIMILI_REPO_OWNER="${AIMILI_REPO_OWNER:-baoweise-bot}"
AIMILI_REPO_NAME="${AIMILI_REPO_NAME:-aimili-vpngate}"
AIMILI_CONTROL_MODE="${AIMILI_CONTROL_MODE:-systemd}"
AIMILI_UI_MODE="${AIMILI_UI_MODE:-proxy}"
AIMILI_TARGET_SCHEME="${AIMILI_TARGET_SCHEME:-http}"
AIMILI_TARGET_HOST="${AIMILI_TARGET_HOST:-127.0.0.1}"
AIMILI_AUTH_FILE="${AIMILI_AUTH_FILE:-/opt/aimilivpn/vpngate_data/ui_auth.json}"
AIMILI_STATE_FILE="${AIMILI_STATE_FILE:-/opt/aimilivpn/vpngate_data/state.json}"
AIMILI_LOG_FILE="${AIMILI_LOG_FILE:-/opt/aimilivpn/vpngate_data/vpngate.log}"
AIMILI_PUBLIC_URL="${AIMILI_PUBLIC_URL:-}"
BUILD_SWAPFILE="${BUILD_SWAPFILE:-/swapfile-xui-build}"
BUILD_SWAP_SIZE_MB="${BUILD_SWAP_SIZE_MB:-2048}"
NODE_BUILD_HEAP_MB="${NODE_BUILD_HEAP_MB:-384}"
MIN_BUILD_RAM_MB="${MIN_BUILD_RAM_MB:-1500}"
CREATED_BUILD_SWAP="0"

if [[ $EUID -ne 0 ]]; then
  echo -e "${red}Please run this installer as root.${plain}"
  exit 1
fi

if [[ -f /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="${ID:-}"
else
  echo -e "${red}Unable to detect operating system.${plain}"
  exit 1
fi

case "${OS_ID}" in
  ubuntu|debian) ;;
  *)
    echo -e "${red}This installer currently supports Debian/Ubuntu only.${plain}"
    exit 1
    ;;
esac

rand_alnum() {
  local len="$1"
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$len"
}

rand_password() {
  while true; do
    local p
    p="$(rand_alnum 12)"
    [[ "$p" =~ [a-z] && "$p" =~ [A-Z] && "$p" =~ [0-9] ]] && { printf '%s\n' "$p"; return; }
  done
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l|armv7) echo "armv7" ;;
    *) echo -e "${red}Unsupported architecture: $(uname -m)${plain}" >&2; exit 1 ;;
  esac
}

ARCH="$(detect_arch)"

info() { echo -e "${blue}==>${plain} $*"; }
warn() { echo -e "${yellow}==>${plain} $*"; }

cleanup_build_swap() {
  if [[ "${CREATED_BUILD_SWAP}" != "1" ]]; then
    return
  fi
  swapoff "${BUILD_SWAPFILE}" >/dev/null 2>&1 || true
  rm -f "${BUILD_SWAPFILE}" >/dev/null 2>&1 || true
}

trap cleanup_build_swap EXIT

apt_install() {
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

install_base_deps() {
  info "Installing system dependencies"
  apt-get update -y >/dev/null
  apt_install ca-certificates curl git unzip tar build-essential jq python3 openvpn iproute2 iptables >/dev/null
}

install_node_22() {
  local current=""
  if command -v node >/dev/null 2>&1; then
    current="$(node -v 2>/dev/null | sed 's/^v//')"
  fi
  if [[ -n "$current" && "${current%%.*}" -ge 22 ]]; then
    info "Node.js $current already satisfies the build requirement"
    return
  fi
  info "Installing Node.js 22"
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null
  apt_install nodejs >/dev/null
}

install_go() {
  local current=""
  if command -v /usr/local/go/bin/go >/dev/null 2>&1; then
    current="$(/usr/local/go/bin/go version | awk '{print $3}' | sed 's/^go//')"
  fi
  if [[ "$current" == "$GO_VERSION" ]]; then
    info "Go $GO_VERSION already installed"
    return
  fi

  info "Installing Go $GO_VERSION"
  rm -rf /usr/local/go
  curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" -o "/tmp/go${GO_VERSION}.linux-${ARCH}.tar.gz"
  tar -C /usr/local -xzf "/tmp/go${GO_VERSION}.linux-${ARCH}.tar.gz"
}

ensure_build_swap() {
  local mem_mb swap_mb
  mem_mb="$(awk '/MemTotal:/ {print int($2/1024)}' /proc/meminfo)"
  swap_mb="$(awk '/SwapTotal:/ {print int($2/1024)}' /proc/meminfo)"

  if (( mem_mb >= MIN_BUILD_RAM_MB )) || (( swap_mb >= 512 )); then
    info "Memory looks sufficient for frontend build (${mem_mb} MiB RAM, ${swap_mb} MiB swap)"
    return
  fi

  if [[ -f "${BUILD_SWAPFILE}" ]]; then
    warn "Using existing swap file ${BUILD_SWAPFILE}"
    swapon "${BUILD_SWAPFILE}" >/dev/null 2>&1 || true
    return
  fi

  warn "Low-memory VPS detected (${mem_mb} MiB RAM, ${swap_mb} MiB swap). Creating temporary ${BUILD_SWAP_SIZE_MB} MiB swap for frontend build."
  if command -v fallocate >/dev/null 2>&1; then
    fallocate -l "${BUILD_SWAP_SIZE_MB}M" "${BUILD_SWAPFILE}"
  else
    dd if=/dev/zero of="${BUILD_SWAPFILE}" bs=1M count="${BUILD_SWAP_SIZE_MB}" status=none
  fi
  chmod 600 "${BUILD_SWAPFILE}"
  mkswap "${BUILD_SWAPFILE}" >/dev/null
  swapon "${BUILD_SWAPFILE}"
  CREATED_BUILD_SWAP="1"
}

sync_repo() {
  info "Syncing repository ${REPO_OWNER}/${REPO_NAME} (${REPO_BRANCH})"
  mkdir -p "$(dirname "$SRC_ROOT")"
  if [[ -d "$SRC_ROOT/.git" ]]; then
    git -C "$SRC_ROOT" fetch --all --prune
    git -C "$SRC_ROOT" checkout "$REPO_BRANCH"
    git -C "$SRC_ROOT" reset --hard "origin/$REPO_BRANCH"
  else
    rm -rf "$SRC_ROOT"
    git clone --depth 1 --branch "$REPO_BRANCH" "https://github.com/${REPO_OWNER}/${REPO_NAME}.git" "$SRC_ROOT"
  fi
}

build_panel() {
  ensure_build_swap

  info "Building frontend"
  pushd "$SRC_ROOT/frontend" >/dev/null
  npm ci --no-fund --no-audit >/dev/null
  CI=1 npm_config_jobs=1 NODE_OPTIONS="--max-old-space-size=${NODE_BUILD_HEAP_MB}" npm run build >/dev/null
  popd >/dev/null

  info "Building x-ui binary"
  pushd "$SRC_ROOT" >/dev/null
  /usr/local/go/bin/go build -ldflags "-w -s" -o build/x-ui main.go
  sh ./DockerInit.sh "$ARCH" >/dev/null
  popd >/dev/null
}

install_panel_files() {
  info "Installing panel runtime into ${INSTALL_ROOT}"
  mkdir -p "$INSTALL_ROOT/bin" /etc/x-ui /var/log/x-ui
  install -m 755 "$SRC_ROOT/build/x-ui" "$INSTALL_ROOT/x-ui"
  cp -f "$SRC_ROOT"/build/bin/* "$INSTALL_ROOT/bin/"
  chmod +x "$INSTALL_ROOT/bin/"* 2>/dev/null || true

  cat > /usr/bin/x-ui <<EOF
#!/usr/bin/env bash
exec ${INSTALL_ROOT}/x-ui "\$@"
EOF
  chmod +x /usr/bin/x-ui
}

upsert_env_line() {
  local file="$1" key="$2" value="$3"
  touch "$file"
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}

configure_env() {
  info "Writing ${ENV_FILE}"
  mkdir -p "$(dirname "$ENV_FILE")"
  touch "$ENV_FILE"
  upsert_env_line "$ENV_FILE" "XUI_ENABLE_FAIL2BAN" "$XUI_ENABLE_FAIL2BAN"
  upsert_env_line "$ENV_FILE" "XUI_MAIN_FOLDER" "$INSTALL_ROOT"
  upsert_env_line "$ENV_FILE" "XUI_BIN_FOLDER" "$INSTALL_ROOT/bin"
  upsert_env_line "$ENV_FILE" "AIMILI_ENABLED" "false"
}

install_service() {
  info "Installing systemd service ${SERVICE_NAME}"
  cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=x-ui Service
After=network.target
Wants=network.target

[Service]
EnvironmentFile=-${ENV_FILE}
Environment="XRAY_VMESS_AEAD_FORCED=false"
Type=simple
WorkingDirectory=${INSTALL_ROOT}
ExecStart=${INSTALL_ROOT}/x-ui
ExecReload=/bin/kill -USR1 \$MAINPID
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}" >/dev/null
}

ensure_panel_credentials() {
  local fresh_install="0"
  if [[ ! -f /etc/x-ui/x-ui.db ]]; then
    fresh_install="1"
  fi

  if [[ -z "$PANEL_BASE_PATH" ]]; then
    PANEL_BASE_PATH="$(rand_alnum 18)"
  fi
  if [[ -z "$PANEL_USERNAME" ]]; then
    PANEL_USERNAME="$(rand_alnum 10)"
  fi
  if [[ -z "$PANEL_PASSWORD" ]]; then
    PANEL_PASSWORD="$(rand_password)"
  fi

  systemctl restart "${SERVICE_NAME}"

  if [[ "$fresh_install" == "1" || "$FORCE_PANEL_RESET" == "1" ]]; then
    info "Configuring panel credentials"
    for _ in $(seq 1 15); do
      if "${INSTALL_ROOT}/x-ui" setting -username "$PANEL_USERNAME" -password "$PANEL_PASSWORD" -port "$PANEL_PORT" -webBasePath "$PANEL_BASE_PATH" >/dev/null 2>&1; then
        systemctl restart "${SERVICE_NAME}"
        return
      fi
      sleep 2
    done
    echo -e "${red}Failed to apply panel credentials.${plain}"
    exit 1
  fi

  warn "Existing /etc/x-ui/x-ui.db detected; panel credentials were preserved."
}

install_aimili() {
  if [[ "$AIMILI_INSTALL" != "true" ]]; then
    warn "Skipping Aimili installation because AIMILI_INSTALL=${AIMILI_INSTALL}"
    return
  fi

  info "Installing or updating aimili-vpngate"
  bash <(curl -fsSL "https://raw.githubusercontent.com/${AIMILI_REPO_OWNER}/${AIMILI_REPO_NAME}/main/install.sh")

  if [[ -f "$AIMILI_AUTH_FILE" ]]; then
    python3 - <<PY
import json
path = ${AIMILI_AUTH_FILE@Q}
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
data["host"] = "127.0.0.1"
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
PY
  fi

  upsert_env_line "$ENV_FILE" "AIMILI_ENABLED" "true"
  upsert_env_line "$ENV_FILE" "AIMILI_CONTROL_MODE" "$AIMILI_CONTROL_MODE"
  upsert_env_line "$ENV_FILE" "AIMILI_UI_MODE" "$AIMILI_UI_MODE"
  upsert_env_line "$ENV_FILE" "AIMILI_SERVICE_NAME" "aimilivpn"
  upsert_env_line "$ENV_FILE" "AIMILI_TARGET_SCHEME" "$AIMILI_TARGET_SCHEME"
  upsert_env_line "$ENV_FILE" "AIMILI_TARGET_HOST" "$AIMILI_TARGET_HOST"
  upsert_env_line "$ENV_FILE" "AIMILI_AUTH_FILE" "$AIMILI_AUTH_FILE"
  upsert_env_line "$ENV_FILE" "AIMILI_STATE_FILE" "$AIMILI_STATE_FILE"
  upsert_env_line "$ENV_FILE" "AIMILI_LOG_FILE" "$AIMILI_LOG_FILE"
  if [[ -n "$AIMILI_PUBLIC_URL" ]]; then
    upsert_env_line "$ENV_FILE" "AIMILI_PUBLIC_URL" "$AIMILI_PUBLIC_URL"
  fi

  systemctl restart aimilivpn >/dev/null
}

print_summary() {
  local host ip aimili_user aimili_pass aimili_port aimili_secret
  host="$(curl -4fsSL https://api.ipify.org || hostname -I | awk '{print $1}')"
  aimili_user="-"
  aimili_pass="-"
  aimili_port="8787"
  aimili_secret="-"

  if [[ -f "$AIMILI_AUTH_FILE" ]]; then
    aimili_user="$(python3 -c "import json; print(json.load(open(${AIMILI_AUTH_FILE@Q})).get('username','-'))" 2>/dev/null || echo '-')"
    aimili_pass="$(python3 -c "import json; print(json.load(open(${AIMILI_AUTH_FILE@Q})).get('password','-'))" 2>/dev/null || echo '-')"
    aimili_port="$(python3 -c "import json; print(json.load(open(${AIMILI_AUTH_FILE@Q})).get('port',8787))" 2>/dev/null || echo '8787')"
    aimili_secret="$(python3 -c "import json; print(json.load(open(${AIMILI_AUTH_FILE@Q})).get('secret_path','-'))" 2>/dev/null || echo '-')"
  fi

  echo
  echo -e "${green}==========================================================${plain}"
  echo -e "${green}Residential IP panel deployment completed.${plain}"
  echo -e "${green}==========================================================${plain}"
  echo -e "Panel URL:      ${blue}http://${host}:${PANEL_PORT}/${PANEL_BASE_PATH}${plain}"
  echo -e "Panel user:     ${yellow}${PANEL_USERNAME}${plain}"
  echo -e "Panel password: ${yellow}${PANEL_PASSWORD}${plain}"
  echo -e "Aimili entry:   ${blue}http://${host}:${PANEL_PORT}/panel/aimili${plain}"
  echo -e "Console entry:  ${blue}http://${host}:${PANEL_PORT}/panel/aimili-console/${plain}"
  echo -e "Aimili user:    ${yellow}${aimili_user}${plain}"
  echo -e "Aimili password:${yellow}${aimili_pass}${plain}"
  echo -e "Aimili loopback:${blue}http://127.0.0.1:${aimili_port}/${aimili_secret}/${plain}"
  echo -e "${green}==========================================================${plain}"
}

install_base_deps
install_node_22
install_go
sync_repo
build_panel
install_panel_files
configure_env
install_service
ensure_panel_credentials
install_aimili
systemctl restart "${SERVICE_NAME}"
sleep 3
systemctl is-active "${SERVICE_NAME}" >/dev/null
print_summary
