#!/usr/bin/env bash

runtime_port_for_tag() {
  local engine="$1" tag="$2"
  if [[ "$engine" == "sing-box" && -f "${SBD_CONFIG_DIR}/config.json" ]]; then
    jq -r --arg t "$tag" '.inbounds[] | select(.tag==$t) | (.listen_port // .port // empty)' "${SBD_CONFIG_DIR}/config.json" | head -n1
  elif [[ "$engine" == "xray" && -f "${SBD_CONFIG_DIR}/xray-config.json" ]]; then
    jq -r --arg t "$tag" '.inbounds[] | select(.tag==$t) | (.port // empty)' "${SBD_CONFIG_DIR}/xray-config.json" | head -n1
  fi
}

append_argo_cdn_templates() {
  local file="$1" uuid="$2" domain="$3" vm="$4" vl="$5"
  local ep host port tls
  for ep in "yg1.ygkkk.dpdns.org:443:tls" "yg2.ygkkk.dpdns.org:8443:tls" "yg3.ygkkk.dpdns.org:2053:tls" "yg4.ygkkk.dpdns.org:2083:tls" "yg5.ygkkk.dpdns.org:2087:tls" "[2606:4700::0]:2096:tls" "yg6.ygkkk.dpdns.org:80:none" "yg7.ygkkk.dpdns.org:8080:none" "yg8.ygkkk.dpdns.org:8880:none" "yg9.ygkkk.dpdns.org:2052:none"; do
    host="${ep%%:*}"; port="${ep#*:}"; port="${port%%:*}"; tls="${ep##*:}"
    if [[ "$vm" == "true" ]]; then
      echo "vmess://$(printf '{"v":"2","ps":"sbd-vmess-argo-cdn-%s","add":"%s","port":"%s","id":"%s","aid":"0","net":"ws","type":"none","host":"%s","path":"/vmess","tls":"%s","sni":"%s"}' "$port" "$host" "$port" "$uuid" "$domain" "$([[ "$tls" == tls ]] && echo tls || echo '')" "$domain" | base64 -w 0)" >> "$file"
    fi
    if [[ "$vl" == "true" ]]; then
      if [[ "$tls" == "tls" ]]; then
        echo "vless://$uuid@$host:$port?encryption=none&security=tls&sni=$domain&type=ws&host=$domain&path=%2Fvless#sbd-vless-argo-cdn-$port" >> "$file"
      else
        echo "vless://$uuid@$host:$port?encryption=none&security=none&type=ws&host=$domain&path=%2Fvless#sbd-vless-argo-cdn-$port" >> "$file"
      fi
    fi
  done
}

rewrite_link_with_endpoint() {
  local link="$1" endpoint="$2" label="$3" host port payload json out
  host="${endpoint%%:*}"; port="${endpoint##*:}"
  if [[ ! "$port" =~ ^[0-9]+$ ]]; then return 1; fi

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
    vless://*|trojan://*|hysteria2://*|anytls://*|socks://*|wireguard://*)
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

write_nodes_output() {
  local engine="$1" protocols_csv="$2" ip uuid
  ip="$(detect_public_ip)"; uuid="$(ensure_uuid)"
  : > "$SBD_NODES_BASE_FILE"

  local public_key short_id
  if [[ "$engine" == "sing-box" ]]; then
    public_key="$(<"${SBD_DATA_DIR}/reality_public.key")"; short_id="$(<"${SBD_DATA_DIR}/reality_short_id")"
  else
    public_key="$(<"${SBD_DATA_DIR}/xray_public.key")"; short_id="$(<"${SBD_DATA_DIR}/xray_short_id")"
  fi
  echo "vless://$uuid@$ip:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=apple.com&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp#sbd-vless-reality" >> "$SBD_NODES_BASE_FILE"

  local protocols=()
  protocols_to_array "$protocols_csv" protocols
  local p_vmess p_vless_ws p_xhttp p_hy2 p_trojan p_anytls p_anyreality p_wg p_socks
  p_vmess="$(runtime_port_for_tag "$engine" "vmess-ws")"; [[ -n "$p_vmess" ]] || p_vmess="$(get_protocol_port "vmess-ws")"
  p_vless_ws="$(runtime_port_for_tag "$engine" "vless-ws")"; [[ -n "$p_vless_ws" ]] || p_vless_ws="$(get_protocol_port "vless-ws")"
  p_xhttp="$(runtime_port_for_tag "$engine" "vless-xhttp")"; [[ -n "$p_xhttp" ]] || p_xhttp="$(get_protocol_port "vless-xhttp")"
  p_hy2="$(runtime_port_for_tag "$engine" "hy2")"; [[ -n "$p_hy2" ]] || p_hy2="$(get_protocol_port "hysteria2")"
  p_trojan="$(runtime_port_for_tag "$engine" "trojan")"; [[ -n "$p_trojan" ]] || p_trojan="$(get_protocol_port "trojan")"
  p_anytls="$(runtime_port_for_tag "$engine" "anytls")"; [[ -n "$p_anytls" ]] || p_anytls="$(get_protocol_port "anytls")"
  p_anyreality="$(runtime_port_for_tag "$engine" "any-reality")"; [[ -n "$p_anyreality" ]] || p_anyreality="$(get_protocol_port "any-reality")"
  p_wg="$(runtime_port_for_tag "$engine" "wireguard")"; [[ -n "$p_wg" ]] || p_wg="$(get_protocol_port "wireguard")"
  p_socks="$(runtime_port_for_tag "$engine" "socks5")"; [[ -n "$p_socks" ]] || p_socks="$(get_protocol_port "socks5")"

  protocol_enabled "vmess-ws" "${protocols[@]}" && echo "vmess://$(printf '{"v":"2","ps":"sbd-vmess-ws","add":"%s","port":"%s","id":"%s","aid":"0","net":"ws","type":"none","host":"","path":"/vmess","tls":""}' "$ip" "$p_vmess" "$uuid" | base64 -w 0)" >> "$SBD_NODES_BASE_FILE"
  protocol_enabled "vless-ws" "${protocols[@]}" && echo "vless://$uuid@$ip:${p_vless_ws}?encryption=none&security=none&type=ws&path=%2Fvless#sbd-vless-ws" >> "$SBD_NODES_BASE_FILE"
  if [[ "$engine" == "xray" ]] && protocol_enabled "vless-xhttp" "${protocols[@]}"; then
    echo "vless://$uuid@$ip:${p_xhttp}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=apple.com&fp=chrome&pbk=$public_key&sid=$short_id&type=xhttp&path=%2F${uuid}-xh&mode=auto#sbd-vless-xhttp" >> "$SBD_NODES_BASE_FILE"
  fi
  protocol_enabled "hysteria2" "${protocols[@]}" && echo "hysteria2://$uuid@$ip:${p_hy2}?security=tls&sni=www.bing.com&insecure=1#sbd-hysteria2" >> "$SBD_NODES_BASE_FILE"
  protocol_enabled "trojan" "${protocols[@]}" && echo "trojan://$uuid@$ip:${p_trojan}?security=tls&sni=www.bing.com#sbd-trojan" >> "$SBD_NODES_BASE_FILE"
  protocol_enabled "anytls" "${protocols[@]}" && echo "anytls://$uuid@$ip:${p_anytls}?security=tls&sni=www.bing.com#sbd-anytls" >> "$SBD_NODES_BASE_FILE"
  protocol_enabled "any-reality" "${protocols[@]}" && [[ "$engine" == "sing-box" ]] && echo "anytls://$uuid@$ip:${p_anyreality}?security=reality&sni=apple.com&pbk=$public_key&sid=$short_id#sbd-any-reality" >> "$SBD_NODES_BASE_FILE"
  protocol_enabled "wireguard" "${protocols[@]}" && echo "wireguard://$ip:${p_wg}#sbd-wireguard-server" >> "$SBD_NODES_BASE_FILE"
  protocol_enabled "socks5" "${protocols[@]}" && echo "socks://$uuid:$uuid@$ip:${p_socks}#sbd-socks5" >> "$SBD_NODES_BASE_FILE"
  protocol_enabled "warp" "${protocols[@]}" && echo "warp-mode://${WARP_MODE:-off}" >> "$SBD_NODES_BASE_FILE"

  if protocol_enabled "argo" "${protocols[@]}" && [[ -f "${SBD_DATA_DIR}/argo_domain" ]]; then
    local ad vm_enable vl_enable
    ad="$(<"${SBD_DATA_DIR}/argo_domain")"; vm_enable="$([[ " ${protocols[*]} " == *" vmess-ws "* ]] && echo true || echo false)"; vl_enable="$([[ " ${protocols[*]} " == *" vless-ws "* ]] && echo true || echo false)"
    echo "argo-domain://${ad}" >> "$SBD_NODES_BASE_FILE"
    [[ "$vm_enable" == true ]] && echo "vmess://$(printf '{"v":"2","ps":"sbd-vmess-argo","add":"%s","port":"443","id":"%s","aid":"0","net":"ws","type":"none","host":"%s","path":"/vmess","tls":"tls","sni":"%s"}' "$ad" "$uuid" "$ad" "$ad" | base64 -w 0)" >> "$SBD_NODES_BASE_FILE"
    [[ "$vl_enable" == true ]] && echo "vless://$uuid@$ad:443?encryption=none&security=tls&sni=$ad&type=ws&host=$ad&path=%2Fvless#sbd-vless-argo" >> "$SBD_NODES_BASE_FILE"
    append_argo_cdn_templates "$SBD_NODES_BASE_FILE" "$uuid" "$ad" "$vm_enable" "$vl_enable"
  fi

  cp "$SBD_NODES_BASE_FILE" "$SBD_NODES_FILE"
  append_share_variants "$SBD_NODES_BASE_FILE" "$SBD_NODES_FILE" "${DIRECT_SHARE_ENDPOINTS:-}" "${PROXY_SHARE_ENDPOINTS:-}" "${WARP_SHARE_ENDPOINTS:-}"
  awk 'NF && !seen[$0]++' "$SBD_NODES_FILE" > "${SBD_NODES_FILE}.tmp" && mv "${SBD_NODES_FILE}.tmp" "$SBD_NODES_FILE"
  build_aggregate_subscription
}

protocol_to_tag() {
  local protocol="$1"
  case "$protocol" in
    vless-reality) echo "vless-reality" ;;
    vmess-ws) echo "vmess-ws" ;;
    vless-ws) echo "vless-ws" ;;
    vless-xhttp) echo "vless-xhttp" ;;
    shadowsocks-2022) echo "ss-2022" ;;
    hysteria2) echo "hy2" ;;
    tuic) echo "tuic" ;;
    trojan) echo "trojan" ;;
    wireguard) echo "wireguard" ;;
    anytls) echo "anytls" ;;
    any-reality) echo "any-reality" ;;
    socks5) echo "socks5" ;;
    *) die "Unsupported protocol for set-port: $protocol" ;;
  esac
}
