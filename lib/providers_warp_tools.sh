#!/usr/bin/env bash

SBD_WARP_SOCKS_CONFIG_FILE="/etc/sing-box-deve/warp-socks5.json"
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
  [[ -n "$WARP_PRIVATE_KEY" ]] || die "$(msg "WARP_PRIVATE_KEY 为空，请重新执行 warp register" "WARP_PRIVATE_KEY is empty, run warp register again")"
}

provider_warp_socks5_write_config() {
  local port="$1"
  provider_warp_load_account

  local client_ipv4 client_ipv6
  if [[ -f "${SBD_DATA_DIR}/warp-client-id" ]]; then
    local client_id
    client_id="$(tr -d '[:space:]' < "${SBD_DATA_DIR}/warp-client-id" 2>/dev/null || true)"
    if [[ -n "$client_id" ]]; then
      local hash
      hash="$(printf '%s' "$client_id" | sha256sum | cut -c1-4)"
      client_ipv4="172.16.$((0x${hash:0:2} % 256)).$((0x${hash:2:2} % 256))/32"
    fi
  fi
  [[ -n "$client_ipv4" ]] || client_ipv4="172.16.0.2/32"
  client_ipv6="${WARP_CLIENT_IPV6:-fd01:5ca1:ab1e::2/128}"

  mkdir -p /etc/sing-box-deve
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

  cat > "$SBD_WARP_SOCKS_SERVICE_FILE" <<EOF
[Unit]
Description=sing-box-deve WARP SOCKS5
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${SBD_BIN_DIR}/sing-box run -c ${SBD_WARP_SOCKS_CONFIG_FILE}
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now sing-box-deve-warp-socks5.service >/dev/null
  printf '%s\n' "$port" > "$SBD_WARP_SOCKS_PORT_FILE"
  log_success "$(msg "WARP Socks5 已启动: 127.0.0.1:${port}" "WARP Socks5 started: 127.0.0.1:${port}")"
}

provider_warp_socks5_stop() {
  ensure_root
  systemctl disable --now sing-box-deve-warp-socks5.service >/dev/null 2>&1 || true
  log_success "$(msg "WARP Socks5 已停止" "WARP Socks5 stopped")"
}

provider_warp_socks5_status() {
  local port="40000"
  [[ -f "$SBD_WARP_SOCKS_PORT_FILE" ]] && port="$(cat "$SBD_WARP_SOCKS_PORT_FILE" 2>/dev/null || echo 40000)"
  if systemctl is-active --quiet sing-box-deve-warp-socks5.service; then
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
  if systemctl is-active --quiet sing-box-deve-warp-socks5.service; then
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
