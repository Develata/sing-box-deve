#!/usr/bin/env bash

append_argo_cdn_templates() {
  local file="$1" uuid="$2" domain="$3" vm="$4" vl="$5" enc="${6:-none}"
  local vm_host vl_host vm_path vl_path
  vm_host="$(sbd_cdn_host_vmess)"; [[ -n "$vm_host" ]] || vm_host="$domain"
  vl_host="$(sbd_cdn_host_vless_ws)"; [[ -n "$vl_host" ]] || vl_host="$domain"
  vm_path="$(sbd_vmess_ws_path)"
  vl_path="$(uri_encode "$(sbd_vless_ws_path)")"
  local ep host port tls
  for ep in "deve1.devekkk.dpdns.org:443:tls" "deve2.devekkk.dpdns.org:8443:tls" "deve3.devekkk.dpdns.org:2053:tls" "deve4.devekkk.dpdns.org:2083:tls" "deve5.devekkk.dpdns.org:2087:tls" "[2606:4700::0]:2096:tls" "deve6.devekkk.dpdns.org:80:none" "deve7.devekkk.dpdns.org:8080:none" "deve8.devekkk.dpdns.org:8880:none" "deve9.devekkk.dpdns.org:2052:none"; do
    if [[ "$ep" =~ ^(\[[^]]+\]|[^:]+):([0-9]+):(tls|none)$ ]]; then
      host="${BASH_REMATCH[1]}"; port="${BASH_REMATCH[2]}"; tls="${BASH_REMATCH[3]}"
    else
      continue
    fi
    if [[ "$vm" == "true" ]]; then
      echo "vmess://$(printf '{"v":"2","ps":"sbd-vmess-argo-cdn-%s","add":"%s","port":"%s","id":"%s","aid":"0","net":"ws","type":"none","host":"%s","path":"%s","tls":"%s","sni":"%s"}' "$port" "$host" "$port" "$uuid" "$vm_host" "$vm_path" "$([[ "$tls" == tls ]] && echo tls || echo '')" "$vm_host" | base64 -w 0)" >> "$file"
    fi
    if [[ "$vl" == "true" ]]; then
      if [[ "$tls" == "tls" ]]; then
        echo "vless://$uuid@$host:$port?encryption=$enc&security=tls&sni=$vl_host&type=ws&host=$vl_host&path=${vl_path}#sbd-vless-argo-cdn-$port" >> "$file"
      else
        echo "vless://$uuid@$host:$port?encryption=$enc&security=none&type=ws&host=$vl_host&path=${vl_path}#sbd-vless-argo-cdn-$port" >> "$file"
      fi
    fi
  done
}

rewrite_link_with_endpoint() {
  local link="$1" endpoint="$2" label="$3" host port payload json out
  if [[ "$endpoint" =~ ^(\[[^]]+\]|[^:]+):([0-9]+)$ ]]; then
    host="${BASH_REMATCH[1]}"; port="${BASH_REMATCH[2]}"
  else
    return 1
  fi

  case "$link" in
    vmess://*)
      payload="${link#vmess://}"
      json="$(printf '%s' "$payload" | base64 -d 2>/dev/null || true)"
      [[ -n "$json" ]] || return 1
      if ! command -v jq >/dev/null 2>&1; then return 1; fi
      out="$(printf '%s' "$json" | jq -c --arg add "$host" --arg port "$port" '.add=$add | .port=$port | .ps=(.ps + "-'"${label}"'")' 2>/dev/null || true)"
      [[ -n "$out" ]] || return 1
      echo "vmess://$(printf '%s' "$out" | base64 -w 0)"
      ;;
    vless://*|trojan://*|hysteria2://*|anytls://*|socks://*|wireguard://*|tuic://*|ss://*)
      local pre after hp suffix
      if [[ "$link" == *"@"* ]]; then
        pre="${link%%@*}@"; after="${link#*@}"
      else
        pre="${link%%://*}://"; after="${link#*://}"
      fi
      hp="${after%%[?#]*}"; suffix="${after#"$hp"}"
      echo "${pre}${host}:${port}${suffix}"
      ;;
    *) return 1 ;;
  esac
}

append_share_variants() {
  local base_file="$1" out_file="$2"; shift 2
  local group entry line rewritten
  for group in "$@"; do
    [[ -n "$group" ]] || continue
    IFS=',' read -r -a _entries <<< "$group"
    for entry in "${_entries[@]}"; do
      entry="$(echo "$entry" | xargs)"
      [[ "$entry" == *:* ]] || continue
      while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        rewritten="$(rewrite_link_with_endpoint "$line" "$entry" "share" 2>/dev/null || true)"
        [[ -n "$rewritten" ]] && echo "$rewritten" >> "$out_file"
      done < "$base_file"
    done
  done
}

build_aggregate_subscription() {
  [[ -f "$SBD_NODES_FILE" ]] || return 0
  base64 -w 0 < "$SBD_NODES_FILE" > "$SBD_SUB_FILE"
}

append_jump_variants() {
  load_jump_ports || return 0
  [[ -n "${JUMP_PROTOCOL:-}" && -n "${JUMP_MAIN_PORT:-}" && -n "${JUMP_EXTRA_PORTS:-}" ]] || return 0
  local marker
  case "$JUMP_PROTOCOL" in
    vless-reality) marker="#sbd-vless-reality" ;;
    vmess-ws) marker="sbd-vmess-ws" ;;
    vless-ws) marker="#sbd-vless-ws" ;;
    vless-xhttp) marker="#sbd-vless-xhttp" ;;
    shadowsocks-2022) marker="#sbd-shadowsocks-2022" ;;
    hysteria2) marker="#sbd-hysteria2" ;;
    tuic) marker="#sbd-tuic" ;;
    trojan) marker="#sbd-trojan" ;;
    anytls) marker="#sbd-anytls" ;;
    any-reality) marker="#sbd-any-reality" ;;
    socks5) marker="#sbd-socks5" ;;
    wireguard) marker="#sbd-wireguard-server" ;;
    *) return 0 ;;
  esac

  extract_link_host() {
    local lnk="$1" payload json
    case "$lnk" in
      vmess://*)
        payload="${lnk#vmess://}"
        json="$(printf '%s' "$payload" | base64 -d 2>/dev/null || true)"
        [[ -n "$json" ]] && printf '%s' "$json" | jq -r '.add // empty' 2>/dev/null
        ;;
      *)
        if [[ "$lnk" =~ ^[^:]+://[^@]+@([^:/?]+) ]]; then
          echo "${BASH_REMATCH[1]}"
        elif [[ "$lnk" =~ ^[^:]+://([^:/?]+) ]]; then
          echo "${BASH_REMATCH[1]}"
        fi
        ;;
    esac
  }

  local line p rewritten host
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    [[ "$line" == *"$marker"* ]] || continue
    host="$(extract_link_host "$line")"
    [[ -n "$host" ]] || continue
    IFS=',' read -r -a _extras <<< "$JUMP_EXTRA_PORTS"
    for p in "${_extras[@]}"; do
      p="$(echo "$p" | xargs)"
      [[ "$p" =~ ^[0-9]+$ ]] || continue
      (( p == JUMP_MAIN_PORT )) && continue
      rewritten="$(rewrite_link_with_endpoint "$line" "${host}:${p}" "jump" 2>/dev/null || true)"
      [[ -n "$rewritten" ]] && echo "$rewritten" >> "$SBD_NODES_FILE"
    done
  done < "$SBD_NODES_BASE_FILE"
}

write_nodes_output() {
  local engine="$1" protocols_csv="$2" ip uuid
  ip="$(detect_public_ip)"; uuid="$(ensure_uuid)"
  : > "$SBD_NODES_BASE_FILE"
  local reality_sni reality_fp tls_sni vm_path vless_ws_path vless_ws_path_uri xhttp_path xhttp_path_uri xhttp_mode enc_vless vm_cdn_host vl_cdn_host vh
  local ip_vmess ip_vless_ws ip_xhttp
  reality_sni="$(sbd_reality_server_name)"
  reality_fp="$(sbd_reality_fingerprint)"
  tls_sni="$(sbd_tls_server_name)"
  vm_path="$(sbd_vmess_ws_path)"
  vless_ws_path="$(sbd_vless_ws_path)"; vless_ws_path_uri="$(uri_encode "$vless_ws_path")"
  xhttp_path="$(sbd_vless_xhttp_path "$uuid")"; xhttp_path_uri="$(uri_encode "$xhttp_path")"; xhttp_mode="$(sbd_vless_xhttp_mode)"
  vm_cdn_host="$(sbd_cdn_host_vmess)"
  vl_cdn_host="$(sbd_cdn_host_vless_ws)"
  ip_vmess="$(sbd_proxyip_vmess "$ip")"
  ip_vless_ws="$(sbd_proxyip_vless_ws "$ip")"
  ip_xhttp="$(sbd_proxyip_vless_xhttp "$ip")"
  enc_vless="none"
  if [[ "$engine" == "xray" ]] && sbd_xray_vless_enc_enabled; then
    ensure_xray_vless_enc_keys
    enc_vless="$(sbd_xray_vless_encryption_key)"
    [[ -n "$enc_vless" ]] || enc_vless="none"
  fi

  local public_key short_id
  if [[ "$engine" == "sing-box" ]]; then
    public_key="$(<"${SBD_DATA_DIR}/reality_public.key")"; short_id="$(<"${SBD_DATA_DIR}/reality_short_id")"
  else
    public_key="$(<"${SBD_DATA_DIR}/xray_public.key")"; short_id="$(<"${SBD_DATA_DIR}/xray_short_id")"
  fi
  local protocols=()
  protocols_to_array "$protocols_csv" protocols
  local p_vless_reality p_vmess p_vless_ws p_xhttp p_ss p_hy2 p_tuic p_trojan p_anytls p_anyreality p_wg p_socks
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

  echo "vless://$uuid@$ip:${p_vless_reality}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$reality_sni&fp=$reality_fp&pbk=$public_key&sid=$short_id&type=tcp#sbd-vless-reality" >> "$SBD_NODES_BASE_FILE"
  protocol_enabled "vmess-ws" "${protocols[@]}" && echo "vmess://$(printf '{"v":"2","ps":"sbd-vmess-ws","add":"%s","port":"%s","id":"%s","aid":"0","net":"ws","type":"none","host":"%s","path":"%s","tls":""}' "$ip_vmess" "$p_vmess" "$uuid" "$vm_cdn_host" "$vm_path" | base64 -w 0)" >> "$SBD_NODES_BASE_FILE"
  if protocol_enabled "vless-ws" "${protocols[@]}"; then
    vh=""; [[ -n "$vl_cdn_host" ]] && vh="&host=${vl_cdn_host}"
    echo "vless://$uuid@$ip_vless_ws:${p_vless_ws}?encryption=$enc_vless&security=none&type=ws&path=${vless_ws_path_uri}${vh}#sbd-vless-ws" >> "$SBD_NODES_BASE_FILE"
  fi
  if [[ "$engine" == "xray" ]] && protocol_enabled "vless-xhttp" "${protocols[@]}"; then
    vh=""; [[ -n "$(sbd_cdn_host_vless_xhttp)" ]] && vh="&host=$(sbd_cdn_host_vless_xhttp)"
    echo "vless://$uuid@$ip_xhttp:${p_xhttp}?encryption=$enc_vless&flow=xtls-rprx-vision&security=reality&sni=$reality_sni&fp=$reality_fp&pbk=$public_key&sid=$short_id&type=xhttp&path=${xhttp_path_uri}&mode=$xhttp_mode${vh}#sbd-vless-xhttp" >> "$SBD_NODES_BASE_FILE"
  fi
  protocol_enabled "shadowsocks-2022" "${protocols[@]}" && echo "ss://$(printf '%s' "2022-blake3-aes-128-gcm:${uuid}" | base64 -w 0)@$ip:${p_ss}#sbd-shadowsocks-2022" >> "$SBD_NODES_BASE_FILE"
  protocol_enabled "hysteria2" "${protocols[@]}" && echo "hysteria2://$uuid@$ip:${p_hy2}?security=tls&sni=$tls_sni&insecure=1#sbd-hysteria2" >> "$SBD_NODES_BASE_FILE"
  protocol_enabled "tuic" "${protocols[@]}" && echo "tuic://$uuid:$uuid@$ip:${p_tuic}?congestion_control=bbr&sni=$tls_sni&allow_insecure=1#sbd-tuic" >> "$SBD_NODES_BASE_FILE"
  protocol_enabled "trojan" "${protocols[@]}" && echo "trojan://$uuid@$ip:${p_trojan}?security=tls&sni=$tls_sni#sbd-trojan" >> "$SBD_NODES_BASE_FILE"
  protocol_enabled "anytls" "${protocols[@]}" && echo "anytls://$uuid@$ip:${p_anytls}?security=tls&sni=$tls_sni#sbd-anytls" >> "$SBD_NODES_BASE_FILE"
  protocol_enabled "any-reality" "${protocols[@]}" && [[ "$engine" == "sing-box" ]] && echo "anytls://$uuid@$ip:${p_anyreality}?security=reality&sni=$reality_sni&pbk=$public_key&sid=$short_id#sbd-any-reality" >> "$SBD_NODES_BASE_FILE"
  protocol_enabled "wireguard" "${protocols[@]}" && echo "wireguard://$ip:${p_wg}#sbd-wireguard-server" >> "$SBD_NODES_BASE_FILE"
  protocol_enabled "socks5" "${protocols[@]}" && echo "socks://$uuid:$uuid@$ip:${p_socks}#sbd-socks5" >> "$SBD_NODES_BASE_FILE"
  protocol_enabled "warp" "${protocols[@]}" && echo "warp-mode://${WARP_MODE:-off}" >> "$SBD_NODES_BASE_FILE"

  if protocol_enabled "argo" "${protocols[@]}" && [[ -f "${SBD_DATA_DIR}/argo_domain" ]]; then
    local ad vm_enable vl_enable argo_vm_host argo_vl_host
    ad="$(<"${SBD_DATA_DIR}/argo_domain")"; vm_enable="$([[ " ${protocols[*]} " == *" vmess-ws "* ]] && echo true || echo false)"; vl_enable="$([[ " ${protocols[*]} " == *" vless-ws "* ]] && echo true || echo false)"
    argo_vm_host="${vm_cdn_host:-$ad}"; argo_vl_host="${vl_cdn_host:-$ad}"
    echo "argo-domain://${ad}" >> "$SBD_NODES_BASE_FILE"
    [[ "$vm_enable" == true ]] && echo "vmess://$(printf '{"v":"2","ps":"sbd-vmess-argo","add":"%s","port":"443","id":"%s","aid":"0","net":"ws","type":"none","host":"%s","path":"%s","tls":"tls","sni":"%s"}' "$ad" "$uuid" "$argo_vm_host" "$vm_path" "$argo_vm_host" | base64 -w 0)" >> "$SBD_NODES_BASE_FILE"
    [[ "$vl_enable" == true ]] && echo "vless://$uuid@$ad:443?encryption=$enc_vless&security=tls&sni=$argo_vl_host&type=ws&host=$argo_vl_host&path=${vless_ws_path_uri}#sbd-vless-argo" >> "$SBD_NODES_BASE_FILE"
    append_argo_cdn_templates "$SBD_NODES_BASE_FILE" "$uuid" "$ad" "$vm_enable" "$vl_enable" "$enc_vless"
  fi

  cp "$SBD_NODES_BASE_FILE" "$SBD_NODES_FILE"
  append_share_variants "$SBD_NODES_BASE_FILE" "$SBD_NODES_FILE" "${DIRECT_SHARE_ENDPOINTS:-}" "${PROXY_SHARE_ENDPOINTS:-}" "${WARP_SHARE_ENDPOINTS:-}"
  append_jump_variants
  awk 'NF && !seen[$0]++' "$SBD_NODES_FILE" > "${SBD_NODES_FILE}.tmp" && mv "${SBD_NODES_FILE}.tmp" "$SBD_NODES_FILE"
  build_aggregate_subscription
}
