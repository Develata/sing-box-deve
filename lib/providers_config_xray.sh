#!/usr/bin/env bash

build_xray_config() {
  local protocols_csv="$1"
  local config_file="${SBD_CONFIG_DIR}/xray-config.json"
  local uuid
  uuid="$(ensure_uuid)"

  local port_vless_reality port_vmess_ws port_vless_ws port_vless_xhttp port_trojan port_socks5
  port_vless_reality="$(get_protocol_port "vless-reality")"
  port_vmess_ws="$(get_protocol_port "vmess-ws")"
  port_vless_ws="$(get_protocol_port "vless-ws")"
  port_vless_xhttp="$(get_protocol_port "vless-xhttp")"
  port_trojan="$(get_protocol_port "trojan")"
  port_socks5="$(get_protocol_port "socks5")"

  if [[ ! -f "${SBD_DATA_DIR}/xray_private.key" ]]; then
    local out
    out="$("${SBD_BIN_DIR}/xray" x25519)"
    echo "$out" | awk '/Private key/{print $3}' > "${SBD_DATA_DIR}/xray_private.key"
    echo "$out" | awk '/Public key/{print $3}' > "${SBD_DATA_DIR}/xray_public.key"
    openssl rand -hex 4 > "${SBD_DATA_DIR}/xray_short_id"
  fi

  local private_key public_key short_id
  local cert_file key_file
  cert_file="$(get_tls_cert_path)"
  key_file="$(get_tls_key_path)"
  private_key="$(<"${SBD_DATA_DIR}/xray_private.key")"
  public_key="$(<"${SBD_DATA_DIR}/xray_public.key")"
  short_id="$(<"${SBD_DATA_DIR}/xray_short_id")"

  local inbounds=""
  inbounds+=$'    {\n'
  inbounds+=$'      "tag": "vless-reality",\n'
  inbounds+=$'      "listen": "::",\n'
  inbounds+="      \"port\": ${port_vless_reality},\n"
  inbounds+=$'      "protocol": "vless",\n'
  inbounds+=$'      "settings": {"clients": [{"id": "'"${uuid}"'", "flow": "xtls-rprx-vision"}], "decryption": "none"},\n'
  inbounds+=$'      "streamSettings": {"network": "tcp", "security": "reality", "realitySettings": {"show": false, "dest": "apple.com:443", "xver": 0, "serverNames": ["apple.com"], "privateKey": "'"${private_key}"'", "shortIds": ["'"${short_id}"'"]}}\n'
  inbounds+=$'    }'

  local protocols=()
  protocols_to_array "$protocols_csv" protocols
  local has_warp="false"
  if protocol_enabled "warp" "${protocols[@]}"; then
    if warp_mode_targets_xray "${WARP_MODE:-off}"; then
      has_warp="true"
    else
      log_warn "Protocol 'warp' enabled but WARP_MODE='${WARP_MODE:-off}' targets non-xray path"
    fi
  fi

  if protocol_enabled "vmess-ws" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "tag": "vmess-ws",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+="      \"port\": ${port_vmess_ws},\n"
    inbounds+=$'      "protocol": "vmess",\n'
    inbounds+=$'      "settings": {"clients": [{"id": "'"${uuid}"'"}]},\n'
    inbounds+=$'      "streamSettings": {"network": "ws", "wsSettings": {"path": "/vmess"}}\n'
    inbounds+=$'    }'
  fi

  if protocol_enabled "vless-ws" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "tag": "vless-ws",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+="      \"port\": ${port_vless_ws},\n"
    inbounds+=$'      "protocol": "vless",\n'
    inbounds+=$'      "settings": {"clients": [{"id": "'"${uuid}"'"}], "decryption": "none"},\n'
    inbounds+=$'      "streamSettings": {"network": "ws", "wsSettings": {"path": "/vless"}}\n'
    inbounds+=$'    }'
  fi

  if protocol_enabled "vless-xhttp" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "tag": "vless-xhttp",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+="      \"port\": ${port_vless_xhttp},\n"
    inbounds+=$'      "protocol": "vless",\n'
    inbounds+=$'      "settings": {"clients": [{"id": "'"${uuid}"'", "flow": "xtls-rprx-vision"}], "decryption": "none"},\n'
    if [[ "${SBD_XHTTP_REALITY_ENC:-false}" == "true" ]]; then
      inbounds+=$'      "streamSettings": {"network": "xhttp", "security": "reality", "realitySettings": {"show": false, "dest": "apple.com:443", "xver": 0, "serverNames": ["apple.com"], "privateKey": "'"${private_key}"'", "shortIds": ["'"${short_id}"'"]}, "xhttpSettings": {"path": "/'"${uuid}"'-xh", "mode": "auto"}}\n'
    else
      inbounds+=$'      "streamSettings": {"network": "xhttp", "xhttpSettings": {"path": "/'"${uuid}"'-xh", "mode": "auto"}}\n'
    fi
    inbounds+=$'    }'
  fi

  if protocol_enabled "trojan" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "tag": "trojan",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+="      \"port\": ${port_trojan},\n"
    inbounds+=$'      "protocol": "trojan",\n'
    inbounds+=$'      "settings": {"clients": [{"password": "'"${uuid}"'"}]},\n'
    inbounds+=$'      "streamSettings": {"security": "tls", "tlsSettings": {"certificates": [{"certificateFile": "'"${cert_file}"'", "keyFile": "'"${key_file}"'"}]}}\n'
    inbounds+=$'    }'
  fi

  if protocol_enabled "socks5" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "tag": "socks5",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+="      \"port\": ${port_socks5},\n"
    inbounds+=$'      "protocol": "socks",\n'
    inbounds+=$'      "settings": {"auth": "password", "accounts": [{"user": "'"${uuid}"'", "pass": "'"${uuid}"'"}], "udp": true}\n'
    inbounds+=$'    }'
  fi

  local xray_outbounds xray_routing primary_tag
  primary_tag="direct"
  xray_outbounds=$'    {"protocol": "freedom", "tag": "direct"},\n'
  xray_outbounds+=$'    {"protocol": "blackhole", "tag": "block"}'
  xray_routing=""
  if [[ "$has_warp" == "true" ]]; then
    xray_outbounds+=$',\n'
    xray_outbounds+="$(build_warp_outbound_xray)"
    primary_tag="warp-out"
  fi
  if [[ "${OUTBOUND_PROXY_MODE:-direct}" != "direct" ]]; then
    xray_outbounds+=$',\n'
    xray_outbounds+="$(build_upstream_outbound_xray)"
    primary_tag="proxy-out"
  fi
  xray_routing="$(build_xray_routing_fragment "$primary_tag")"

  inbounds="${inbounds//\\n/$'\n'}"
  xray_outbounds="${xray_outbounds//\\n/$'\n'}"
  xray_routing="${xray_routing//\\n/$'\n'}"

  cat > "$config_file" <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [
${inbounds}
  ],
  "outbounds": [
${xray_outbounds}
  ]${xray_routing}
}
EOF

  echo "$public_key" > "${SBD_DATA_DIR}/xray_public.key"
}

write_systemd_service() {
  local engine="$1"
  local config_path
  local binary_path
  local exec_args
  case "$engine" in
    sing-box)
      config_path="${SBD_CONFIG_DIR}/config.json"
      binary_path="${SBD_BIN_DIR}/sing-box"
      exec_args="run -c ${config_path}"
      ;;
    xray)
      config_path="${SBD_CONFIG_DIR}/xray-config.json"
      binary_path="${SBD_BIN_DIR}/xray"
      exec_args="run -config ${config_path}"
      ;;
    *) die "Unsupported engine for service: $engine" ;;
  esac

  cat > "$SBD_SERVICE_FILE" <<EOF
[Unit]
Description=sing-box-deve core service
After=network.target

[Service]
Type=simple
ExecStart=${binary_path} ${exec_args}
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  systemd_reload_and_enable
  safe_service_restart
}
