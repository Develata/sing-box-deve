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
  local inbound_map=""
  sbd_inbounds_append inbounds inbound_map "vless-reality" "$port_vless_reality" \
    "$(singbox_fragment_vless_reality "$uuid" "$port_vless_reality" "$reality_server_name" "$reality_port" "$private_key" "$short_id")"
  local protocols=()
  protocols_to_array "$protocols_csv" protocols

  local has_warp="false"
  if protocol_enabled "warp" "${protocols[@]}"; then
    if warp_mode_targets_singbox "${WARP_MODE:-off}"; then
      has_warp="true"
    else
      log_warn "$(msg "已启用 warp 协议，但当前 WARP_MODE='${WARP_MODE:-off}' 不指向 sing-box 路径" "Protocol 'warp' enabled but WARP_MODE='${WARP_MODE:-off}' targets non-sing-box path")"
    fi
  fi

  if protocol_enabled "vmess-ws" "${protocols[@]}"; then
    sbd_inbounds_append inbounds inbound_map "vmess-ws" "$port_vmess_ws" \
      "$(singbox_fragment_vmess_ws "$uuid" "$port_vmess_ws" "$ws_path_vmess")"
  fi

  if protocol_enabled "vless-ws" "${protocols[@]}"; then
    sbd_inbounds_append inbounds inbound_map "vless-ws" "$port_vless_ws" \
      "$(singbox_fragment_vless_ws "$uuid" "$port_vless_ws" "$ws_path_vless")"
  fi

  if protocol_enabled "shadowsocks-2022" "${protocols[@]}"; then
    sbd_inbounds_append inbounds inbound_map "ss-2022" "$port_ss2022" \
      "$(singbox_fragment_ss2022 "$uuid" "$port_ss2022")"
  fi

  if protocol_enabled "hysteria2" "${protocols[@]}"; then
    sbd_inbounds_append inbounds inbound_map "hy2" "$port_hysteria2" \
      "$(singbox_fragment_hysteria2 "$uuid" "$port_hysteria2" "$tls_server_name" "$cert_file" "$key_file")"
  fi

  if protocol_enabled "tuic" "${protocols[@]}"; then
    sbd_inbounds_append inbounds inbound_map "tuic" "$port_tuic" \
      "$(singbox_fragment_tuic "$uuid" "$port_tuic" "$tls_server_name" "$cert_file" "$key_file")"
  fi

  if protocol_enabled "trojan" "${protocols[@]}"; then
    sbd_inbounds_append inbounds inbound_map "trojan" "$port_trojan" \
      "$(singbox_fragment_trojan "$uuid" "$port_trojan" "$tls_server_name" "$cert_file" "$key_file")"
  fi

  if protocol_enabled "anytls" "${protocols[@]}"; then
    sbd_inbounds_append inbounds inbound_map "anytls" "$port_anytls" \
      "$(singbox_fragment_anytls "$uuid" "$port_anytls" "$cert_file" "$key_file")"
  fi

  if protocol_enabled "any-reality" "${protocols[@]}"; then
    sbd_inbounds_append inbounds inbound_map "any-reality" "$port_anyreality" \
      "$(singbox_fragment_any_reality "$uuid" "$port_anyreality" "$reality_server_name" "$reality_port" "$private_key" "$short_id")"
  fi

  if protocol_enabled "wireguard" "${protocols[@]}"; then
    local wg_private wg_public
    command -v wg >/dev/null 2>&1 || die "wireguard protocol requires 'wg' command (install wireguard-tools)"
    if [[ ! -f "${SBD_DATA_DIR}/wg_private.key" ]]; then
      wg_private="$(wg genkey)"
      wg_public="$(printf '%s' "$wg_private" | wg pubkey)"
      echo "$wg_private" > "${SBD_DATA_DIR}/wg_private.key"
      echo "$wg_public" > "${SBD_DATA_DIR}/wg_public.key"
      chmod 600 "${SBD_DATA_DIR}/wg_private.key" "${SBD_DATA_DIR}/wg_public.key"
    fi
    wg_private="$(<"${SBD_DATA_DIR}/wg_private.key")"
    sbd_inbounds_append inbounds inbound_map "wireguard" "$port_wireguard" \
      "$(singbox_fragment_wireguard "$port_wireguard" "$wg_private")"
  fi

  local outbounds final_tag upstream_mode available_outbounds
  final_tag="direct"
  available_outbounds="direct"
  outbounds=$'    {"type": "direct", "tag": "direct"},\n'
  outbounds+=$'    {"type": "block", "tag": "block"}'
  upstream_mode="${OUTBOUND_PROXY_MODE:-direct}"
  if [[ "$upstream_mode" != "direct" ]]; then
    outbounds+=$',\n'
    outbounds+="$(build_upstream_outbound_singbox)"
    final_tag="proxy-out"
    available_outbounds+=",proxy-out"
  fi
  if [[ "$has_warp" == "true" ]]; then
    outbounds+=$',\n'
    outbounds+="$(build_warp_outbound_singbox)"
    [[ "$upstream_mode" == "direct" ]] && final_tag="warp-out"
    available_outbounds+=",warp-out"
  fi

  inbounds="${inbounds//\\n/$'\n'}"
  outbounds="${outbounds//\\n/$'\n'}"
  local route_json
  route_json="$(build_singbox_route_json "$final_tag" "$inbound_map" "$available_outbounds")"

  local config_backup="${config_file}.bak"
  if [[ -f "$config_file" ]]; then
    cp "$config_file" "$config_backup"
  fi

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
