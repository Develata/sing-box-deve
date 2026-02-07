#!/usr/bin/env bash

generate_reality_keys() {
  local private_key_file="${SBD_DATA_DIR}/reality_private.key"
  local public_key_file="${SBD_DATA_DIR}/reality_public.key"
  local short_id_file="${SBD_DATA_DIR}/reality_short_id"

  if [[ -f "$private_key_file" && -f "$public_key_file" && -f "$short_id_file" ]]; then
    return 0
  fi

  local out
  out="$("${SBD_BIN_DIR}/sing-box" generate reality-keypair)"
  echo "$out" | awk -F': ' '/PrivateKey/{print $2}' > "$private_key_file"
  echo "$out" | awk -F': ' '/PublicKey/{print $2}' > "$public_key_file"
  openssl rand -hex 4 > "$short_id_file"
}

build_sing_box_config() {
  local protocols_csv="$1"
  local config_file="${SBD_CONFIG_DIR}/config.json"
  local uuid
  uuid="$(ensure_uuid)"
  ensure_self_signed_cert
  generate_reality_keys

  local private_key public_key short_id
  private_key="$(<"${SBD_DATA_DIR}/reality_private.key")"
  public_key="$(<"${SBD_DATA_DIR}/reality_public.key")"
  short_id="$(<"${SBD_DATA_DIR}/reality_short_id")"

  local inbounds=""
  inbounds+=$'    {\n'
  inbounds+=$'      "type": "vless",\n'
  inbounds+=$'      "tag": "vless-reality",\n'
  inbounds+=$'      "listen": "::",\n'
  inbounds+=$'      "listen_port": 443,\n'
  inbounds+=$'      "users": [{"uuid": "'"${uuid}"'", "flow": "xtls-rprx-vision"}],\n'
  inbounds+=$'      "tls": {\n'
  inbounds+=$'        "enabled": true,\n'
  inbounds+=$'        "server_name": "apple.com",\n'
  inbounds+=$'        "reality": {\n'
  inbounds+=$'          "enabled": true,\n'
  inbounds+=$'          "handshake": {"server": "apple.com", "server_port": 443},\n'
  inbounds+=$'          "private_key": "'"${private_key}"'",\n'
  inbounds+=$'          "short_id": ["'"${short_id}"'"]\n'
  inbounds+=$'        }\n'
  inbounds+=$'      }\n'
  inbounds+=$'    }'

  local protocols=()
  protocols_to_array "$protocols_csv" protocols

  local has_warp="false"
  if protocol_enabled "warp" "${protocols[@]}"; then
    if [[ "${WARP_MODE:-off}" == "global" ]]; then
      has_warp="true"
    else
      log_warn "Protocol 'warp' enabled but WARP_MODE is '${WARP_MODE:-off}', warp outbound disabled"
    fi
  fi

  if protocol_enabled "vmess-ws" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "type": "vmess",\n'
    inbounds+=$'      "tag": "vmess-ws",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+=$'      "listen_port": 8443,\n'
    inbounds+=$'      "users": [{"uuid": "'"${uuid}"'"}],\n'
    inbounds+=$'      "transport": {"type": "ws", "path": "/vmess"}\n'
    inbounds+=$'    }'
  fi

  if protocol_enabled "vless-ws" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "type": "vless",\n'
    inbounds+=$'      "tag": "vless-ws",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+=$'      "listen_port": 8444,\n'
    inbounds+=$'      "users": [{"uuid": "'"${uuid}"'"}],\n'
    inbounds+=$'      "transport": {"type": "ws", "path": "/vless"}\n'
    inbounds+=$'    }'
  fi

  if protocol_enabled "shadowsocks-2022" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "type": "shadowsocks",\n'
    inbounds+=$'      "tag": "ss-2022",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+=$'      "listen_port": 2443,\n'
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
    inbounds+=$'      "listen_port": 8443,\n'
    inbounds+=$'      "users": [{"password": "'"${uuid}"'"}],\n'
    inbounds+=$'      "tls": {\n'
    inbounds+=$'        "enabled": true,\n'
    inbounds+=$'        "server_name": "www.bing.com",\n'
    inbounds+=$'        "certificate_path": "'"${SBD_DATA_DIR}/cert.pem"'",\n'
    inbounds+=$'        "key_path": "'"${SBD_DATA_DIR}/private.key"'"\n'
    inbounds+=$'      }\n'
    inbounds+=$'    }'
  fi

  if protocol_enabled "tuic" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "type": "tuic",\n'
    inbounds+=$'      "tag": "tuic",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+=$'      "listen_port": 10443,\n'
    inbounds+=$'      "users": [{"uuid": "'"${uuid}"'", "password": "'"${uuid}"'"}],\n'
    inbounds+=$'      "congestion_control": "bbr",\n'
    inbounds+=$'      "tls": {\n'
    inbounds+=$'        "enabled": true,\n'
    inbounds+=$'        "server_name": "www.bing.com",\n'
    inbounds+=$'        "certificate_path": "'"${SBD_DATA_DIR}/cert.pem"'",\n'
    inbounds+=$'        "key_path": "'"${SBD_DATA_DIR}/private.key"'"\n'
    inbounds+=$'      }\n'
    inbounds+=$'    }'
  fi

  if protocol_enabled "trojan" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "type": "trojan",\n'
    inbounds+=$'      "tag": "trojan",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+=$'      "listen_port": 4433,\n'
    inbounds+=$'      "users": [{"password": "'"${uuid}"'"}],\n'
    inbounds+=$'      "tls": {\n'
    inbounds+=$'        "enabled": true,\n'
    inbounds+=$'        "server_name": "www.bing.com",\n'
    inbounds+=$'        "certificate_path": "'"${SBD_DATA_DIR}/cert.pem"'",\n'
    inbounds+=$'        "key_path": "'"${SBD_DATA_DIR}/private.key"'"\n'
    inbounds+=$'      }\n'
    inbounds+=$'    }'
  fi

  if protocol_enabled "anytls" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "type": "anytls",\n'
    inbounds+=$'      "tag": "anytls",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+=$'      "listen_port": 20443,\n'
    inbounds+=$'      "users": [{"password": "'"${uuid}"'"}],\n'
    inbounds+=$'      "padding_scheme": [],\n'
    inbounds+=$'      "tls": {\n'
    inbounds+=$'        "enabled": true,\n'
    inbounds+=$'        "certificate_path": "'"${SBD_DATA_DIR}/cert.pem"'",\n'
    inbounds+=$'        "key_path": "'"${SBD_DATA_DIR}/private.key"'"\n'
    inbounds+=$'      }\n'
    inbounds+=$'    }'
  fi

  if protocol_enabled "any-reality" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "type": "anytls",\n'
    inbounds+=$'      "tag": "any-reality",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+=$'      "listen_port": 30443,\n'
    inbounds+=$'      "users": [{"password": "'"${uuid}"'"}],\n'
    inbounds+=$'      "padding_scheme": [],\n'
    inbounds+=$'      "tls": {\n'
    inbounds+=$'        "enabled": true,\n'
    inbounds+=$'        "server_name": "apple.com",\n'
    inbounds+=$'        "reality": {\n'
    inbounds+=$'          "enabled": true,\n'
    inbounds+=$'          "handshake": {"server": "apple.com", "server_port": 443},\n'
    inbounds+=$'          "private_key": "'"${private_key}"'",\n'
    inbounds+=$'          "short_id": ["'"${short_id}"'"]\n'
    inbounds+=$'        }\n'
    inbounds+=$'      }\n'
    inbounds+=$'    }'
  fi

  if protocol_enabled "wireguard" "${protocols[@]}"; then
    local wg_private wg_public
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
    inbounds+=$'      "listen_port": 51820,\n'
    inbounds+=$'      "address": ["10.66.66.1/24"],\n'
    inbounds+=$'      "private_key": "'"${wg_private}"'",\n'
    inbounds+=$'      "peers": []\n'
    inbounds+=$'    }'
  fi

  local outbounds
  local final_tag="direct"
  outbounds=$'    {"type": "direct", "tag": "direct"},\n'
  outbounds+=$'    {"type": "block", "tag": "block"}'

  local upstream_mode
  upstream_mode="${OUTBOUND_PROXY_MODE:-direct}"
  if [[ "$upstream_mode" != "direct" ]]; then
    outbounds+=$',\n'
    outbounds+="$(build_upstream_outbound_singbox)"
    final_tag="proxy-out"
  fi

  if [[ "$has_warp" == "true" ]]; then
    outbounds+=$',\n'
    outbounds+="$(build_warp_outbound_singbox)"
    if [[ "${WARP_MODE:-off}" == "global" && "$upstream_mode" == "direct" ]]; then
      final_tag="warp-out"
    fi
  fi

  cat > "$config_file" <<EOF
{
  "log": {"level": "info"},
  "inbounds": [
${inbounds}
  ],
  "outbounds": [
${outbounds}
  ],
  "route": {
    "final": "${final_tag}"
  }
}
EOF

  echo "$public_key" > "${SBD_DATA_DIR}/reality_public.key"
}
