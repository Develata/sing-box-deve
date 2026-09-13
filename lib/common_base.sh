#!/usr/bin/env bash
# shellcheck disable=SC2034

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common_runtime_schema.sh"

# This base is also sourced directly by the focused regression tests.
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common_io.sh"
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common_lock.sh"

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
SBD_NODE_MODEL_FILE="${SBD_DATA_DIR}/nodes-model.json"
SBD_ARGO_TOKEN_FILE="${SBD_DATA_DIR}/argo-token"
SBD_ARGO_EXEC_FILE="${SBD_DATA_DIR}/argo-exec"
SBD_SERVICE_FILE="/etc/systemd/system/sing-box-deve.service"
SBD_ARGO_SERVICE_FILE="/etc/systemd/system/sing-box-deve-argo.service"
SBD_WARP_SOCKS_SERVICE_FILE="/etc/systemd/system/sing-box-deve-warp-socks5.service"
SBD_FW_REPLAY_SERVICE_FILE="/etc/systemd/system/sing-box-deve-fw-replay.service"

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

  if [[ ! -t 0 ]]; then
    log_error "Confirmation requires a terminal or explicit --yes: ${prompt}"
    return 1
  fi

  if [[ "$default_answer" == "Y" ]]; then
    read -r -p "${prompt} [Y/n]: " answer || return 1
    answer="${answer:-Y}"
    [[ "$answer" =~ ^[Yy]$ ]]
    return $?
  fi

  read -r -p "${prompt} [y/N]: " answer || return 1
  answer="${answer:-N}"
  [[ "$answer" =~ ^[Yy]$ ]]
}

prompt_with_default() {
  local prompt="$1"
  local default_value="$2"
  local out_var="$3"
  local answer
  [[ -t 0 ]] || { log_error "Input requires a terminal: ${prompt}"; return 1; }
  read -r -p "${prompt} (default: ${default_value}): " answer || return 1
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
  mkdir -p "$SBD_STATE_DIR" "$SBD_CONFIG_DIR" "$SBD_RUNTIME_DIR" "$SBD_BIN_DIR" "$SBD_DATA_DIR" "$SBD_CACHE_DIR" "$(dirname "$SBD_SERVICE_FILE")" || return 1
  touch "$SBD_RULES_FILE" || return 1
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
  case "${OS_ID:-}" in
    freebsd)
      sbd_package_op pkg install -y curl jq openssl ca_root_nss unzip coreutils python3 || return 1 ;;
    alpine)
      sbd_package_op apk update || return 1
      sbd_package_op apk add --no-cache curl jq tar openssl util-linux coreutils iproute2 ca-certificates unzip libqrencode-tools xxd python3 || return 1 ;;
    ubuntu|debian)
      sbd_apt_get update -y || return 1
      sbd_apt_get install -y curl jq tar openssl uuid-runtime iproute2 ca-certificates unzip qrencode xxd python3 coreutils util-linux || return 1 ;;
    *) log_warn "Skipping dependency installation on unsupported OS: ${OS_ID:-unknown}" ;;
  esac
}

download_file() {
  local url="$1"
  local out="$2"
  local attempts="${SBD_DOWNLOAD_RETRIES:-3}"
  local delay="${SBD_DOWNLOAD_RETRY_DELAY:-2}"
  local max_time="${SBD_DOWNLOAD_MAX_TIME:-300}"
  local budget="${SBD_DOWNLOAD_TOTAL_TIME:-$max_time}" deadline remaining tmp err rc attempt
  sbd_positive_seconds "$attempts" && sbd_positive_seconds "$max_time" && sbd_positive_seconds "$budget" || return 2
  [[ "$delay" =~ ^[0-9]+$ ]] || return 2
  deadline=$((SECONDS + budget))
  tmp="${out}.tmp.$$"
  err="${out}.err.$$"
  mkdir -p "$(dirname "$out")"
  rm -f "$tmp" "$err" 2>/dev/null || true

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    remaining=$((deadline - SECONDS))
    (( remaining > 0 )) || break
    (( remaining <= max_time )) || remaining="$max_time"
    if curl -fsSL --connect-timeout 15 --max-time "$remaining" "$url" -o "$tmp" 2>"$err"; then
      mv -f "$tmp" "$out" || { rm -f "$tmp" "$err"; return 1; }
      rm -f "$err" 2>/dev/null || true
      return 0
    else
      rc=$?
    fi
    log_warn "$(msg "下载失败(${attempt}/${attempts}, rc=${rc}): ${url}" "Download failed (${attempt}/${attempts}, rc=${rc}): ${url}")"
    if [[ -s "$err" ]]; then
      log_warn "$(tail -n 2 "$err" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    fi
    rm -f "$tmp" 2>/dev/null || true
    if (( attempt < attempts && SECONDS + delay < deadline )); then sleep "$delay"; fi
  done

  rm -f "$tmp" "$err" 2>/dev/null || true
  return 1
}

systemd_reload_and_enable() {
  detect_init_system 2>/dev/null || true
  case "${SBD_INIT_SYSTEM:-systemd}" in
    systemd)
      sbd_service_daemon_reload || return 1
      sbd_service_op systemctl enable sing-box-deve.service >/dev/null
      ;;
    openrc)
      sbd_service_op rc-update add sing-box-deve default || return 1
      ;;
    nohup)
      log_info "$(msg "nohup 模式：跳过 daemon-reload" "nohup mode: skipping daemon-reload")"
      ;;
  esac
}

safe_service_restart() {
  local runtime_engine="${engine:-sing-box}"
  local -a argv
  case "$runtime_engine" in
    sing-box) argv=("${SBD_BIN_DIR}/sing-box" run -c "${SBD_CONFIG_DIR}/config.json") ;;
    xray) argv=("${SBD_BIN_DIR}/xray" run -config "${SBD_CONFIG_DIR}/xray-config.json") ;;
    *) log_error "Unsupported runtime engine: ${runtime_engine}"; return 1 ;;
  esac
  sbd_service_restart "sing-box-deve" "${argv[@]}" || return 1
  sbd_service_wait_active "sing-box-deve" 10
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
  local value="$1" out="" ch next i
  if [[ "$value" == \"*\" && "$value" == *\" && "${#value}" -ge 2 ]]; then
    value="${value:1:${#value}-2}"
    for ((i = 0; i < ${#value}; i++)); do
      ch="${value:i:1}"
      if [[ "$ch" == "\\" && $((i + 1)) -lt ${#value} ]]; then
        next="${value:i+1:1}"
        if [[ "$next" == "\\" || "$next" == '"' ]]; then
          out+="$next"
          i=$((i + 1))
          continue
        fi
      fi
      out+="$ch"
    done
    value="$out"
  elif [[ "$value" == \'*\' && "$value" == *\' && "${#value}" -ge 2 ]]; then
    value="${value:1:${#value}-2}"
  fi
  printf '%s' "$value"
}

sbd_env_quote() {
  local value="$1"
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || die "Env value must be single-line"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}

sbd_write_env_kv() {
  local key="$1" value="${2:-}"
  [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "Invalid env key: ${key}"
  local quoted
  quoted="$(sbd_env_quote "$value")" || return 1
  printf '%s=%s\n' "$key" "$quoted"
}

sbd_strip_inline_env_comment() {
  local value="$1" out="" ch prev=""
  local in_single="false" in_double="false" escaped="false" i
  for ((i = 0; i < ${#value}; i++)); do
    ch="${value:i:1}"
    if [[ "$in_double" == "true" && "$ch" == "\\" ]]; then
      out+="$ch"
      if [[ "$escaped" == "true" ]]; then
        escaped="false"
      else
        escaped="true"
      fi
      prev="$ch"
      continue
    fi
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
    if [[ "$ch" == "\"" && "$in_single" == "false" && "$escaped" == "false" ]]; then
      if [[ "$in_double" == "true" ]]; then
        in_double="false"
      else
        in_double="true"
      fi
      out+="$ch"
      prev="$ch"
      continue
    fi
    escaped="false"
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

sbd_parse_env_file() {
  local _sbd_file="$1" _sbd_raw _sbd_line _sbd_key _sbd_value _sbd_first
  local -n _sbd_result="$2"
  [[ -f "$_sbd_file" && ! -L "$_sbd_file" ]] || return 1
  while IFS= read -r _sbd_raw || [[ -n "$_sbd_raw" ]]; do
    _sbd_line="$(sbd_trim_whitespace "${_sbd_raw%$'\r'}")"
    [[ -n "$_sbd_line" && "$_sbd_line" != \#* ]] || continue
    [[ "$_sbd_line" != export[[:space:]]* ]] || _sbd_line="$(sbd_trim_whitespace "${_sbd_line#export}")"
    [[ "$_sbd_line" == *=* ]] || { log_error "Invalid env line"; return 1; }
    _sbd_key="$(sbd_trim_whitespace "${_sbd_line%%=*}")"
    [[ "$_sbd_key" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] || return 1
    case "$_sbd_key" in PATH|HOME|SHELL|IFS|ENV|BASH*|LD_*|SBD_*|PROJECT_ROOT|SECONDS|RANDOM|UID|EUID) log_error "Reserved env key: $_sbd_key"; return 1 ;; esac
    [[ ! -v '_sbd_result[$_sbd_key]' ]] || { log_error "Duplicate env key: $_sbd_key"; return 1; }
    _sbd_value="$(sbd_strip_inline_env_comment "${_sbd_line#*=}")"
    _sbd_value="$(sbd_trim_whitespace "$_sbd_value")"
    _sbd_first="${_sbd_value:0:1}"
    if [[ "$_sbd_first" == \" || "$_sbd_first" == \' ]]; then
      [[ ${#_sbd_value} -ge 2 && "${_sbd_value: -1}" == "$_sbd_first" ]] || { log_error "Unterminated env quote"; return 1; }
    fi
    _sbd_result["$_sbd_key"]="$(sbd_unquote_env_value "$_sbd_value")" || return 1
  done < "$_sbd_file"
}

sbd_safe_load_env_file() {
  local -A _sbd_values=()
  local _sbd_name
  sbd_parse_env_file "$1" _sbd_values || return 1
  for _sbd_name in "${!_sbd_values[@]}"; do
    printf -v "$_sbd_name" '%s' "${_sbd_values[$_sbd_name]}" || return 1
  done
}

sbd_load_runtime_env() {
  local -A _sbd_values=()
  local _sbd_name
  sbd_verify_runtime_file "${1:-${SBD_CONFIG_DIR}/runtime.env}" || return 1
  sbd_parse_env_file "${1:-${SBD_CONFIG_DIR}/runtime.env}" _sbd_values || return 1
  sbd_validate_runtime_values _sbd_values || return 1
  # Clear omitted optional fields to prevent state leaking from an earlier load.
  while IFS= read -r _sbd_name; do
    printf -v "$_sbd_name" '%s' "${_sbd_values[$_sbd_name]:-}" || return 1
  done < <(sbd_runtime_keys)
}
