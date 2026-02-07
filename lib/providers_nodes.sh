#!/usr/bin/env bash

runtime_port_for_tag() {
  local engine="$1"
  local tag="$2"
  if [[ "$engine" == "sing-box" && -f "${SBD_CONFIG_DIR}/config.json" ]]; then
    jq -r --arg t "$tag" '.inbounds[] | select(.tag==$t) | (.listen_port // .port // empty)' "${SBD_CONFIG_DIR}/config.json" | head -n1
  elif [[ "$engine" == "xray" && -f "${SBD_CONFIG_DIR}/xray-config.json" ]]; then
    jq -r --arg t "$tag" '.inbounds[] | select(.tag==$t) | (.port // empty)' "${SBD_CONFIG_DIR}/xray-config.json" | head -n1
  fi
}

write_nodes_output() {
  local engine="$1"
  local protocols_csv="$2"
  local ip uuid
  ip="$(detect_public_ip)"
  uuid="$(ensure_uuid)"

  : > "$SBD_NODES_FILE"

  if [[ "$engine" == "sing-box" ]]; then
    local public_key short_id
    public_key="$(<"${SBD_DATA_DIR}/reality_public.key")"
    short_id="$(<"${SBD_DATA_DIR}/reality_short_id")"
    echo "vless://$uuid@$ip:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=apple.com&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp#sbd-vless-reality" >> "$SBD_NODES_FILE"
  else
    local public_key short_id
    public_key="$(<"${SBD_DATA_DIR}/xray_public.key")"
    short_id="$(<"${SBD_DATA_DIR}/xray_short_id")"
    echo "vless://$uuid@$ip:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=apple.com&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp#sbd-vless-reality" >> "$SBD_NODES_FILE"
  fi

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
  if protocol_enabled "vmess-ws" "${protocols[@]}"; then
    echo "vmess://$(printf '{"v":"2","ps":"sbd-vmess-ws","add":"%s","port":"%s","id":"%s","aid":"0","net":"ws","type":"none","host":"","path":"/vmess","tls":""}' "$ip" "$p_vmess" "$uuid" | base64 -w 0)" >> "$SBD_NODES_FILE"
  fi
  if protocol_enabled "vless-ws" "${protocols[@]}"; then
    echo "vless://$uuid@$ip:${p_vless_ws}?encryption=none&security=none&type=ws&path=%2Fvless#sbd-vless-ws" >> "$SBD_NODES_FILE"
  fi
  if [[ "$engine" == "xray" ]] && protocol_enabled "vless-xhttp" "${protocols[@]}"; then
    local xpkey xsid
    xpkey="$(<"${SBD_DATA_DIR}/xray_public.key")"
    xsid="$(<"${SBD_DATA_DIR}/xray_short_id")"
    echo "vless://$uuid@$ip:${p_xhttp}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=apple.com&fp=chrome&pbk=$xpkey&sid=$xsid&type=xhttp&path=%2F${uuid}-xh&mode=auto#sbd-vless-xhttp" >> "$SBD_NODES_FILE"
  fi
  if protocol_enabled "hysteria2" "${protocols[@]}"; then
    echo "hysteria2://$uuid@$ip:${p_hy2}?security=tls&sni=www.bing.com&insecure=1#sbd-hysteria2" >> "$SBD_NODES_FILE"
  fi
  if protocol_enabled "trojan" "${protocols[@]}"; then
    echo "trojan://$uuid@$ip:${p_trojan}?security=tls&sni=www.bing.com#sbd-trojan" >> "$SBD_NODES_FILE"
  fi
  if protocol_enabled "anytls" "${protocols[@]}"; then
    echo "anytls://$uuid@$ip:${p_anytls}?security=tls&sni=www.bing.com#sbd-anytls" >> "$SBD_NODES_FILE"
  fi
  if protocol_enabled "any-reality" "${protocols[@]}"; then
    if [[ "$engine" == "sing-box" ]]; then
      local arpk arsid
      arpk="$(<"${SBD_DATA_DIR}/reality_public.key")"
      arsid="$(<"${SBD_DATA_DIR}/reality_short_id")"
      echo "anytls://$uuid@$ip:${p_anyreality}?security=reality&sni=apple.com&pbk=$arpk&sid=$arsid#sbd-any-reality" >> "$SBD_NODES_FILE"
    fi
  fi
  if protocol_enabled "wireguard" "${protocols[@]}"; then
    echo "wireguard://$ip:${p_wg}#sbd-wireguard-server" >> "$SBD_NODES_FILE"
  fi
  if protocol_enabled "socks5" "${protocols[@]}"; then
    echo "socks://$uuid:$uuid@$ip:${p_socks}#sbd-socks5" >> "$SBD_NODES_FILE"
  fi
  if protocol_enabled "warp" "${protocols[@]}"; then
    echo "warp-mode://${WARP_MODE:-off}" >> "$SBD_NODES_FILE"
  fi
  if protocol_enabled "argo" "${protocols[@]}" && [[ -f "${SBD_DATA_DIR}/argo_domain" ]]; then
    local ad
    ad="$(<"${SBD_DATA_DIR}/argo_domain")"
    echo "argo-domain://${ad}" >> "$SBD_NODES_FILE"
    if protocol_enabled "vmess-ws" "${protocols[@]}"; then
      echo "vmess://$(printf '{"v":"2","ps":"sbd-vmess-argo","add":"%s","port":"443","id":"%s","aid":"0","net":"ws","type":"none","host":"%s","path":"/vmess","tls":"tls","sni":"%s"}' "$ad" "$uuid" "$ad" "$ad" | base64 -w 0)" >> "$SBD_NODES_FILE"
    fi
    if protocol_enabled "vless-ws" "${protocols[@]}"; then
      echo "vless://$uuid@$ad:443?encryption=none&security=tls&sni=$ad&type=ws&host=$ad&path=%2Fvless#sbd-vless-argo" >> "$SBD_NODES_FILE"
    fi
  fi
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
    socks5) echo "socks5" ;;
    anytls) echo "anytls" ;;
    any-reality) echo "any-reality" ;;
    *) die "Unsupported protocol for set-port: $protocol" ;;
  esac
}
