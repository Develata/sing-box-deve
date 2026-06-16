#!/usr/bin/env bash
build_sing_box_config() {
  local protocols_csv="$1"
  local config_file="${SBD_CONFIG_DIR}/config.json"
  local uuid
  uuid="$(ensure_uuid)"
  local cert_file key_file
  cert_file="$(get_tls_cert_path)"
  key_file="$(get_tls_key_path)"
  local ss2022_password=""
  generate_reality_keys
  local private_key public_key short_id
  private_key="$(<"${SBD_DATA_DIR}/reality_private.key")"
  public_key="$(<"${SBD_DATA_DIR}/reality_public.key")"
  short_id="$(<"${SBD_DATA_DIR}/reality_short_id")"
  local reality_server_name reality_port tls_server_name ws_path_vless
  reality_server_name="$(sbd_reality_server_name)"
  reality_port="$(sbd_reality_handshake_port)"
  tls_server_name="$(sbd_tls_server_name)"
  ws_path_vless="$(sbd_vless_ws_path)"
  local port_vless_reality port_vless_ws port_ss2022 port_naive port_hysteria2
  local port_tuic
  port_vless_reality="$(resolve_protocol_port_for_engine "sing-box" "vless-reality")"
  port_vless_ws="$(resolve_protocol_port_for_engine "sing-box" "vless-ws")"
  port_ss2022="$(resolve_protocol_port_for_engine "sing-box" "shadowsocks-2022")"
  port_naive="$(resolve_protocol_port_for_engine "sing-box" "naive")"
  port_hysteria2="$(resolve_protocol_port_for_engine "sing-box" "hysteria2")"
  port_tuic="$(resolve_protocol_port_for_engine "sing-box" "tuic")"
  local inbounds=""
  local inbound_map=""
  local protocols=()
  protocols_to_array "$protocols_csv" protocols

  if protocol_enabled "vless-reality" "${protocols[@]}"; then
    sbd_inbounds_append inbounds inbound_map "vless-reality" "$port_vless_reality" \
      "$(singbox_fragment_vless_reality "$uuid" "$port_vless_reality" "$reality_server_name" "$reality_port" "$private_key" "$short_id")"
  fi

  local has_warp="false"
  if warp_mode_targets_singbox "${WARP_MODE:-off}"; then
    has_warp="true"
  elif protocol_enabled "warp" "${protocols[@]}"; then
    log_warn "$(msg "已启用 warp 协议，但当前 WARP_MODE='${WARP_MODE:-off}' 不指向 sing-box 路径" "Protocol 'warp' enabled but WARP_MODE='${WARP_MODE:-off}' targets non-sing-box path")"
  fi

  if protocol_enabled "vless-ws" "${protocols[@]}"; then
    sbd_inbounds_append inbounds inbound_map "vless-ws" "$port_vless_ws" \
      "$(singbox_fragment_vless_ws "$uuid" "$port_vless_ws" "$ws_path_vless")"
  fi

  if protocol_enabled "shadowsocks-2022" "${protocols[@]}"; then
    ss2022_password="$(ensure_ss2022_password)"
    sbd_inbounds_append inbounds inbound_map "ss-2022" "$port_ss2022" \
      "$(singbox_fragment_ss2022 "$ss2022_password" "$port_ss2022")"
  fi

  if protocol_enabled "naive" "${protocols[@]}"; then
    sbd_inbounds_append inbounds inbound_map "naive" "$port_naive" \
      "$(singbox_fragment_naive "$uuid" "$port_naive" "$tls_server_name" "$cert_file" "$key_file")"
  fi

  if protocol_enabled "hysteria2" "${protocols[@]}"; then
    local archive_site_dir=""
    if protocols_require_domain_cert "$protocols_csv"; then
      archive_site_dir="$(sbd_archive_site_dir)"
    fi
    sbd_inbounds_append inbounds inbound_map "hy2" "$port_hysteria2" \
      "$(singbox_fragment_hysteria2 "$uuid" "$port_hysteria2" "$tls_server_name" "$cert_file" "$key_file" "$archive_site_dir")"
  fi

  if protocol_enabled "tuic" "${protocols[@]}"; then
    sbd_inbounds_append inbounds inbound_map "tuic" "$port_tuic" \
      "$(singbox_fragment_tuic "$uuid" "$port_tuic" "$tls_server_name" "$cert_file" "$key_file")"
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

  local tmp_config
  tmp_config="$(mktemp "${config_file}.tmp.XXXXXX")"
  cat > "$tmp_config" <<EOF_JSON
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
  sbd_commit_file_with_backups "$config_file" "$tmp_config" 600

  multi_ports_runtime_append_singbox "$protocols_csv"
  echo "$public_key" > "${SBD_DATA_DIR}/reality_public.key"
}
