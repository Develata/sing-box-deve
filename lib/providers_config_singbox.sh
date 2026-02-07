#!/usr/bin/env bash
build_sing_box_config() {
  local protocols_csv="$1"
  local config_file="${SBD_CONFIG_DIR}/config.json"
  local uuid
  uuid="$(ensure_uuid)"
  local cert_file key_file
  cert_file="$(get_tls_cert_path)"
  key_file="$(get_tls_key_path)"
  generate_reality_keys
  local private_key public_key short_id
  private_key="$(<"${SBD_DATA_DIR}/reality_private.key")"
  public_key="$(<"${SBD_DATA_DIR}/reality_public.key")"
  short_id="$(<"${SBD_DATA_DIR}/reality_short_id")"

  local reality_server_name reality_port tls_server_name ws_path_vmess ws_path_vless
  reality_server_name="$(sbd_reality_server_name)"
  reality_port="$(sbd_reality_handshake_port)"
  tls_server_name="$(sbd_tls_server_name)"
  ws_path_vmess="$(sbd_vmess_ws_path)"
  ws_path_vless="$(sbd_vless_ws_path)"

  local port_vless_reality port_vmess_ws port_vless_ws port_ss2022 port_hysteria2
  local port_tuic port_trojan port_anytls port_anyreality port_wireguard
  port_vless_reality="$(resolve_protocol_port_for_engine "sing-box" "vless-reality")"
  port_vmess_ws="$(resolve_protocol_port_for_engine "sing-box" "vmess-ws")"
  port_vless_ws="$(resolve_protocol_port_for_engine "sing-box" "vless-ws")"
  port_ss2022="$(resolve_protocol_port_for_engine "sing-box" "shadowsocks-2022")"
  port_hysteria2="$(resolve_protocol_port_for_engine "sing-box" "hysteria2")"
  port_tuic="$(resolve_protocol_port_for_engine "sing-box" "tuic")"
  port_trojan="$(resolve_protocol_port_for_engine "sing-box" "trojan")"
  port_anytls="$(resolve_protocol_port_for_engine "sing-box" "anytls")"
  port_anyreality="$(resolve_protocol_port_for_engine "sing-box" "any-reality")"
  port_wireguard="$(resolve_protocol_port_for_engine "sing-box" "wireguard")"

  local inbounds=""
  inbounds+=$'    {\n'
  inbounds+=$'      "type": "vless",\n'
  inbounds+=$'      "tag": "vless-reality",\n'
  inbounds+=$'      "listen": "::",\n'
  inbounds+="      \"listen_port\": ${port_vless_reality},\n"
  inbounds+=$'      "users": [{"uuid": "'"${uuid}"'", "flow": "xtls-rprx-vision"}],\n'
  inbounds+=$'      "tls": {\n'
  inbounds+=$'        "enabled": true,\n'
  inbounds+=$'        "server_name": "'"${reality_server_name}"'",\n'
  inbounds+=$'        "reality": {\n'
  inbounds+=$'          "enabled": true,\n'
  inbounds+=$'          "handshake": {"server": "'"${reality_server_name}"'", "server_port": '"${reality_port}"'},\n'
  inbounds+=$'          "private_key": "'"${private_key}"'",\n'
  inbounds+=$'          "short_id": ["'"${short_id}"'"]\n'
  inbounds+=$'        }\n'
  inbounds+=$'      }\n'
  inbounds+=$'    }'

  local protocols=()
  protocols_to_array "$protocols_csv" protocols

  local has_warp="false"
  if protocol_enabled "warp" "${protocols[@]}"; then
    if warp_mode_targets_singbox "${WARP_MODE:-off}"; then
      has_warp="true"
    else
      log_warn "Protocol 'warp' enabled but WARP_MODE='${WARP_MODE:-off}' targets non-sing-box path"
    fi
  fi

  if protocol_enabled "vmess-ws" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "type": "vmess",\n'
    inbounds+=$'      "tag": "vmess-ws",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+="      \"listen_port\": ${port_vmess_ws},\n"
    inbounds+=$'      "users": [{"uuid": "'"${uuid}"'"}],\n'
    inbounds+=$'      "transport": {"type": "ws", "path": "'"${ws_path_vmess}"'"}\n'
    inbounds+=$'    }'
  fi

  if protocol_enabled "vless-ws" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "type": "vless",\n'
    inbounds+=$'      "tag": "vless-ws",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+="      \"listen_port\": ${port_vless_ws},\n"
    inbounds+=$'      "users": [{"uuid": "'"${uuid}"'"}],\n'
    inbounds+=$'      "transport": {"type": "ws", "path": "'"${ws_path_vless}"'"}\n'
    inbounds+=$'    }'
  fi

  if protocol_enabled "shadowsocks-2022" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "type": "shadowsocks",\n'
    inbounds+=$'      "tag": "ss-2022",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+="      \"listen_port\": ${port_ss2022},\n"
    inbounds+=$'      "method": "2022-blake3-aes-128-gcm",\n'
    inbounds+=$'      "password": "'"${uuid}"'"\n'
    inbounds+=$'    }'
  fi

  if protocol_enabled "hysteria2" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "type": "hysteria2",\n'
    inbounds+=$'      "tag": "hy2",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+="      \"listen_port\": ${port_hysteria2},\n"
    inbounds+=$'      "users": [{"password": "'"${uuid}"'"}],\n'
    inbounds+=$'      "tls": {\n'
    inbounds+=$'        "enabled": true,\n'
    inbounds+=$'        "server_name": "'"${tls_server_name}"'",\n'
    inbounds+=$'        "certificate_path": "'"${cert_file}"'",\n'
    inbounds+=$'        "key_path": "'"${key_file}"'"\n'
    inbounds+=$'      }\n'
    inbounds+=$'    }'
  fi

  if protocol_enabled "tuic" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "type": "tuic",\n'
    inbounds+=$'      "tag": "tuic",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+="      \"listen_port\": ${port_tuic},\n"
    inbounds+=$'      "users": [{"uuid": "'"${uuid}"'", "password": "'"${uuid}"'"}],\n'
    inbounds+=$'      "congestion_control": "bbr",\n'
    inbounds+=$'      "tls": {\n'
    inbounds+=$'        "enabled": true,\n'
    inbounds+=$'        "server_name": "'"${tls_server_name}"'",\n'
    inbounds+=$'        "certificate_path": "'"${cert_file}"'",\n'
    inbounds+=$'        "key_path": "'"${key_file}"'"\n'
    inbounds+=$'      }\n'
    inbounds+=$'    }'
  fi

  if protocol_enabled "trojan" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "type": "trojan",\n'
    inbounds+=$'      "tag": "trojan",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+="      \"listen_port\": ${port_trojan},\n"
    inbounds+=$'      "users": [{"password": "'"${uuid}"'"}],\n'
    inbounds+=$'      "tls": {\n'
    inbounds+=$'        "enabled": true,\n'
    inbounds+=$'        "server_name": "'"${tls_server_name}"'",\n'
    inbounds+=$'        "certificate_path": "'"${cert_file}"'",\n'
    inbounds+=$'        "key_path": "'"${key_file}"'"\n'
    inbounds+=$'      }\n'
    inbounds+=$'    }'
  fi

  if protocol_enabled "anytls" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "type": "anytls",\n'
    inbounds+=$'      "tag": "anytls",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+="      \"listen_port\": ${port_anytls},\n"
    inbounds+=$'      "users": [{"password": "'"${uuid}"'"}],\n'
    inbounds+=$'      "padding_scheme": [],\n'
    inbounds+=$'      "tls": {\n'
    inbounds+=$'        "enabled": true,\n'
    inbounds+=$'        "certificate_path": "'"${cert_file}"'",\n'
    inbounds+=$'        "key_path": "'"${key_file}"'"\n'
    inbounds+=$'      }\n'
    inbounds+=$'    }'
  fi

  if protocol_enabled "any-reality" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "type": "anytls",\n'
    inbounds+=$'      "tag": "any-reality",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+="      \"listen_port\": ${port_anyreality},\n"
    inbounds+=$'      "users": [{"password": "'"${uuid}"'"}],\n'
    inbounds+=$'      "padding_scheme": [],\n'
    inbounds+=$'      "tls": {\n'
    inbounds+=$'        "enabled": true,\n'
    inbounds+=$'        "server_name": "'"${reality_server_name}"'",\n'
    inbounds+=$'        "reality": {\n'
    inbounds+=$'          "enabled": true,\n'
    inbounds+=$'          "handshake": {"server": "'"${reality_server_name}"'", "server_port": '"${reality_port}"'},\n'
    inbounds+=$'          "private_key": "'"${private_key}"'",\n'
    inbounds+=$'          "short_id": ["'"${short_id}"'"]\n'
    inbounds+=$'        }\n'
    inbounds+=$'      }\n'
    inbounds+=$'    }'
  fi

  if protocol_enabled "wireguard" "${protocols[@]}"; then
    local wg_private wg_public
    command -v wg >/dev/null 2>&1 || die "wireguard protocol requires 'wg' command (install wireguard-tools)"
    if [[ ! -f "${SBD_DATA_DIR}/wg_private.key" ]]; then
      wg_private="$(wg genkey)"
      wg_public="$(printf '%s' "$wg_private" | wg pubkey)"
      echo "$wg_private" > "${SBD_DATA_DIR}/wg_private.key"
      echo "$wg_public" > "${SBD_DATA_DIR}/wg_public.key"
    fi
    wg_private="$(<"${SBD_DATA_DIR}/wg_private.key")"
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "type": "wireguard",\n'
    inbounds+=$'      "tag": "wireguard",\n'
    inbounds+="      \"listen_port\": ${port_wireguard},\n"
    inbounds+=$'      "address": ["10.66.66.1/24"],\n'
    inbounds+=$'      "private_key": "'"${wg_private}"'",\n'
    inbounds+=$'      "peers": []\n'
    inbounds+=$'    }'
  fi

  local outbounds final_tag upstream_mode
  final_tag="direct"
  outbounds=$'    {"type": "direct", "tag": "direct"},\n'
  outbounds+=$'    {"type": "block", "tag": "block"}'
  upstream_mode="${OUTBOUND_PROXY_MODE:-direct}"
  if [[ "$upstream_mode" != "direct" ]]; then
    outbounds+=$',\n'
    outbounds+="$(build_upstream_outbound_singbox)"
    final_tag="proxy-out"
  fi
  if [[ "$has_warp" == "true" ]]; then
    outbounds+=$',\n'
    outbounds+="$(build_warp_outbound_singbox)"
    [[ "$upstream_mode" == "direct" ]] && final_tag="warp-out"
  fi

  inbounds="${inbounds//\\n/$'\n'}"
  outbounds="${outbounds//\\n/$'\n'}"
  local route_json
  route_json="$(build_singbox_route_json "$final_tag")"

  cat > "$config_file" <<EOF_JSON
{
  "log": {"level": "info"},
  "inbounds": [
${inbounds}
  ],
  "outbounds": [
${outbounds}
  ],
  "route": ${route_json}
}
EOF_JSON

  echo "$public_key" > "${SBD_DATA_DIR}/reality_public.key"
}
