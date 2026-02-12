#!/usr/bin/env bash

build_aggregate_subscription() {
  [[ -f "$SBD_NODES_FILE" ]] || return 0
  base64 -w 0 < "$SBD_NODES_FILE" > "$SBD_SUB_FILE"
}

write_nodes_output() {
  local engine="$1" protocols_csv="$2" ip uuid
  ip="$(detect_public_ip)"
  uuid="$(ensure_uuid)"
  : > "$SBD_NODES_BASE_FILE"

  local reality_sni reality_fp tls_sni vm_path vless_ws_path vless_ws_path_uri
  local xhttp_path xhttp_path_uri xhttp_mode enc_vless vm_cdn_host
  local ip_vmess ip_vless_ws ip_xhttp public_key short_id
  local p_vless_reality p_vmess p_vless_ws p_xhttp p_ss p_hy2 p_tuic
  local p_trojan p_anytls p_anyreality p_wg p_socks
  local protocols=()

  reality_sni="$(sbd_reality_server_name)"
  reality_fp="$(sbd_reality_fingerprint)"
  tls_sni="$(sbd_tls_server_name)"
  vm_path="$(sbd_vmess_ws_path)"
  vless_ws_path="$(sbd_vless_ws_path)"
  vless_ws_path_uri="$(uri_encode "$vless_ws_path")"
  xhttp_path="$(sbd_vless_xhttp_path "$uuid")"
  xhttp_path_uri="$(uri_encode "$xhttp_path")"
  xhttp_mode="$(sbd_vless_xhttp_mode)"
  vm_cdn_host="$(sbd_cdn_host_vmess)"
  ip_vmess="$(sbd_proxyip_vmess "$ip")"
  ip_vless_ws="$(sbd_proxyip_vless_ws "$ip")"
  ip_xhttp="$(sbd_proxyip_vless_xhttp "$ip")"

  enc_vless="none"
  if [[ "$engine" == "xray" ]] && sbd_xray_vless_enc_enabled; then
    ensure_xray_vless_enc_keys
    enc_vless="$(sbd_xray_vless_encryption_key)"
    [[ -n "$enc_vless" ]] || enc_vless="none"
  fi

  if [[ "$engine" == "sing-box" ]]; then
    public_key="$(<"${SBD_DATA_DIR}/reality_public.key")"
    short_id="$(<"${SBD_DATA_DIR}/reality_short_id")"
  else
    public_key="$(<"${SBD_DATA_DIR}/xray_public.key")"
    short_id="$(<"${SBD_DATA_DIR}/xray_short_id")"
  fi

  protocols_to_array "$protocols_csv" protocols
  p_vless_reality="$(resolve_protocol_port_for_engine "$engine" "vless-reality")"
  p_vmess="$(resolve_protocol_port_for_engine "$engine" "vmess-ws")"
  p_vless_ws="$(resolve_protocol_port_for_engine "$engine" "vless-ws")"
  p_xhttp="$(resolve_protocol_port_for_engine "$engine" "vless-xhttp")"
  p_ss="$(resolve_protocol_port_for_engine "$engine" "shadowsocks-2022")"
  p_hy2="$(resolve_protocol_port_for_engine "$engine" "hysteria2")"
  p_tuic="$(resolve_protocol_port_for_engine "$engine" "tuic")"
  p_trojan="$(resolve_protocol_port_for_engine "$engine" "trojan")"
  p_anytls="$(resolve_protocol_port_for_engine "$engine" "anytls")"
  p_anyreality="$(resolve_protocol_port_for_engine "$engine" "any-reality")"
  p_wg="$(resolve_protocol_port_for_engine "$engine" "wireguard")"
  p_socks="$(resolve_protocol_port_for_engine "$engine" "socks5")"

  node_link_vless_reality "$uuid" "$ip" "$p_vless_reality" "$reality_sni" "$reality_fp" "$public_key" "$short_id" >> "$SBD_NODES_BASE_FILE"

  if protocol_enabled "vmess-ws" "${protocols[@]}"; then
    node_link_vmess_ws "$uuid" "$ip_vmess" "$p_vmess" "$vm_cdn_host" "$vm_path" >> "$SBD_NODES_BASE_FILE"
  fi
  if protocol_enabled "vless-ws" "${protocols[@]}"; then
    node_link_vless_ws "$uuid" "$ip_vless_ws" "$p_vless_ws" "$enc_vless" "$vless_ws_path_uri" "$(sbd_cdn_host_vless_ws)" >> "$SBD_NODES_BASE_FILE"
  fi
  if [[ "$engine" == "xray" ]] && protocol_enabled "vless-xhttp" "${protocols[@]}"; then
    node_link_vless_xhttp "$uuid" "$ip_xhttp" "$p_xhttp" "$enc_vless" "$reality_sni" "$reality_fp" "$public_key" "$short_id" "$xhttp_path_uri" "$xhttp_mode" "$(sbd_cdn_host_vless_xhttp)" >> "$SBD_NODES_BASE_FILE"
  fi
  if protocol_enabled "shadowsocks-2022" "${protocols[@]}"; then
    node_link_ss2022 "$uuid" "$ip" "$p_ss" >> "$SBD_NODES_BASE_FILE"
  fi
  if protocol_enabled "hysteria2" "${protocols[@]}"; then
    node_link_hysteria2 "$uuid" "$ip" "$p_hy2" "$tls_sni" >> "$SBD_NODES_BASE_FILE"
  fi
  if protocol_enabled "tuic" "${protocols[@]}"; then
    node_link_tuic "$uuid" "$ip" "$p_tuic" "$tls_sni" >> "$SBD_NODES_BASE_FILE"
  fi
  if protocol_enabled "trojan" "${protocols[@]}"; then
    node_link_trojan "$uuid" "$ip" "$p_trojan" "$tls_sni" >> "$SBD_NODES_BASE_FILE"
  fi
  if protocol_enabled "anytls" "${protocols[@]}"; then
    node_link_anytls "$uuid" "$ip" "$p_anytls" "$tls_sni" >> "$SBD_NODES_BASE_FILE"
  fi
  if [[ "$engine" == "sing-box" ]] && protocol_enabled "any-reality" "${protocols[@]}"; then
    node_link_any_reality "$uuid" "$ip" "$p_anyreality" "$reality_sni" "$public_key" "$short_id" >> "$SBD_NODES_BASE_FILE"
  fi
  if protocol_enabled "wireguard" "${protocols[@]}"; then
    node_link_wireguard "$ip" "$p_wg" >> "$SBD_NODES_BASE_FILE"
  fi
  if protocol_enabled "socks5" "${protocols[@]}"; then
    node_link_socks5 "$uuid" "$ip" "$p_socks" >> "$SBD_NODES_BASE_FILE"
  fi
  if protocol_enabled "warp" "${protocols[@]}"; then
    node_link_warp_mode "${WARP_MODE:-off}" >> "$SBD_NODES_BASE_FILE"
  fi

  if protocol_enabled "argo" "${protocols[@]}" && [[ -f "${SBD_DATA_DIR}/argo_domain" ]]; then
    append_argo_primary_links "$SBD_NODES_BASE_FILE" "$protocols_csv" "$uuid" "$(<"${SBD_DATA_DIR}/argo_domain")" "$enc_vless"
  fi

  cp "$SBD_NODES_BASE_FILE" "$SBD_NODES_FILE"
  append_share_variants "$SBD_NODES_BASE_FILE" "$SBD_NODES_FILE" "${DIRECT_SHARE_ENDPOINTS:-}" "${PROXY_SHARE_ENDPOINTS:-}" "${WARP_SHARE_ENDPOINTS:-}"
  append_multi_real_port_variants "$SBD_NODES_FILE" "$SBD_NODES_FILE"
  append_jump_variants "$SBD_NODES_FILE" "$SBD_NODES_FILE"
  awk 'NF && !seen[$0]++' "$SBD_NODES_FILE" > "${SBD_NODES_FILE}.tmp" && mv "${SBD_NODES_FILE}.tmp" "$SBD_NODES_FILE"
  build_aggregate_subscription
}
