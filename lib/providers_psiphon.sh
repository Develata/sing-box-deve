#!/usr/bin/env bash

provider_psiphon_region_normalize() {
  local region="${1:-auto}"
  region="$(echo "$region" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  [[ -n "$region" ]] || region="auto"
  if [[ "$region" != "auto" && ! "$region" =~ ^[a-z]{2}$ ]]; then
    die "Invalid PSIPHON_REGION: ${region} (expected auto or 2-letter code)"
  fi
  echo "$region"
}

provider_psiphon_enabled() {
  local enabled="${PSIPHON_ENABLE:-off}" mode="${PSIPHON_MODE:-off}"
  case "${enabled,,}" in
    1|true|yes|on|enabled) ;;
    *) return 1 ;;
  esac
  [[ "${mode:-off}" != "off" ]]
}

provider_psiphon_mode_effective() {
  local mode="${PSIPHON_MODE:-off}"
  case "$mode" in
    global) echo "proxy" ;;
    *) echo "$mode" ;;
  esac
}

provider_psiphon_use_as_primary() {
  provider_psiphon_enabled || return 1
  [[ "$(provider_psiphon_mode_effective)" == "proxy" ]]
}

provider_psiphon_client_bin() {
  local candidate
  for candidate in \
    "${PSIPHON_CLIENT_BIN:-}" \
    "${SBD_BIN_DIR}/psiphon-tunnel-core" \
    "${SBD_BIN_DIR}/psiphon" \
    "/usr/local/bin/psiphon-tunnel-core" \
    "/usr/bin/psiphon-tunnel-core" \
    "/usr/local/bin/psiphon" \
    "/usr/bin/psiphon"; do
    [[ -n "$candidate" ]] || continue
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

provider_psiphon_detect_client() {
  local bin
  if bin="$(provider_psiphon_client_bin)"; then
    log_success "$(msg "Psiphon 客户端已就绪: ${bin}" "Psiphon client detected: ${bin}")"
    return 0
  fi
  log_warn "$(msg "未检测到 Psiphon 客户端二进制" "Psiphon client binary not found")"
  return 1
}

provider_psiphon_install_client() {
  ensure_root
  provider_psiphon_detect_client && return 0

  # Try downloading pre-compiled binary first
  if install_psiphon_prebuilt; then
    provider_psiphon_detect_client && return 0
  fi

  [[ -n "${OS_ID:-}" ]] || detect_os
  if [[ "${OS_ID:-}" != "ubuntu" && "${OS_ID:-}" != "debian" ]]; then
    die "Psiphon client missing. Set PSIPHON_CLIENT_BIN to an installed binary path."
  fi
  local pkg
  for pkg in psiphon-tunnel-core psiphon; do
    if apt-get install -y "$pkg" >/dev/null 2>&1; then
      break
    fi
  done
  provider_psiphon_detect_client || die "Unable to install/detect Psiphon client. Set PSIPHON_CLIENT_BIN manually."
}

# Download pre-compiled psiphon-tunnel-core binary
install_psiphon_prebuilt() {
  local arch
  arch="$(get_arch)"
  local os_name="linux"
  [[ "${OS_ID:-}" == "freebsd" ]] && os_name="freebsd"

  local bin_url=""
  local bin_out="${SBD_BIN_DIR}/psiphon-tunnel-core"

  # Try Psiphon Labs official releases
  local psiphon_base="https://raw.githubusercontent.com/AzadDevX/PROXY-List/main/psiphon"
  local gh_release="https://github.com/nicekid1/Psiphon-tunnel/releases/latest/download"

  # Architecture mapping
  local asset_suffix="${os_name}-${arch}"

  local candidates=(
    "${gh_release}/psiphon-tunnel-core-${asset_suffix}"
    "${psiphon_base}/psiphon-tunnel-core_${asset_suffix}"
  )

  mkdir -p "$SBD_BIN_DIR"

  local url
  for url in "${candidates[@]}"; do
    log_info "$(msg "尝试下载 Psiphon: ${url}" "Trying to download Psiphon: ${url}")"
    if curl -fsSL --max-time 30 "$url" -o "$bin_out" 2>/dev/null; then
      chmod 0755 "$bin_out"
      if [[ -x "$bin_out" ]] && "$bin_out" --help >/dev/null 2>&1; then
        log_success "$(msg "Psiphon 预编译二进制已下载" "Psiphon pre-built binary downloaded")"
        return 0
      fi
      rm -f "$bin_out"
    fi
  done

  log_warn "$(msg "无法下载预编译 Psiphon 二进制" "Failed to download pre-built Psiphon binary")"
  return 1
}

provider_psiphon_default_socks_port() { echo "11080"; }
provider_psiphon_default_http_port() { echo "11081"; }

provider_psiphon_exec_command() {
  local bin="$1" region="$2" socks_port="$3" http_port="$4"
  if [[ -n "${PSIPHON_CLIENT_CMD:-}" ]]; then
    local cmd="${PSIPHON_CLIENT_CMD}"
    cmd="${cmd//\{\{region\}\}/${region}}"
    cmd="${cmd//\{\{socks_port\}\}/${socks_port}}"
    cmd="${cmd//\{\{http_port\}\}/${http_port}}"
    echo "$cmd"
    return 0
  fi
  # Default command assumes common CLI flags; can be overridden via PSIPHON_CLIENT_CMD.
  echo "${bin} --region ${region} --local-socks-port ${socks_port} --local-http-proxy-port ${http_port}"
}

provider_psiphon_sync_service() {
  ensure_root
  if ! provider_psiphon_enabled; then
    systemctl disable --now sing-box-deve-psiphon.service >/dev/null 2>&1 || true
    rm -f "$SBD_PSIPHON_SERVICE_FILE"
    systemctl daemon-reload
    return 0
  fi

  provider_psiphon_install_client
  local bin exec_cmd region socks_port http_port log_file
  bin="$(provider_psiphon_client_bin)" || die "Psiphon client not found after install attempt"
  region="$(provider_psiphon_region_normalize "${PSIPHON_REGION:-auto}")"
  socks_port="$(provider_psiphon_default_socks_port)"
  http_port="$(provider_psiphon_default_http_port)"
  log_file="${SBD_DATA_DIR}/psiphon.log"
  exec_cmd="$(provider_psiphon_exec_command "$bin" "$region" "$socks_port" "$http_port")"

  cat > "$SBD_PSIPHON_SERVICE_FILE" <<EOF
[Unit]
Description=sing-box-deve psiphon sidecar
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash -lc '${exec_cmd}'
StandardOutput=append:${log_file}
StandardError=append:${log_file}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable sing-box-deve-psiphon.service >/dev/null
  systemctl restart sing-box-deve-psiphon.service
}

provider_psiphon_stop_service() {
  ensure_root
  systemctl disable --now sing-box-deve-psiphon.service >/dev/null 2>&1 || true
  rm -f "$SBD_PSIPHON_SERVICE_FILE"
  systemctl daemon-reload
}

provider_psiphon_detect_exit_ip() {
  local socks_port ip
  socks_port="$(provider_psiphon_default_socks_port)"
  ip="$(curl -fsS --max-time 5 --socks5-hostname "127.0.0.1:${socks_port}" https://api64.ipify.org 2>/dev/null || true)"
  ip="${ip//$'\n'/}"
  [[ -n "$ip" ]] && echo "$ip"
}

provider_psiphon_status() {
  local runtime_file="/etc/sing-box-deve/runtime.env"
  local mode="off" region="auto" enabled="off" state="stopped" ip=""
  if [[ -f "$runtime_file" ]]; then
    sbd_safe_load_env_file "$runtime_file"
    mode="${psiphon_mode:-off}"
    region="${psiphon_region:-auto}"
    enabled="${psiphon_enable:-off}"
  fi
  if systemctl is-active --quiet sing-box-deve-psiphon.service; then
    state="running"
    ip="$(provider_psiphon_detect_exit_ip || true)"
  fi
  log_info "$(msg "Psiphon: 状态=${state} 启用=${enabled} 模式=${mode} 地区=${region} 出口IP=${ip:-unknown}" "Psiphon: state=${state} enabled=${enabled} mode=${mode} region=${region} exit_ip=${ip:-unknown}")"
}

provider_psiphon_set_region() {
  ensure_root
  local region
  region="$(provider_psiphon_region_normalize "${1:-}")"
  provider_cfg_load_runtime_exports
  PSIPHON_REGION="$region"
  provider_cfg_rebuild_runtime
  log_success "$(msg "Psiphon 地区已更新: ${region}" "Psiphon region updated: ${region}")"
}

provider_psiphon_start() {
  ensure_root
  provider_cfg_load_runtime_exports
  PSIPHON_ENABLE="on"
  [[ "${PSIPHON_MODE:-off}" == "off" ]] && PSIPHON_MODE="proxy"
  provider_cfg_rebuild_runtime
  log_success "$(msg "Psiphon 已启动" "Psiphon started")"
}

provider_psiphon_stop() {
  ensure_root
  provider_cfg_load_runtime_exports
  PSIPHON_ENABLE="off"
  PSIPHON_MODE="off"
  provider_cfg_rebuild_runtime
  log_success "$(msg "Psiphon 已停止" "Psiphon stopped")"
}

provider_psiphon_command() {
  case "${1:-status}" in
    status) provider_psiphon_status ;;
    start) provider_psiphon_start ;;
    stop) provider_psiphon_stop ;;
    set-region) provider_psiphon_set_region "${2:-}" ;;
    *)
      die "Usage: psiphon [status|start|stop|set-region <auto|cc>]"
      ;;
  esac
}

provider_psiphon_doctor_check() {
  local enabled="${psiphon_enable:-off}" mode="${psiphon_mode:-off}"
  local enabled_bool="false"
  case "${enabled,,}" in
    1|true|yes|on|enabled) enabled_bool="true" ;;
  esac
  if [[ "$enabled_bool" != "true" || "${mode}" == "off" ]]; then
    log_info "$(msg "Psiphon: 未启用" "Psiphon: disabled")"
    return 0
  fi
  if [[ ! -f "$SBD_PSIPHON_SERVICE_FILE" ]]; then
    log_warn "$(msg "Psiphon: 已启用但服务文件缺失" "Psiphon: enabled but service file missing")"
    return 0
  fi
  if systemctl is-active --quiet sing-box-deve-psiphon.service; then
    log_success "$(msg "Psiphon 服务状态: 运行中" "Psiphon service status: active")"
  else
    log_warn "$(msg "Psiphon 服务状态: 未运行" "Psiphon service status: inactive")"
  fi
}
