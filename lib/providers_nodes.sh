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

  local reality_sni reality_fp tls_sni vless_ws_path vless_ws_path_uri
  local xhttp_path xhttp_path_uri xhttp_mode enc_vless
  local ip_vless_ws ip_xhttp public_key short_id
  local p_vless_reality p_vless_ws p_xhttp p_ss p_naive p_hy2 p_tuic ss2022_password hy2_obfs_mode hy2_obfs_password
  local protocols=()

  reality_sni="$(sbd_reality_server_name)"
  reality_fp="$(sbd_reality_fingerprint)"
  tls_sni="$(sbd_tls_server_name)"
  vless_ws_path="$(sbd_vless_ws_path)"
  vless_ws_path_uri="$(uri_encode "$vless_ws_path")"
  xhttp_path="$(sbd_vless_xhttp_path "$uuid")"
  xhttp_path_uri="$(uri_encode "$xhttp_path")"
  xhttp_mode="$(sbd_vless_xhttp_mode)"
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
  p_vless_ws="$(resolve_protocol_port_for_engine "$engine" "vless-ws")"
  p_xhttp="$(resolve_protocol_port_for_engine "$engine" "vless-xhttp")"
  p_ss="$(resolve_protocol_port_for_engine "$engine" "shadowsocks-2022")"
  p_naive="$(resolve_protocol_port_for_engine "$engine" "naive")"
  p_hy2="$(resolve_protocol_port_for_engine "$engine" "hysteria2")"
  p_tuic="$(resolve_protocol_port_for_engine "$engine" "tuic")"

  if protocol_enabled "vless-reality" "${protocols[@]}"; then
    node_link_vless_reality "$uuid" "$ip" "$p_vless_reality" "$reality_sni" "$reality_fp" "$public_key" "$short_id" >> "$SBD_NODES_BASE_FILE"
  fi

  if protocol_enabled "vless-ws" "${protocols[@]}"; then
    node_link_vless_ws "$uuid" "$ip_vless_ws" "$p_vless_ws" "$enc_vless" "$vless_ws_path_uri" "$(sbd_cdn_host_vless_ws)" >> "$SBD_NODES_BASE_FILE"
  fi
  if [[ "$engine" == "xray" ]] && protocol_enabled "vless-xhttp" "${protocols[@]}"; then
    node_link_vless_xhttp "$uuid" "$ip_xhttp" "$p_xhttp" "$enc_vless" "$reality_sni" "$reality_fp" "$public_key" "$short_id" "$xhttp_path_uri" "$xhttp_mode" "$(sbd_cdn_host_vless_xhttp)" >> "$SBD_NODES_BASE_FILE"
  fi
  if protocol_enabled "shadowsocks-2022" "${protocols[@]}"; then
    ss2022_password="$(ensure_ss2022_password)"
    node_link_ss2022 "$ss2022_password" "$ip" "$p_ss" >> "$SBD_NODES_BASE_FILE"
  fi
  if [[ "$engine" == "sing-box" ]] && protocol_enabled "naive" "${protocols[@]}"; then
    node_link_naive "$uuid" "$ip" "$p_naive" "$tls_sni" >> "$SBD_NODES_BASE_FILE"
  fi
  if protocol_enabled "hysteria2" "${protocols[@]}"; then
    hy2_obfs_mode="$(sbd_hy2_obfs_mode)"
    hy2_obfs_password=""
    if [[ "$hy2_obfs_mode" != "off" ]]; then
      hy2_obfs_password="$(sbd_hy2_obfs_password)"
    fi
    node_link_hysteria2 "$uuid" "$ip" "$p_hy2" "$tls_sni" "$hy2_obfs_mode" "$hy2_obfs_password" >> "$SBD_NODES_BASE_FILE"
  fi
  if protocol_enabled "tuic" "${protocols[@]}"; then
    node_link_tuic "$uuid" "$ip" "$p_tuic" "$tls_sni" >> "$SBD_NODES_BASE_FILE"
  fi
  if [[ "${WARP_MODE:-off}" != "off" ]]; then
    node_link_warp_mode "${WARP_MODE:-off}" >> "$SBD_NODES_BASE_FILE"
  fi

  if [[ "${ARGO_MODE:-off}" != "off" && -f "${SBD_DATA_DIR}/argo_domain" ]]; then
    append_argo_primary_links "$SBD_NODES_BASE_FILE" "$protocols_csv" "$uuid" "$(<"${SBD_DATA_DIR}/argo_domain")" "$enc_vless"
  fi

  cp "$SBD_NODES_BASE_FILE" "$SBD_NODES_FILE"
  append_multi_real_port_variants "$SBD_NODES_FILE" "$SBD_NODES_FILE"
  awk 'NF && !seen[$0]++' "$SBD_NODES_FILE" > "${SBD_NODES_FILE}.tmp" && mv "${SBD_NODES_FILE}.tmp" "$SBD_NODES_FILE"
  build_aggregate_subscription
}
