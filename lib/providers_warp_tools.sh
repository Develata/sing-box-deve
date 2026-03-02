#!/usr/bin/env bash

SBD_WARP_SOCKS_CONFIG_FILE="${SBD_CONFIG_DIR}/warp-socks5.json"
SBD_WARP_SOCKS_SERVICE_FILE="/etc/systemd/system/sing-box-deve-warp-socks5.service"
SBD_WARP_SOCKS_PORT_FILE="${SBD_DATA_DIR}/warp-socks5-port"

provider_warp_account_env_file() {
  echo "${SBD_DATA_DIR}/warp-account.env"
}

provider_warp_load_account() {
  local account_file
  account_file="$(provider_warp_account_env_file)"
  [[ -f "$account_file" ]] || die "$(msg "未找到 WARP 账户，请先执行 warp register" "WARP account not found, run warp register first")"
  sbd_safe_load_env_file "$account_file"
  WARP_PRIVATE_KEY="${WARP_PRIVATE_KEY:-}"
  WARP_PEER_PUBLIC_KEY="${WARP_PEER_PUBLIC_KEY:-bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=}"
  WARP_RESERVED="${WARP_RESERVED:-[0,0,0]}"
  WARP_LOCAL_V4="${WARP_LOCAL_V4:-172.16.0.2/32}"
  WARP_LOCAL_V6="${WARP_LOCAL_V6:-2606:4700:110:876d:4d3c:4206:c90c:6bd0/128}"
  WARP_CLIENT_ID="${WARP_CLIENT_ID:-}"
  [[ -n "$WARP_PRIVATE_KEY" ]] || die "$(msg "WARP_PRIVATE_KEY 为空，请重新执行 warp register" "WARP_PRIVATE_KEY is empty, run warp register again")"
}

provider_warp_mask_secret() {
  local value="${1:-}" len
  len="${#value}"
  if (( len <= 10 )); then
    echo "******"
  else
    echo "${value:0:6}...${value:len-4:4}"
  fi
}

provider_warp_account_load_optional() {
  local account_file
  account_file="$(provider_warp_account_env_file)"

  WARP_PRIVATE_KEY=""
  WARP_PEER_PUBLIC_KEY="bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="
  WARP_RESERVED="[0,0,0]"
  WARP_LOCAL_V4="172.16.0.2/32"
  WARP_LOCAL_V6="2606:4700:110:876d:4d3c:4206:c90c:6bd0/128"
  WARP_CLIENT_ID=""

  if [[ -f "$account_file" ]]; then
    sbd_safe_load_env_file "$account_file"
  fi
  WARP_PEER_PUBLIC_KEY="${WARP_PEER_PUBLIC_KEY:-bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=}"
  WARP_RESERVED="${WARP_RESERVED:-[0,0,0]}"
  WARP_LOCAL_V4="${WARP_LOCAL_V4:-172.16.0.2/32}"
  WARP_LOCAL_V6="${WARP_LOCAL_V6:-2606:4700:110:876d:4d3c:4206:c90c:6bd0/128}"
  WARP_CLIENT_ID="${WARP_CLIENT_ID:-}"
}

provider_warp_normalize_local_v4() {
  local value="${1:-172.16.0.2/32}"
  [[ "$value" == */* ]] || value="${value}/32"
  echo "$value"
}

provider_warp_normalize_local_v6() {
  local value="${1:-2606:4700:110:876d:4d3c:4206:c90c:6bd0/128}"
  [[ "$value" == */* ]] || value="${value}/128"
  echo "$value"
}

provider_warp_normalize_reserved() {
  local value
  value="$(echo "${1:-[0,0,0]}" | tr -d '[:space:]')"
  [[ "$value" =~ ^\[[0-9]{1,3},[0-9]{1,3},[0-9]{1,3}\]$ ]] || \
    die "$(msg "WARP_RESERVED 格式错误，必须为 [n,n,n]" "Invalid WARP_RESERVED format, expected [n,n,n]")"

  local body a b c
  body="${value#[}"
  body="${body%]}"
  IFS=',' read -r a b c <<< "$body"
  for n in "$a" "$b" "$c"; do
    (( n >= 0 && n <= 255 )) || die "$(msg "WARP_RESERVED 每一项必须在 0-255" "Each WARP_RESERVED item must be 0-255")"
  done
  echo "$value"
}

provider_warp_account_write() {
  local private_key="$1" peer_public_key="$2" reserved="$3" local_v4="$4" local_v6="$5" client_id="${6:-}"
  mkdir -p "$SBD_DATA_DIR"
  cat > "${SBD_DATA_DIR}/warp-account.env" <<EOF
WARP_PRIVATE_KEY=${private_key}
WARP_PEER_PUBLIC_KEY=${peer_public_key}
WARP_RESERVED=${reserved}
WARP_CLIENT_ID=${client_id}
WARP_LOCAL_V4=${local_v4}
WARP_LOCAL_V6=${local_v6}
EOF
  chmod 600 "${SBD_DATA_DIR}/warp-account.env"
  if [[ -n "$client_id" ]]; then
    printf '%s\n' "$client_id" > "${SBD_DATA_DIR}/warp-client-id"
    chmod 600 "${SBD_DATA_DIR}/warp-client-id"
  else
    rm -f "${SBD_DATA_DIR}/warp-client-id"
  fi
}

provider_warp_account_show() {
  provider_warp_account_load_optional
  if [[ -z "${WARP_PRIVATE_KEY:-}" ]]; then
    log_warn "$(msg "尚未配置 WARP 账户，可先执行 warp register 或 warp account-set" "WARP account not configured yet, run warp register or warp account-set first")"
    return 0
  fi
  log_info "WARP account:"
  printf '%s\n' "  private_key      : $(provider_warp_mask_secret "${WARP_PRIVATE_KEY}")"
  printf '%s\n' "  peer_public_key  : ${WARP_PEER_PUBLIC_KEY:-}"
  printf '%s\n' "  reserved         : ${WARP_RESERVED:-[0,0,0]}"
  printf '%s\n' "  local_v4         : ${WARP_LOCAL_V4:-172.16.0.2/32}"
  printf '%s\n' "  local_v6         : ${WARP_LOCAL_V6:-2606:4700:110:876d:4d3c:4206:c90c:6bd0/128}"
  printf '%s\n' "  client_id        : ${WARP_CLIENT_ID:-n/a}"
}

provider_warp_rebuild_runtime_from_account() {
  ensure_root
  local mode="${1:-auto}"
  local runtime_file
  runtime_file="$(provider_cfg_runtime_file)"
  if [[ ! -f "$runtime_file" ]]; then
    log_warn "$(msg "未发现 runtime.env，跳过运行时重建" "runtime.env not found, skip runtime rebuild")"
    return 0
  fi

  provider_cfg_load_runtime_exports
  if [[ "$mode" != "force" && "${WARP_MODE:-off}" == "off" ]]; then
    log_info "$(msg "运行时 WARP_MODE=off，跳过自动重建" "Runtime WARP_MODE=off, skip automatic rebuild")"
    return 0
  fi

  provider_warp_load_account
  provider_cfg_with_lock provider_cfg_rebuild_runtime "${protocols:-vless-reality}"
  log_success "$(msg "WARP 账户已应用到当前运行配置" "WARP account applied to current runtime config")"
}

provider_warp_account_set() {
  ensure_root
  local private_key="${1:-}" local_v6="${2:-}" reserved="${3:-}" local_v4="${4:-}" peer_public_key="${5:-}" client_id="${6:-}"
  local interactive="false"

  if [[ -z "$private_key" ]]; then
    interactive="true"
    provider_warp_account_load_optional
    prompt_with_default "$(msg "输入 WARP_PRIVATE_KEY" "Input WARP_PRIVATE_KEY")" "${WARP_PRIVATE_KEY:-}" private_key
    prompt_with_default "$(msg "输入 WARP_LOCAL_V6 (可含/128)" "Input WARP_LOCAL_V6 (with optional /128)")" "${WARP_LOCAL_V6:-2606:4700:110:876d:4d3c:4206:c90c:6bd0/128}" local_v6
    prompt_with_default "$(msg "输入 WARP_RESERVED [n,n,n]" "Input WARP_RESERVED [n,n,n]")" "${WARP_RESERVED:-[0,0,0]}" reserved
    prompt_with_default "$(msg "输入 WARP_LOCAL_V4 (可含/32)" "Input WARP_LOCAL_V4 (with optional /32)")" "${WARP_LOCAL_V4:-172.16.0.2/32}" local_v4
    prompt_with_default "$(msg "输入 WARP_PEER_PUBLIC_KEY" "Input WARP_PEER_PUBLIC_KEY")" "${WARP_PEER_PUBLIC_KEY:-bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=}" peer_public_key
    prompt_with_default "$(msg "输入 WARP_CLIENT_ID (可选)" "Input WARP_CLIENT_ID (optional)")" "${WARP_CLIENT_ID:-}" client_id
  else
    provider_warp_account_load_optional
    [[ -n "$local_v6" ]] || local_v6="${WARP_LOCAL_V6:-2606:4700:110:876d:4d3c:4206:c90c:6bd0/128}"
    [[ -n "$reserved" ]] || reserved="${WARP_RESERVED:-[0,0,0]}"
    [[ -n "$local_v4" ]] || local_v4="${WARP_LOCAL_V4:-172.16.0.2/32}"
    [[ -n "$peer_public_key" ]] || peer_public_key="${WARP_PEER_PUBLIC_KEY:-bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=}"
    [[ -n "$client_id" ]] || client_id="${WARP_CLIENT_ID:-}"
  fi

  [[ -n "$private_key" ]] || die "$(msg "WARP_PRIVATE_KEY 不能为空" "WARP_PRIVATE_KEY cannot be empty")"
  [[ -n "$peer_public_key" ]] || peer_public_key="bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="
  reserved="$(provider_warp_normalize_reserved "${reserved:-[0,0,0]}")"
  local_v4="$(provider_warp_normalize_local_v4 "${local_v4:-172.16.0.2/32}")"
  local_v6="$(provider_warp_normalize_local_v6 "${local_v6:-2606:4700:110:876d:4d3c:4206:c90c:6bd0/128}")"

  provider_warp_account_write "$private_key" "$peer_public_key" "$reserved" "$local_v4" "$local_v6" "$client_id"
  log_success "$(msg "WARP 账户参数已更新" "WARP account settings updated")"

  if [[ "$interactive" == "true" ]]; then
    if prompt_yes_no "$(msg "立即应用到当前运行配置吗？" "Apply to current runtime config now?")" "Y"; then
      provider_warp_rebuild_runtime_from_account "force"
    fi
  else
    log_info "$(msg "已写入账户文件。可执行 'warp config' 或 'warp mode <value>' 应用到运行时" "Account file updated. Run 'warp config' or 'warp mode <value>' to apply runtime changes")"
  fi
}

provider_warp_set_mode() {
  ensure_root
  local mode="${1:-}"
  [[ -n "$mode" ]] || die "Usage: warp mode <off|global|s|s4|s6|sx|xs|x|x4|x6|...>"
  WARP_MODE="$mode"
  validate_warp_mode_extended

  provider_cfg_load_runtime_exports
  WARP_MODE="$mode"
  if [[ "$mode" != "off" ]]; then
    provider_warp_load_account
  fi
  provider_cfg_with_lock provider_cfg_rebuild_runtime "${protocols:-vless-reality}"
  log_success "$(msg "WARP_MODE 已更新: ${mode}" "WARP_MODE updated: ${mode}")"
}

provider_warp_countries() {
  cat <<'EOF'
AT AU BE BG CA CH CZ DE DK EE ES FI FR GB HR HU IE IN IT JP LT LV NL NO PL PT RO RS SE SG SK US
EOF
}

provider_warp_region_set() {
  ensure_root
  local region="${1:-}"
  if [[ -z "$region" ]]; then
    printf '%s\n' "$(msg "可选国家地区代码（示例：US/JP/SG，auto 为自动）:" "Available region codes (e.g. US/JP/SG, auto for automatic):")"
    provider_warp_countries
    read -r -p "$(msg "输入地区代码" "Input region code"): " region
  fi
  [[ -n "$region" ]] || die "$(msg "未输入地区代码" "Region code is required")"
  provider_psiphon_set_region "$region"
  log_info "$(msg "说明：该地区设置映射到 Psiphon sidecar（用于 YG 的多地区交互近似体验）" "Note: this region setting maps to Psiphon sidecar (YG-style multi-region interaction approximation)")"
}

provider_warp_config() {
  ensure_root
  while true; do
    printf '\n'
    printf '%s\n' "========== WARP Config =========="
    echo "1) $(msg "查看当前 WARP 账户参数" "Show current WARP account settings")"
    echo "2) $(msg "自动生成/刷新 WARP 账户（warp register）" "Generate/refresh WARP account (warp register)")"
    echo "3) $(msg "手动修改 WARP 账户参数（私钥/IP/reserved）" "Edit WARP account settings (key/IP/reserved)")"
    echo "4) $(msg "设置 WARP_MODE（并重建运行时）" "Set WARP_MODE (and rebuild runtime)")"
    echo "5) $(msg "设置地区代码（映射 Psiphon）" "Set region code (maps to Psiphon)")"
    echo "6) $(msg "应用当前账户到运行时配置" "Apply current account to runtime config")"
    echo "7) $(msg "查看可选地区代码" "Show available region codes")"
    echo "0) $(msg "返回" "Back")"
    read -r -p "$(msg "请选择" "Select"): " c
    case "${c:-0}" in
      1) provider_warp_account_show ;;
      2) provider_warp_register ;;
      3) provider_warp_account_set ;;
      4)
        read -r -p "$(msg "输入 WARP_MODE" "Input WARP_MODE"): " wm
        provider_warp_set_mode "$wm"
        ;;
      5) provider_warp_region_set ;;
      6) provider_warp_rebuild_runtime_from_account "force" ;;
      7) provider_warp_countries ;;
      0) return 0 ;;
      *) log_warn "$(msg "无效选项" "Invalid option")" ;;
    esac
    read -r -p "$(msg "按回车继续..." "Press Enter to continue...")" _
  done
}

provider_warp_socks5_write_config() {
  local port="$1"
  provider_warp_load_account

  local client_ipv4 client_ipv6
  client_ipv4="${WARP_LOCAL_V4:-}"
  client_ipv6="${WARP_LOCAL_V6:-}"
  [[ "$client_ipv4" == */* ]] || [[ -z "$client_ipv4" ]] || client_ipv4="${client_ipv4}/32"
  [[ "$client_ipv6" == */* ]] || [[ -z "$client_ipv6" ]] || client_ipv6="${client_ipv6}/128"

  if [[ -f "${SBD_DATA_DIR}/warp-client-id" ]]; then
    local client_id
    client_id="$(tr -d '[:space:]' < "${SBD_DATA_DIR}/warp-client-id" 2>/dev/null || true)"
    if [[ -n "$client_id" ]]; then
      local hash
      hash="$(printf '%s' "$client_id" | sha256sum | cut -c1-4)"
      [[ -n "$client_ipv4" ]] || client_ipv4="172.16.$((0x${hash:0:2} % 256)).$((0x${hash:2:2} % 256))/32"
    fi
  elif [[ -n "${WARP_CLIENT_ID:-}" ]]; then
    local hash
    hash="$(printf '%s' "${WARP_CLIENT_ID}" | sha256sum | cut -c1-4)"
    [[ -n "$client_ipv4" ]] || client_ipv4="172.16.$((0x${hash:0:2} % 256)).$((0x${hash:2:2} % 256))/32"
  fi

  [[ -n "$client_ipv4" ]] || client_ipv4="172.16.0.2/32"
  [[ -n "$client_ipv6" ]] || client_ipv6="2606:4700:110:876d:4d3c:4206:c90c:6bd0/128"

  mkdir -p "${SBD_CONFIG_DIR}"
  cat > "$SBD_WARP_SOCKS_CONFIG_FILE" <<EOF
{
  "log": {"level": "warn"},
  "inbounds": [
    {"type":"socks","tag":"socks-in","listen":"127.0.0.1","listen_port":${port}}
  ],
  "outbounds": [
    {"type":"wireguard","tag":"warp-out","server":"engage.cloudflareclient.com","server_port":2408,"local_address":["${client_ipv4}","${client_ipv6}"],"private_key":"${WARP_PRIVATE_KEY}","peer_public_key":"${WARP_PEER_PUBLIC_KEY}","reserved":${WARP_RESERVED},"mtu":1280},
    {"type":"direct","tag":"direct"}
  ],
  "route": {"final":"warp-out"}
}
EOF
}

provider_warp_socks5_start() {
  ensure_root
  local port="${1:-}"
  if [[ -z "$port" && -f "$SBD_WARP_SOCKS_PORT_FILE" ]]; then
    port="$(cat "$SBD_WARP_SOCKS_PORT_FILE" 2>/dev/null || true)"
  fi
  port="${port:-40000}"
  [[ "$port" =~ ^[0-9]+$ ]] || die "$(msg "端口必须为数字" "port must be numeric")"
  (( port >= 1 && port <= 65535 )) || die "$(msg "端口超出范围(1-65535)" "port out of range (1-65535)")"
  [[ -x "${SBD_BIN_DIR}/sing-box" ]] || die "$(msg "未找到 sing-box 内核，请先安装或更新内核" "sing-box binary not found, install/update engine first")"
  if sbd_port_is_in_use tcp "$port"; then
    die "$(msg "端口已被占用: $port" "port already in use: $port")"
  fi

  provider_warp_socks5_write_config "$port"
  local check_out
  if ! check_out="$("${SBD_BIN_DIR}/sing-box" check -c "$SBD_WARP_SOCKS_CONFIG_FILE" 2>&1)"; then
    log_error "$check_out"
    die "$(msg "WARP Socks5 配置校验失败" "WARP Socks5 config validation failed")"
  fi

  local exec_cmd="${SBD_BIN_DIR}/sing-box run -c ${SBD_WARP_SOCKS_CONFIG_FILE}"

  detect_init_system
  if [[ "$SBD_INIT_SYSTEM" == "systemd" ]]; then
    cat > "$SBD_WARP_SOCKS_SERVICE_FILE" <<EOF
[Unit]
Description=sing-box-deve WARP SOCKS5
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${exec_cmd}
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
  fi

  sbd_service_enable_and_start "sing-box-deve-warp-socks5" "$exec_cmd"
  printf '%s\n' "$port" > "$SBD_WARP_SOCKS_PORT_FILE"
  log_success "$(msg "WARP Socks5 已启动: 127.0.0.1:${port}" "WARP Socks5 started: 127.0.0.1:${port}")"
}

provider_warp_socks5_stop() {
  ensure_root
  sbd_service_stop "sing-box-deve-warp-socks5"
  log_success "$(msg "WARP Socks5 已停止" "WARP Socks5 stopped")"
}

provider_warp_socks5_status() {
  local port="40000"
  [[ -f "$SBD_WARP_SOCKS_PORT_FILE" ]] && port="$(cat "$SBD_WARP_SOCKS_PORT_FILE" 2>/dev/null || echo 40000)"
  if sbd_service_is_active "sing-box-deve-warp-socks5"; then
    log_success "$(msg "WARP Socks5 状态: 运行中 (127.0.0.1:${port})" "WARP Socks5 status: running (127.0.0.1:${port})")"
  else
    log_warn "$(msg "WARP Socks5 状态: 未运行" "WARP Socks5 status: stopped")"
  fi
}

provider_warp_unlock_probe() {
  local url="$1" socks_port="$2"
  if [[ -n "$socks_port" ]]; then
    curl -sS -o /dev/null -m 10 --socks5-hostname "127.0.0.1:${socks_port}" -w "%{http_code}" "$url" 2>/dev/null || echo "000"
  else
    curl -sS -o /dev/null -m 10 -w "%{http_code}" "$url" 2>/dev/null || echo "000"
  fi
}

provider_warp_unlock_check() {
  local socks_port="" trace code_netflix code_openai loc
  if sbd_service_is_active "sing-box-deve-warp-socks5"; then
    socks_port="$(cat "$SBD_WARP_SOCKS_PORT_FILE" 2>/dev/null || true)"
  fi

  code_netflix="$(provider_warp_unlock_probe "https://www.netflix.com/" "$socks_port")"
  code_openai="$(provider_warp_unlock_probe "https://chat.openai.com/" "$socks_port")"

  if [[ -n "$socks_port" ]]; then
    trace="$(curl -sS -m 10 --socks5-hostname "127.0.0.1:${socks_port}" "https://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null || true)"
  else
    trace="$(curl -sS -m 10 "https://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null || true)"
  fi
  loc="$(printf '%s\n' "$trace" | awk -F= '/^loc=/{print $2}' | head -n1)"
  log_info "$(msg "出口地区: ${loc:-unknown}" "egress location: ${loc:-unknown}")"

  if [[ "$code_netflix" =~ ^(200|301|302)$ ]]; then
    log_success "$(msg "Netflix 连通性: 正常 (HTTP ${code_netflix})" "Netflix reachability: ok (HTTP ${code_netflix})")"
  elif [[ "$code_netflix" == "000" ]]; then
    log_warn "$(msg "Netflix 连通性: 失败 (HTTP 000)" "Netflix reachability: failed (HTTP 000)")"
  else
    log_warn "$(msg "Netflix 连通性: 受限或不确定 (HTTP ${code_netflix})" "Netflix reachability: limited/unknown (HTTP ${code_netflix})")"
  fi

  if [[ "$code_openai" =~ ^(200|301|302|403)$ ]]; then
    log_success "$(msg "ChatGPT 连通性: 可访问 (HTTP ${code_openai})" "ChatGPT reachability: reachable (HTTP ${code_openai})")"
  elif [[ "$code_openai" == "000" ]]; then
    log_warn "$(msg "ChatGPT 连通性: 失败 (HTTP 000)" "ChatGPT reachability: failed (HTTP 000)")"
  else
    log_warn "$(msg "ChatGPT 连通性: 受限或不确定 (HTTP ${code_openai})" "ChatGPT reachability: limited/unknown (HTTP ${code_openai})")"
  fi
}
