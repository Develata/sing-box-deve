#!/usr/bin/env bash
# shellcheck disable=SC2034

SBD_STATE_DIR="/var/lib/sing-box-deve"
SBD_CONFIG_DIR="/etc/sing-box-deve"
SBD_RUNTIME_DIR="/run/sing-box-deve"
SBD_RULES_FILE="${SBD_STATE_DIR}/firewall-rules.db"
SBD_CONTEXT_FILE="${SBD_STATE_DIR}/context.env"
SBD_FW_SNAPSHOT_FILE="${SBD_STATE_DIR}/firewall-rules.snapshot"
SBD_CFG_LOCK_FILE="${SBD_STATE_DIR}/cfg.lock"
CONFIG_SNAPSHOT_FILE="${SBD_CONFIG_DIR}/config.yaml"
SBD_SETTINGS_FILE="${SBD_CONFIG_DIR}/settings.conf"
SBD_INSTALL_DIR="/opt/sing-box-deve"
SBD_BIN_DIR="${SBD_INSTALL_DIR}/bin"
SBD_DATA_DIR="${SBD_INSTALL_DIR}/data"
SBD_NODES_FILE="${SBD_DATA_DIR}/nodes.txt"
SBD_NODES_BASE_FILE="${SBD_DATA_DIR}/nodes-base.txt"
SBD_SUB_FILE="${SBD_DATA_DIR}/nodes-sub.txt"
SBD_SERVICE_FILE="/etc/systemd/system/sing-box-deve.service"
SBD_ARGO_SERVICE_FILE="/etc/systemd/system/sing-box-deve-argo.service"

log_info() { printf '[INFO] %s\n' "$*"; }
log_warn() { printf '[WARN] %s\n' "$*"; }
log_error() { printf '[ERROR] %s\n' "$*" >&2; }
log_success() { printf '[OK] %s\n' "$*"; }

LANG_CODE="en"
AUTO_YES="false"
UPDATE_CHANNEL="stable"
SETTINGS_INITIALIZED="false"

msg() {
  local zh="$1"
  local en="$2"
  if [[ "${LANG_CODE:-en}" == "zh" ]]; then
    printf '%s' "$zh"
  else
    printf '%s' "$en"
  fi
}

prompt_yes_no() {
  local prompt="$1"
  local default_answer="${2:-Y}"
  local answer

  if [[ "${AUTO_YES:-false}" == "true" ]]; then
    log_info "Auto-accepted: ${prompt}"
    return 0
  fi

  if [[ "$default_answer" == "Y" ]]; then
    read -r -p "${prompt} [Y/n]: " answer
    answer="${answer:-Y}"
    [[ "$answer" =~ ^[Yy]$ ]]
    return $?
  fi

  read -r -p "${prompt} [y/N]: " answer
  answer="${answer:-N}"
  [[ "$answer" =~ ^[Yy]$ ]]
}

prompt_with_default() {
  local prompt="$1"
  local default_value="$2"
  local out_var="$3"
  local answer
  read -r -p "${prompt} (default: ${default_value}): " answer
  answer="${answer:-$default_value}"
  printf -v "$out_var" '%s' "$answer"
}

die() {
  log_error "$*"
  exit 1
}

ensure_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Please run as root"
  fi
}

detect_os() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_VERSION_ID="${VERSION_ID:-unknown}"
    case "$OS_ID" in
      ubuntu|debian)
        log_info "Detected supported OS: ${OS_ID} ${OS_VERSION_ID}"
        ;;
      *)
        log_warn "Detected non-primary OS: ${OS_ID} ${OS_VERSION_ID}"
        ;;
    esac
  else
    die "Unable to detect OS from /etc/os-release"
  fi
}

init_runtime_layout() {
  mkdir -p "$SBD_STATE_DIR" "$SBD_CONFIG_DIR" "$SBD_RUNTIME_DIR" "$SBD_BIN_DIR" "$SBD_DATA_DIR"
  touch "$SBD_RULES_FILE"
}

get_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) die "Unsupported architecture: $(uname -m)" ;;
  esac
}

install_apt_dependencies() {
  if [[ "$OS_ID" != "ubuntu" && "$OS_ID" != "debian" ]]; then
    log_warn "Skipping apt dependency install on ${OS_ID}"
    return 0
  fi

  export DEBIAN_FRONTEND=noninteractive
  local apt_opts=(
    "-o" "Acquire::Retries=2"
    "-o" "Acquire::http::Timeout=15"
    "-o" "Acquire::https::Timeout=15"
  )
  if command -v timeout >/dev/null 2>&1; then
    timeout 90s apt-get "${apt_opts[@]}" update -y >/dev/null || die "apt-get update timed out/failed"
    timeout 120s apt-get "${apt_opts[@]}" install -y curl jq tar openssl uuid-runtime iproute2 ca-certificates unzip wireguard-tools qrencode >/dev/null || die "apt-get install timed out/failed"
  else
    apt-get "${apt_opts[@]}" update -y >/dev/null || die "apt-get update failed"
    apt-get "${apt_opts[@]}" install -y curl jq tar openssl uuid-runtime iproute2 ca-certificates unzip wireguard-tools qrencode >/dev/null || die "apt-get install failed"
  fi
}

download_file() {
  local url="$1"
  local out="$2"
  curl -fsSL "$url" -o "$out"
}

systemd_reload_and_enable() {
  systemctl daemon-reload
  systemctl enable sing-box-deve.service >/dev/null
}

safe_service_restart() {
  systemctl restart sing-box-deve.service
}

rand_hex_8() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 4
  else
    printf '%s-%s-%s\n' "$(date +%s%N 2>/dev/null || date +%s)" "$$" "${RANDOM:-0}" | sha256sum | cut -c1-8
  fi
}
