#!/usr/bin/env bash

SBD_STATE_DIR="/var/lib/sing-box-deve"
SBD_CONFIG_DIR="/etc/sing-box-deve"
SBD_RUNTIME_DIR="/run/sing-box-deve"
SBD_RULES_FILE="${SBD_STATE_DIR}/firewall-rules.db"
SBD_CONTEXT_FILE="${SBD_STATE_DIR}/context.env"
SBD_FW_SNAPSHOT_FILE="${SBD_STATE_DIR}/firewall-rules.snapshot"
CONFIG_SNAPSHOT_FILE="${SBD_CONFIG_DIR}/config.yaml"
SBD_SETTINGS_FILE="${SBD_CONFIG_DIR}/settings.conf"
SBD_INSTALL_DIR="/opt/sing-box-deve"
SBD_BIN_DIR="${SBD_INSTALL_DIR}/bin"
SBD_DATA_DIR="${SBD_INSTALL_DIR}/data"
SBD_NODES_FILE="${SBD_DATA_DIR}/nodes.txt"
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

load_settings() {
  if [[ "$SETTINGS_INITIALIZED" == "true" ]]; then
    return 0
  fi

  mkdir -p "$SBD_CONFIG_DIR" >/dev/null 2>&1 || true

  if [[ ! -f "$SBD_SETTINGS_FILE" && -f "${SBD_CONFIG_DIR}/lang" ]]; then
    local legacy_lang
    legacy_lang="$(tr -d '[:space:]' < "${SBD_CONFIG_DIR}/lang" 2>/dev/null || true)"
    [[ "$legacy_lang" == "zh" || "$legacy_lang" == "en" ]] || legacy_lang="en"
    LANG_CODE="$legacy_lang"
    save_settings
    rm -f "${SBD_CONFIG_DIR}/lang"
  fi

  if [[ -f "$SBD_SETTINGS_FILE" ]]; then
    local line
    line="$(head -n1 "$SBD_SETTINGS_FILE" 2>/dev/null || true)"
    if [[ -n "$line" ]]; then
      local IFS=';'
      local kv
      read -r -a _pairs <<< "$line"
      for kv in "${_pairs[@]}"; do
        local key="${kv%%=*}"
        local val="${kv#*=}"
        case "$key" in
          lang) [[ "$val" == "zh" || "$val" == "en" ]] && LANG_CODE="$val" ;;
          auto_yes) [[ "$val" == "true" || "$val" == "false" ]] && AUTO_YES="$val" ;;
          update_channel) [[ -n "$val" ]] && UPDATE_CHANNEL="$val" ;;
        esac
      done
    fi
  fi

  SETTINGS_INITIALIZED="true"
}

save_settings() {
  mkdir -p "$SBD_CONFIG_DIR" >/dev/null 2>&1 || true
  if [[ -w "$SBD_CONFIG_DIR" || "${EUID}" -eq 0 ]]; then
    printf 'lang=%s;auto_yes=%s;update_channel=%s\n' "$LANG_CODE" "$AUTO_YES" "$UPDATE_CHANNEL" > "$SBD_SETTINGS_FILE"
  fi
}

set_setting() {
  local key="$1"
  local value="$2"
  load_settings
  case "$key" in
    lang)
      [[ "$value" == "zh" || "$value" == "en" ]] || die "Invalid lang: $value"
      LANG_CODE="$value"
      ;;
    auto_yes)
      [[ "$value" == "true" || "$value" == "false" ]] || die "Invalid auto_yes: $value"
      AUTO_YES="$value"
      ;;
    update_channel)
      [[ -n "$value" ]] || die "update_channel cannot be empty"
      UPDATE_CHANNEL="$value"
      ;;
    *)
      die "Unknown setting key: $key"
      ;;
  esac
  save_settings
}

show_settings() {
  load_settings
  printf 'lang=%s;auto_yes=%s;update_channel=%s\n' "$LANG_CODE" "$AUTO_YES" "$UPDATE_CHANNEL"
}

init_i18n() {
  load_settings

  if [[ -f "$SBD_SETTINGS_FILE" ]]; then
    return 0
  fi

  if [[ ! -t 0 ]]; then
    LANG_CODE="en"
    save_settings
    return 0
  fi

  local choose
  echo "Select language / 选择语言"
  echo "1) 中文"
  echo "2) English"
  read -r -p "Choose [1/2] (default: 1): " choose
  case "${choose:-1}" in
    1) LANG_CODE="zh" ;;
    2) LANG_CODE="en" ;;
    *) LANG_CODE="zh" ;;
  esac

  save_settings
}

current_script_version() {
  local version_file="${PROJECT_ROOT}/version"
  if [[ -f "$version_file" ]]; then
    tr -d '[:space:]' < "$version_file"
  else
    echo "v0.0.0-dev"
  fi
}

resolve_update_base_url() {
  if [[ -n "${SBD_UPDATE_BASE_URL:-}" ]]; then
    echo "$SBD_UPDATE_BASE_URL"
    return 0
  fi

  local origin=""
  if command -v git >/dev/null 2>&1 && [[ -d "${PROJECT_ROOT}/.git" ]]; then
    origin="$(git -C "$PROJECT_ROOT" config --get remote.origin.url 2>/dev/null || true)"
  fi

  if [[ "$origin" =~ ^git@github.com:([^/]+)/([^/.]+)(\.git)?$ ]]; then
    echo "https://raw.githubusercontent.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}/main"
    return 0
  fi

  if [[ "$origin" =~ ^https://github.com/([^/]+)/([^/.]+)(\.git)?$ ]]; then
    echo "https://raw.githubusercontent.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}/main"
    return 0
  fi

  echo ""
}

fetch_remote_script_version() {
  local base_url
  base_url="$(resolve_update_base_url)"
  [[ -n "$base_url" ]] || return 1
  curl -fsSL "${base_url}/version" 2>/dev/null | tr -d '[:space:]'
}

perform_script_self_update() {
  local base_url
  base_url="$(resolve_update_base_url)"
  [[ -n "$base_url" ]] || die "Cannot resolve update URL. Set SBD_UPDATE_BASE_URL first."

  local files=(
    "sing-box-deve.sh"
    "version"
    "README.md"
    "CHANGELOG.md"
    "CONTRIBUTING.md"
    "LICENSE"
    "config.env.example"
    "lib/common.sh"
    "lib/protocols.sh"
    "lib/security.sh"
    "lib/providers.sh"
    "lib/output.sh"
    "docs/README.md"
    "docs/V1-SPEC.md"
    "docs/CONVENTIONS.md"
    "docs/ACCEPTANCE-MATRIX.md"
    "docs/Serv00.md"
    "docs/SAP.md"
    "docs/Docker.md"
    "examples/vps-lite.env"
    "examples/vps-full-argo.env"
    "examples/docker.env"
    "examples/settings.conf"
    "examples/serv00-accounts.json"
    "examples/sap-accounts.json"
    "web-generator/index.html"
    "scripts/acceptance-matrix.sh"
    "scripts/update-checksums.sh"
    ".github/workflows/main.yml"
    ".github/workflows/mainh.yml"
    ".github/workflows/ci.yml"
    "workers/_worker.js"
    "workers/workers_keep.js"
  )

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local checksums_file="${tmp_dir}/checksums.txt"
  if ! download_file "${base_url}/checksums.txt" "$checksums_file"; then
    die "Secure update requires checksums.txt at update source"
  fi

  local rel
  for rel in "${files[@]}"; do
    mkdir -p "${tmp_dir}/$(dirname "$rel")"
    download_file "${base_url}/${rel}" "${tmp_dir}/${rel}"
    local expected actual
    expected="$(grep -E "[[:space:]]${rel}$" "$checksums_file" | awk '{print $1}' | head -n1)"
    [[ -n "$expected" ]] || die "Missing checksum entry for ${rel}"
    actual="$(sha256sum "${tmp_dir}/${rel}" | awk '{print $1}')"
    [[ "$expected" == "$actual" ]] || die "Checksum mismatch for ${rel}"
  done

  for rel in "${files[@]}"; do
    install -D -m 0644 "${tmp_dir}/${rel}" "${PROJECT_ROOT}/${rel}"
  done

  chmod +x "${PROJECT_ROOT}/sing-box-deve.sh" \
    "${PROJECT_ROOT}/lib/common.sh" "${PROJECT_ROOT}/lib/protocols.sh" "${PROJECT_ROOT}/lib/security.sh" "${PROJECT_ROOT}/lib/providers.sh" "${PROJECT_ROOT}/lib/output.sh" \
    "${PROJECT_ROOT}/scripts/acceptance-matrix.sh" "${PROJECT_ROOT}/scripts/update-checksums.sh" || true
  rm -rf "$tmp_dir"
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
  apt-get update -y >/dev/null
  apt-get install -y curl jq tar openssl uuid-runtime iproute2 ca-certificates unzip wireguard-tools >/dev/null
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
    date +%s | sha256sum | cut -c1-8
  fi
}

create_install_context() {
  local provider="$1"
  local profile="$2"
  local engine="$3"
  local protocols_csv="$4"
  local argo_mode="${ARGO_MODE:-off}"
  local argo_domain="${ARGO_DOMAIN:-}"
  local argo_token="${ARGO_TOKEN:-}"
  local warp_mode="${WARP_MODE:-off}"
  local outbound_proxy_mode="${OUTBOUND_PROXY_MODE:-direct}"
  local outbound_proxy_host="${OUTBOUND_PROXY_HOST:-}"
  local outbound_proxy_port="${OUTBOUND_PROXY_PORT:-}"
  local outbound_proxy_user="${OUTBOUND_PROXY_USER:-}"
  local outbound_proxy_pass="${OUTBOUND_PROXY_PASS:-}"

  local install_id
  install_id="$(rand_hex_8)"
  local created_at
  created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  cat > "$SBD_CONTEXT_FILE" <<EOF
install_id=${install_id}
created_at=${created_at}
provider=${provider}
profile=${profile}
engine=${engine}
protocols=${protocols_csv}
argo_mode=${argo_mode}
argo_domain=${argo_domain}
argo_token_set=$([[ -n "${argo_token}" ]] && echo true || echo false)
warp_mode=${warp_mode}
outbound_proxy_mode=${outbound_proxy_mode}
outbound_proxy_host=${outbound_proxy_host}
outbound_proxy_port=${outbound_proxy_port}
outbound_proxy_user_set=$([[ -n "${outbound_proxy_user}" ]] && echo true || echo false)
outbound_proxy_pass_set=$([[ -n "${outbound_proxy_pass}" ]] && echo true || echo false)
EOF
}

load_install_context() {
  if [[ -f "$SBD_CONTEXT_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$SBD_CONTEXT_FILE"
    return 0
  fi
  return 1
}

auto_generate_config_snapshot() {
  local file_path="$1"
  load_install_context || die "Install context not found"

  cat > "$file_path" <<EOF
version: v1
generated_at: ${created_at}
provider: ${provider}
profile: ${profile}
engine: ${engine}
protocols:
$(echo "$protocols" | tr ',' '\n' | sed 's/^/  - /')
security:
  firewall_managed: true
  firewall_mode: incremental_with_rollback
  destructive_firewall_actions: false
features:
  argo_mode: ${argo_mode:-off}
  argo_domain: ${argo_domain:-""}
  argo_token_set: ${argo_token_set:-false}
  warp_mode: ${warp_mode:-off}
  outbound_proxy_mode: ${outbound_proxy_mode:-direct}
  outbound_proxy_host: ${outbound_proxy_host:-""}
  outbound_proxy_port: ${outbound_proxy_port:-""}
  outbound_proxy_user_set: ${outbound_proxy_user_set:-false}
  outbound_proxy_pass_set: ${outbound_proxy_pass_set:-false}
resources:
  default_profile: ${profile}
EOF

  log_info "Auto-generated config snapshot: ${file_path}"
}

doctor_system() {
  local deps=(curl awk sed grep cut tr ss)
  local missing=0
  for dep in "${deps[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      log_warn "Missing dependency: $dep"
      missing=1
    fi
  done

  if [[ "$missing" -eq 0 ]]; then
    log_success "Core dependencies present"
  else
    log_warn "Some dependencies are missing"
  fi

  local mem_kb
  mem_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
  if [[ -n "$mem_kb" ]]; then
    local mem_mb
    mem_mb=$((mem_kb / 1024))
    log_info "Detected memory: ${mem_mb}MB"
    if (( mem_mb <= 600 )); then
      log_info "Small-memory host detected; Lite profile is recommended"
    fi
  fi

  if curl -fsS --max-time 5 https://1.1.1.1 >/dev/null 2>&1; then
    log_success "Outbound HTTPS reachability: ok"
  else
    log_warn "Outbound HTTPS reachability: failed"
  fi

  if command -v getent >/dev/null 2>&1; then
    if getent hosts github.com >/dev/null 2>&1; then
      log_success "DNS resolution check: ok"
    else
      log_warn "DNS resolution check: failed"
    fi
  fi
}
