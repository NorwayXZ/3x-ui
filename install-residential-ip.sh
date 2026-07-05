#!/usr/bin/env bash
set -euo pipefail

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
plain='\033[0m'

REPO_OWNER="${REPO_OWNER:-NorwayXZ}"
REPO_NAME="${REPO_NAME:-3x-ui}"
REPO_BRANCH="${1:-${REPO_BRANCH:-release/residential-ip-v1}}"
PREBUILT_TAG="${PREBUILT_TAG:-residential-ip-prebuilt-v1}"
PREBUILT_ASSET_AMD64="${PREBUILT_ASSET_AMD64:-3x-ui-residential-linux-amd64.tar.gz}"
FORCE_SOURCE_BUILD="${FORCE_SOURCE_BUILD:-false}"

GO_VERSION="${GO_VERSION:-1.26.4}"
INSTALL_ROOT="${INSTALL_ROOT:-/usr/local/x-ui}"
SRC_ROOT="${SRC_ROOT:-/usr/local/src/3x-ui-residential}"
SERVICE_NAME="${SERVICE_NAME:-x-ui}"
ENV_FILE="${ENV_FILE:-/etc/default/x-ui}"
PREBUILT_ROOT="${PREBUILT_ROOT:-/tmp/3x-ui-residential-prebuilt}"
INSTALL_RESULT_FILE="${INSTALL_RESULT_FILE:-/etc/x-ui/install-result.env}"

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
TMP_NPM_CACHE="${TMP_NPM_CACHE:-/tmp/xui-npm-cache}"
TMP_GOMODCACHE="${TMP_GOMODCACHE:-/tmp/xui-go-modcache}"
TMP_GOCACHE="${TMP_GOCACHE:-/tmp/xui-go-buildcache}"
PANEL_CREDS_KNOWN="0"
MIN_APT_FREE_MB="${MIN_APT_FREE_MB:-512}"
MIN_PREBUILT_FREE_MB="${MIN_PREBUILT_FREE_MB:-512}"
MIN_INSTALL_FREE_MB="${MIN_INSTALL_FREE_MB:-256}"
MIN_AIMILI_FREE_MB="${MIN_AIMILI_FREE_MB:-512}"
MIN_SOURCE_BUILD_FREE_MB="${MIN_SOURCE_BUILD_FREE_MB:-4096}"

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
  python3 - <<PY
import secrets
import string
chars = string.ascii_letters + string.digits
print(''.join(secrets.choice(chars) for _ in range(${len})))
PY
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
die() { echo -e "${red}Error:${plain} $*" >&2; exit 1; }

disk_cleanup_hint() {
  cat >&2 <<'EOF'
Free some disk space and rerun the installer. Useful commands:
  df -h
  du -xhd1 / /var /usr /tmp 2>/dev/null | sort -h
  apt-get clean
  journalctl --vacuum-size=100M
EOF
}

require_free_space() {
  local dir="$1" min_mb="$2" purpose="$3"
  local available_mb mount_point

  mkdir -p "$dir"
  available_mb="$(df -Pm "$dir" 2>/dev/null | awk 'NR==2 {print $4}')"
  mount_point="$(df -Pm "$dir" 2>/dev/null | awk 'NR==2 {print $6}')"

  [[ "$available_mb" =~ ^[0-9]+$ ]] || die "Unable to determine free disk space for ${dir}."

  if (( available_mb < min_mb )); then
    echo -e "${red}Error:${plain} Not enough free disk space to ${purpose}." >&2
    echo -e "Need at least ${yellow}${min_mb} MiB${plain} free on ${mount_point:-$dir}, but only ${yellow}${available_mb} MiB${plain} is available." >&2
    disk_cleanup_hint
    exit 1
  fi
}

cleanup_build_swap() {
  if [[ "${CREATED_BUILD_SWAP}" != "1" ]]; then
    return
  fi
  swapoff "${BUILD_SWAPFILE}" >/dev/null 2>&1 || true
  rm -f "${BUILD_SWAPFILE}" >/dev/null 2>&1 || true
}

cleanup_build_caches() {
  rm -rf "${TMP_NPM_CACHE}" "${TMP_GOMODCACHE}" "${TMP_GOCACHE}" >/dev/null 2>&1 || true
}

cleanup_prebuilt_root() {
  rm -rf "${PREBUILT_ROOT}" >/dev/null 2>&1 || true
}

cleanup_all() {
  cleanup_build_swap
  cleanup_build_caches
  cleanup_prebuilt_root
}

trap cleanup_all EXIT

apt_install() {
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

install_base_deps() {
  require_free_space "/var/cache/apt" "${MIN_APT_FREE_MB}" "install system dependencies"
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

download_prebuilt_panel() {
  if [[ "${FORCE_SOURCE_BUILD}" == "true" ]]; then
    warn "FORCE_SOURCE_BUILD=true set, skipping prebuilt package"
    return 1
  fi

  local asset=""
  case "${ARCH}" in
    amd64) asset="${PREBUILT_ASSET_AMD64}" ;;
    *)
      warn "No prebuilt package configured for architecture ${ARCH}; falling back to source build"
      return 1
      ;;
  esac

  local url="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/${PREBUILT_TAG}/${asset}"
  info "Downloading prebuilt package ${asset}"
  require_free_space "/tmp" "${MIN_PREBUILT_FREE_MB}" "download and extract the prebuilt panel package"
  cleanup_prebuilt_root
  mkdir -p "${PREBUILT_ROOT}"
  if ! curl -fL --connect-timeout 20 --retry 3 --retry-delay 3 "${url}" -o "${PREBUILT_ROOT}/${asset}"; then
    warn "Failed to download prebuilt package; falling back to source build"
    cleanup_prebuilt_root
    return 1
  fi
  # This function runs inside `if download_prebuilt_panel; then ...`, so rely on
  # an explicit check instead of `set -e` for tar extraction failures.
  if ! tar -xzf "${PREBUILT_ROOT}/${asset}" -C "${PREBUILT_ROOT}"; then
    warn "Failed to extract prebuilt package. The VPS may be out of disk space, or the archive may be corrupt."
    disk_cleanup_hint
    cleanup_prebuilt_root
    return 1
  fi
  [[ -f "${PREBUILT_ROOT}/x-ui" && -f "${PREBUILT_ROOT}/bin/xray-linux-${ARCH}" && -f "${PREBUILT_ROOT}/bin/geosite.dat" && -f "${PREBUILT_ROOT}/bin/geoip.dat" ]] || {
    warn "Prebuilt package is incomplete; falling back to source build"
    cleanup_prebuilt_root
    return 1
  }
  return 0
}

build_panel() {
  require_free_space "/tmp" "${MIN_SOURCE_BUILD_FREE_MB}" "build x-ui from source"
  require_free_space "$(dirname "$SRC_ROOT")" "${MIN_SOURCE_BUILD_FREE_MB}" "build x-ui from source"
  ensure_build_swap
  cleanup_build_caches
  mkdir -p "${TMP_NPM_CACHE}" "${TMP_GOMODCACHE}" "${TMP_GOCACHE}"

  info "Building frontend"
  pushd "$SRC_ROOT/frontend" >/dev/null
  npm_config_cache="${TMP_NPM_CACHE}" npm ci --no-fund --no-audit >/dev/null
  CI=1 npm_config_jobs=1 npm_config_cache="${TMP_NPM_CACHE}" NODE_OPTIONS="--max-old-space-size=${NODE_BUILD_HEAP_MB}" npm run build >/dev/null
  rm -rf node_modules
  npm_config_cache="${TMP_NPM_CACHE}" npm cache clean --force >/dev/null 2>&1 || true
  popd >/dev/null

  # Frontend build is the memory-hungry step on tiny VPSes. Once it finishes,
  # drop the temporary swap immediately so the following Go module download and
  # compile stages recover that disk space.
  cleanup_build_swap
  CREATED_BUILD_SWAP="0"

  info "Building x-ui binary"
  pushd "$SRC_ROOT" >/dev/null
  GOMODCACHE="${TMP_GOMODCACHE}" GOCACHE="${TMP_GOCACHE}" /usr/local/go/bin/go build -ldflags "-w -s" -o build/x-ui main.go
  sh ./DockerInit.sh "$ARCH" >/dev/null
  popd >/dev/null

  cleanup_build_caches
}

install_panel_files() {
  local source_root="$1"
  require_free_space "$INSTALL_ROOT" "${MIN_INSTALL_FREE_MB}" "install the panel runtime"
  info "Installing panel runtime into ${INSTALL_ROOT}"
  mkdir -p "$INSTALL_ROOT/bin" /etc/x-ui /var/log/x-ui
  install -m 755 "${source_root}/x-ui" "$INSTALL_ROOT/x-ui"
  cp -f "${source_root}"/bin/* "$INSTALL_ROOT/bin/"
  chmod +x "$INSTALL_ROOT/bin/"* 2>/dev/null || true

  cat > /usr/bin/x-ui <<EOF
#!/usr/bin/env bash
exec ${INSTALL_ROOT}/x-ui "\$@"
EOF
  chmod +x /usr/bin/x-ui
}

install_cli_script() {
  local cli_url="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}/x-ui.sh"
  local temp_script="/tmp/x-ui-cli.$$"
  info "Installing x-ui management CLI"
  if ! curl -fsSL "${cli_url}" -o "${temp_script}"; then
    echo -e "${red}Failed to download x-ui CLI script from ${cli_url}${plain}"
    rm -f "${temp_script}"
    exit 1
  fi
  install -m 755 "${temp_script}" /usr/bin/x-ui
  rm -f "${temp_script}"
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
  upsert_env_line "$ENV_FILE" "XUI_GITHUB_REPO" "$REPO_OWNER/$REPO_NAME"
  upsert_env_line "$ENV_FILE" "XUI_GITHUB_REF" "$REPO_BRANCH"
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
        PANEL_CREDS_KNOWN="1"
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
  local aimili_installer=""
  if [[ "$AIMILI_INSTALL" != "true" ]]; then
    warn "Skipping Aimili installation because AIMILI_INSTALL=${AIMILI_INSTALL}"
    return
  fi

  require_free_space "/opt" "${MIN_AIMILI_FREE_MB}" "install aimili-vpngate"
  info "Installing or updating aimili-vpngate"
  aimili_installer="$(mktemp /tmp/aimili-install.XXXXXX.sh)"
  if ! curl -fsSL "https://raw.githubusercontent.com/${AIMILI_REPO_OWNER}/${AIMILI_REPO_NAME}/main/install.sh" -o "${aimili_installer}"; then
    rm -f "${aimili_installer}"
    warn "Failed to download the Aimili installer."
    return 1
  fi
  if ! bash "${aimili_installer}"; then
    rm -f "${aimili_installer}"
    warn "Aimili installer failed. If the log shows 'No space left on device', free disk space and rerun this installer."
    disk_cleanup_hint
    return 1
  fi
  rm -f "${aimili_installer}"

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

write_install_result() {
  local host aimili_user aimili_pass aimili_port aimili_secret panel_user panel_pass current_info current_port current_base
  host="$(curl -4fsSL https://api.ipify.org || hostname -I | awk '{print $1}')"
  aimili_user="-"
  aimili_pass="-"
  aimili_port="8787"
  aimili_secret="-"
  panel_user="${PANEL_USERNAME}"
  panel_pass="${PANEL_PASSWORD}"

  if [[ "${PANEL_CREDS_KNOWN}" != "1" && -f "${INSTALL_RESULT_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${INSTALL_RESULT_FILE}" || true
    panel_user="${PANEL_USERNAME:-${panel_user}}"
    panel_pass="${PANEL_PASSWORD:-${panel_pass}}"
  fi

  current_info="$("${INSTALL_ROOT}/x-ui" setting -show true 2>/dev/null || true)"
  current_port="$(echo "$current_info" | grep -Eo 'port: .+' | awk '{print $2}')"
  current_base="$(echo "$current_info" | grep -Eo 'webBasePath: .+' | awk '{print $2}')"
  [[ -n "${current_port}" ]] && PANEL_PORT="${current_port}"
  [[ -n "${current_base}" ]] && PANEL_BASE_PATH="${current_base#/}" && PANEL_BASE_PATH="${PANEL_BASE_PATH%/}"

  if [[ -f "$AIMILI_AUTH_FILE" ]]; then
    aimili_user="$(python3 -c "import json; print(json.load(open(${AIMILI_AUTH_FILE@Q})).get('username','-'))" 2>/dev/null || echo '-')"
    aimili_pass="$(python3 -c "import json; print(json.load(open(${AIMILI_AUTH_FILE@Q})).get('password','-'))" 2>/dev/null || echo '-')"
    aimili_port="$(python3 -c "import json; print(json.load(open(${AIMILI_AUTH_FILE@Q})).get('port',8787))" 2>/dev/null || echo '8787')"
    aimili_secret="$(python3 -c "import json; print(json.load(open(${AIMILI_AUTH_FILE@Q})).get('secret_path','-'))" 2>/dev/null || echo '-')"
  fi

  install -d -m 700 /etc/x-ui
  local prev_umask
  prev_umask="$(umask)"
  umask 077
  {
    printf 'PANEL_URL=%q\n' "http://${host}:${PANEL_PORT}/${PANEL_BASE_PATH}"
    printf 'PANEL_USERNAME=%q\n' "$panel_user"
    printf 'PANEL_PASSWORD=%q\n' "$panel_pass"
    printf 'PANEL_PORT=%q\n' "$PANEL_PORT"
    printf 'PANEL_BASE_PATH=%q\n' "$PANEL_BASE_PATH"
    printf 'AIMILI_ENTRY=%q\n' "http://${host}:${PANEL_PORT}/panel/aimili"
    printf 'AIMILI_CONSOLE=%q\n' "http://${host}:${PANEL_PORT}/panel/aimili-console/"
    printf 'AIMILI_USERNAME=%q\n' "$aimili_user"
    printf 'AIMILI_PASSWORD=%q\n' "$aimili_pass"
    printf 'AIMILI_PORT=%q\n' "$aimili_port"
    printf 'AIMILI_SECRET_PATH=%q\n' "$aimili_secret"
  } > "${INSTALL_RESULT_FILE}"
  umask "${prev_umask}"
  chmod 600 "${INSTALL_RESULT_FILE}" 2>/dev/null || true
}

print_summary() {
  local host
  host="$(curl -4fsSL https://api.ipify.org || hostname -I | awk '{print $1}')"

  echo
  echo -e "${green}==========================================================${plain}"
  echo -e "${green}Residential IP panel deployment completed.${plain}"
  echo -e "${green}==========================================================${plain}"
  echo -e "Panel URL:      ${blue}http://${host}:${PANEL_PORT}/${PANEL_BASE_PATH}${plain}"
  echo -e "Panel user:     ${yellow}${PANEL_USERNAME}${plain}"
  echo -e "Panel password: ${yellow}${PANEL_PASSWORD}${plain}"
  echo -e "Residential IP: ${blue}Open the 3x-ui panel and enter the 'Residential IP' page${plain}"
  echo -e "Tips:           ${yellow}run 'x-ui info' on the VPS to see advanced panel / Aimili details${plain}"
  echo -e "${green}==========================================================${plain}"
}

install_base_deps
if download_prebuilt_panel; then
  install_panel_files "${PREBUILT_ROOT}"
else
  install_node_22
  install_go
  sync_repo
  build_panel
  install_panel_files "${SRC_ROOT}/build"
fi
install_cli_script
configure_env
install_service
ensure_panel_credentials
install_aimili
systemctl restart "${SERVICE_NAME}"
sleep 3
systemctl is-active "${SERVICE_NAME}" >/dev/null
write_install_result
print_summary
