#!/usr/bin/env bash

build_xray_config() {
  local protocols_csv="$1"
  local config_file="${SBD_CONFIG_DIR}/xray-config.json"
  local uuid
  uuid="$(ensure_uuid)"
  local reality_server_name reality_port ws_path_vmess ws_path_vless xhttp_path xhttp_mode vless_decryption
  reality_server_name="$(sbd_reality_server_name)"
  reality_port="$(sbd_reality_handshake_port)"
  ws_path_vmess="$(sbd_vmess_ws_path)"
  ws_path_vless="$(sbd_vless_ws_path)"
  xhttp_path="$(sbd_vless_xhttp_path "$uuid")"
  xhttp_mode="$(sbd_vless_xhttp_mode)"
  vless_decryption="none"
  if sbd_xray_vless_enc_enabled; then
    ensure_xray_vless_enc_keys
    vless_decryption="$(sbd_xray_vless_decryption_key)"
    [[ -n "$vless_decryption" ]] || die "XRAY_VLESS_ENC=true but decryption key is empty"
  fi

  local port_vless_reality port_vmess_ws port_vless_ws port_vless_xhttp port_trojan port_socks5
  port_vless_reality="$(resolve_protocol_port_for_engine "xray" "vless-reality")"
  port_vmess_ws="$(resolve_protocol_port_for_engine "xray" "vmess-ws")"
  port_vless_ws="$(resolve_protocol_port_for_engine "xray" "vless-ws")"
  port_vless_xhttp="$(resolve_protocol_port_for_engine "xray" "vless-xhttp")"
  port_trojan="$(resolve_protocol_port_for_engine "xray" "trojan")"
  port_socks5="$(resolve_protocol_port_for_engine "xray" "socks5")"

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
  local inbound_map=""
  inbounds+=$'    {\n'
  inbounds+=$'      "tag": "vless-reality",\n'
  inbounds+=$'      "listen": "::",\n'
  inbounds+="      \"port\": ${port_vless_reality},\n"
  inbounds+=$'      "protocol": "vless",\n'
  inbounds+=$'      "settings": {"clients": [{"id": "'"${uuid}"'", "flow": "xtls-rprx-vision"}], "decryption": "none"},\n'
  inbounds+=$'      "streamSettings": {"network": "tcp", "security": "reality", "realitySettings": {"show": false, "dest": "'"${reality_server_name}:${reality_port}"'", "xver": 0, "serverNames": ["'"${reality_server_name}"'"], "privateKey": "'"${private_key}"'", "shortIds": ["'"${short_id}"'"]}}\n'
  inbounds+=$'    }'
  inbound_map="vless-reality:${port_vless_reality}"

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
    inbounds+=$'      "streamSettings": {"network": "ws", "wsSettings": {"path": "'"${ws_path_vmess}"'"}}\n'
    inbounds+=$'    }'
    inbound_map+=",vmess-ws:${port_vmess_ws}"
  fi

  if protocol_enabled "vless-ws" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "tag": "vless-ws",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+="      \"port\": ${port_vless_ws},\n"
    inbounds+=$'      "protocol": "vless",\n'
    inbounds+=$'      "settings": {"clients": [{"id": "'"${uuid}"'"}], "decryption": "'"${vless_decryption}"'"},\n'
    inbounds+=$'      "streamSettings": {"network": "ws", "wsSettings": {"path": "'"${ws_path_vless}"'"}}\n'
    inbounds+=$'    }'
    inbound_map+=",vless-ws:${port_vless_ws}"
  fi

  if protocol_enabled "vless-xhttp" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "tag": "vless-xhttp",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+="      \"port\": ${port_vless_xhttp},\n"
    inbounds+=$'      "protocol": "vless",\n'
    inbounds+=$'      "settings": {"clients": [{"id": "'"${uuid}"'", "flow": "xtls-rprx-vision"}], "decryption": "'"${vless_decryption}"'"},\n'
    if sbd_xhttp_use_reality; then
      inbounds+=$'      "streamSettings": {"network": "xhttp", "security": "reality", "realitySettings": {"show": false, "dest": "'"${reality_server_name}:${reality_port}"'", "xver": 0, "serverNames": ["'"${reality_server_name}"'"], "privateKey": "'"${private_key}"'", "shortIds": ["'"${short_id}"'"]}, "xhttpSettings": {"path": "'"${xhttp_path}"'", "mode": "'"${xhttp_mode}"'"}}\n'
    else
      inbounds+=$'      "streamSettings": {"network": "xhttp", "xhttpSettings": {"path": "'"${xhttp_path}"'", "mode": "'"${xhttp_mode}"'"}}\n'
    fi
    inbounds+=$'    }'
    inbound_map+=",vless-xhttp:${port_vless_xhttp}"
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
    inbound_map+=",trojan:${port_trojan}"
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
    inbound_map+=",socks5:${port_socks5}"
  fi

  local xray_outbounds xray_routing primary_tag available_outbounds
  primary_tag="direct"
  available_outbounds="direct"
  xray_outbounds=$'    {"protocol": "freedom", "tag": "direct"},\n'
  xray_outbounds+=$'    {"protocol": "blackhole", "tag": "block"}'
  xray_routing=""
  if [[ "$has_warp" == "true" ]]; then
    xray_outbounds+=$',\n'
    xray_outbounds+="$(build_warp_outbound_xray)"
    primary_tag="warp-out"
    available_outbounds+=",warp-out"
  fi
  if [[ "${OUTBOUND_PROXY_MODE:-direct}" != "direct" ]]; then
    xray_outbounds+=$',\n'
    xray_outbounds+="$(build_upstream_outbound_xray)"
    primary_tag="proxy-out"
    available_outbounds+=",proxy-out"
  fi
  xray_routing="$(build_xray_routing_fragment "$primary_tag" "$inbound_map" "$available_outbounds")"

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
