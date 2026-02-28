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
SBD_CACHE_DIR="${SBD_INSTALL_DIR}/cache"
SBD_NODES_FILE="${SBD_DATA_DIR}/nodes.txt"
SBD_NODES_BASE_FILE="${SBD_DATA_DIR}/nodes-base.txt"
SBD_SUB_FILE="${SBD_DATA_DIR}/nodes-sub.txt"
SBD_SERVICE_FILE="/etc/systemd/system/sing-box-deve.service"
SBD_ARGO_SERVICE_FILE="/etc/systemd/system/sing-box-deve-argo.service"
SBD_PSIPHON_SERVICE_FILE="/etc/systemd/system/sing-box-deve-psiphon.service"

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
    log_info "$(msg "已自动确认: ${prompt}" "Auto-accepted: ${prompt}")"
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
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    if [[ "${SBD_USER_MODE:-false}" == "true" ]]; then
      log_warn "$(msg "此操作通常需要 root 权限，在用户模式下可能受限" \
                   "This operation normally requires root; may be limited in user mode")"
      return 0
    fi
    die "Please run as root"
  fi
}

detect_os() {
  # FreeBSD detection (Serv00 / HeroTofu environments)
  if [[ "$(uname -s)" == "FreeBSD" ]]; then
    OS_ID="freebsd"
    OS_VERSION_ID="$(uname -r | cut -d- -f1)"
    log_info "$(msg "检测到 FreeBSD ${OS_VERSION_ID}" "Detected FreeBSD ${OS_VERSION_ID}")"
    return 0
  fi

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_VERSION_ID="${VERSION_ID:-unknown}"
    case "$OS_ID" in
      ubuntu|debian)
        log_info "$(msg "检测到受支持系统: ${OS_ID} ${OS_VERSION_ID}" "Detected supported OS: ${OS_ID} ${OS_VERSION_ID}")"
        ;;
      alpine)
        log_info "$(msg "检测到 Alpine Linux ${OS_VERSION_ID}" "Detected Alpine Linux ${OS_VERSION_ID}")"
        ;;
      *)
        log_warn "$(msg "检测到非主支持系统: ${OS_ID} ${OS_VERSION_ID}" "Detected non-primary OS: ${OS_ID} ${OS_VERSION_ID}")"
        ;;
    esac
  else
    OS_ID="unknown"
    OS_VERSION_ID="unknown"
    log_warn "$(msg "无法从 /etc/os-release 检测系统信息，尝试继续" "Unable to detect OS from /etc/os-release, attempting to continue")"
  fi
}

init_runtime_layout() {
  mkdir -p "$SBD_STATE_DIR" "$SBD_CONFIG_DIR" "$SBD_RUNTIME_DIR" "$SBD_BIN_DIR" "$SBD_DATA_DIR" "$SBD_CACHE_DIR"
  touch "$SBD_RULES_FILE"
  chmod 700 "$SBD_DATA_DIR" 2>/dev/null || true
  chmod 700 "$SBD_STATE_DIR" 2>/dev/null || true
}

get_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) die "$(msg "不支持的架构: $(uname -m)" "Unsupported architecture: $(uname -m)")" ;;
  esac
}

install_apt_dependencies() {
  # FreeBSD (Serv00) — use pkg
  if [[ "${OS_ID:-}" == "freebsd" ]]; then
    if command -v pkg >/dev/null 2>&1; then
      pkg install -y curl jq openssl ca_root_nss unzip 2>/dev/null || true
    fi
    return 0
  fi

  # Alpine — use apk
  if [[ "${OS_ID:-}" == "alpine" ]]; then
    apk update >/dev/null 2>&1 || true
    apk add --no-cache curl jq tar openssl util-linux iproute2 ca-certificates unzip wireguard-tools libqrencode-tools >/dev/null 2>&1 || true
    return 0
  fi

  if [[ "$OS_ID" != "ubuntu" && "$OS_ID" != "debian" ]]; then
    log_warn "$(msg "在 ${OS_ID} 上跳过 apt 依赖安装" "Skipping apt dependency install on ${OS_ID}")"
    return 0
  fi

  export DEBIAN_FRONTEND=noninteractive
  local apt_opts=(
    "-o" "Acquire::Retries=2"
    "-o" "Acquire::http::Timeout=15"
    "-o" "Acquire::https::Timeout=15"
  )
  if command -v timeout >/dev/null 2>&1; then
    timeout 90s apt-get "${apt_opts[@]}" update -y >/dev/null || die "$(msg "apt-get update 超时或失败" "apt-get update timed out/failed")"
    timeout 120s apt-get "${apt_opts[@]}" install -y curl jq tar openssl uuid-runtime iproute2 ca-certificates unzip wireguard-tools qrencode >/dev/null || die "$(msg "apt-get install 超时或失败" "apt-get install timed out/failed")"
  else
    apt-get "${apt_opts[@]}" update -y >/dev/null || die "$(msg "apt-get update 失败" "apt-get update failed")"
    apt-get "${apt_opts[@]}" install -y curl jq tar openssl uuid-runtime iproute2 ca-certificates unzip wireguard-tools qrencode >/dev/null || die "$(msg "apt-get install 失败" "apt-get install failed")"
  fi
}

download_file() {
  local url="$1"
  local out="$2"
  curl -fsSL "$url" -o "$out"
}

systemd_reload_and_enable() {
  detect_init_system 2>/dev/null || true
  case "${SBD_INIT_SYSTEM:-systemd}" in
    systemd)
      systemctl daemon-reload
      systemctl enable sing-box-deve.service >/dev/null
      ;;
    openrc)
      rc-update add sing-box-deve default 2>/dev/null || true
      ;;
    nohup)
      log_info "$(msg "nohup 模式：跳过 daemon-reload" "nohup mode: skipping daemon-reload")"
      ;;
  esac
}

safe_service_restart() {
  detect_init_system 2>/dev/null || true
  case "${SBD_INIT_SYSTEM:-systemd}" in
    systemd)
      systemctl restart sing-box-deve.service
      ;;
    openrc)
      rc-service sing-box-deve restart 2>/dev/null || true
      ;;
    nohup)
      # Caller should use sbd_service_restart with full exec_cmd
      log_warn "$(msg "nohup 模式下需通过 sbd_service_restart 重启" \
                   "Use sbd_service_restart in nohup mode")"
      ;;
  esac
}

rand_hex_8() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 4
  else
    printf '%s-%s-%s\n' "$(date +%s%N 2>/dev/null || date +%s)" "$$" "${RANDOM:-0}" | sha256sum | cut -c1-8
  fi
}

sbd_trim_whitespace() {
  local v="$1"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  printf '%s' "$v"
}

sbd_unquote_env_value() {
  local value="$1"
  if [[ "$value" == \"*\" && "$value" == *\" && "${#value}" -ge 2 ]]; then
    value="${value:1:${#value}-2}"
  elif [[ "$value" == \'*\' && "$value" == *\' && "${#value}" -ge 2 ]]; then
    value="${value:1:${#value}-2}"
  fi
  printf '%s' "$value"
}

sbd_strip_inline_env_comment() {
  local value="$1" out="" ch prev=""
  local in_single="false" in_double="false" i
  for ((i = 0; i < ${#value}; i++)); do
    ch="${value:i:1}"
    if [[ "$ch" == "'" && "$in_double" == "false" ]]; then
      if [[ "$in_single" == "true" ]]; then
        in_single="false"
      else
        in_single="true"
      fi
      out+="$ch"
      prev="$ch"
      continue
    fi
    if [[ "$ch" == "\"" && "$in_single" == "false" ]]; then
      if [[ "$in_double" == "true" ]]; then
        in_double="false"
      else
        in_double="true"
      fi
      out+="$ch"
      prev="$ch"
      continue
    fi
    if [[ "$ch" == "#" && "$in_single" == "false" && "$in_double" == "false" ]]; then
      if [[ -n "$prev" && "$prev" =~ [[:space:]] ]]; then
        break
      fi
    fi
    out+="$ch"
    prev="$ch"
  done
  printf '%s' "$out"
}

sbd_safe_load_env_file() {
  local file="$1"
  [[ -f "$file" ]] || return 1

  local raw line key value lineno=0
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    lineno=$((lineno + 1))
    line="${raw%$'\r'}"
    [[ -n "${line//[[:space:]]/}" ]] || continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    line="$(sbd_trim_whitespace "$line")"
    if [[ "$line" == export[[:space:]]* ]]; then
      line="$(sbd_trim_whitespace "${line#export}")"
    fi
    [[ "$line" == *=* ]] || die "Invalid env line (${file}:${lineno}), expected key=value"

    key="${line%%=*}"
    value="${line#*=}"
    key="$(sbd_trim_whitespace "$key")"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "Invalid env key (${file}:${lineno}): ${key}"
    value="$(sbd_strip_inline_env_comment "$value")"
    value="$(sbd_trim_whitespace "$value")"
    value="$(sbd_unquote_env_value "$value")"
    printf -v "$key" '%s' "$value"
  done < "$file"
}

sbd_load_runtime_env() {
  local runtime_file="${1:-${SBD_CONFIG_DIR}/runtime.env}"
  [[ -f "$runtime_file" ]] || return 1
  sbd_safe_load_env_file "$runtime_file"
}
