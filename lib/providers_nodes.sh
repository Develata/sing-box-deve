#!/usr/bin/env bash

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
  if protocol_enabled "vmess-ws" "${protocols[@]}"; then
    echo "vmess://$(printf '{"v":"2","ps":"sbd-vmess-ws","add":"%s","port":"8443","id":"%s","aid":"0","net":"ws","type":"none","host":"","path":"/vmess","tls":""}' "$ip" "$uuid" | base64 -w 0)" >> "$SBD_NODES_FILE"
  fi
  if protocol_enabled "vless-ws" "${protocols[@]}"; then
    echo "vless://$uuid@$ip:8444?encryption=none&security=none&type=ws&path=%2Fvless#sbd-vless-ws" >> "$SBD_NODES_FILE"
  fi
  if [[ "$engine" == "xray" ]] && protocol_enabled "vless-xhttp" "${protocols[@]}"; then
    local xpkey xsid
    xpkey="$(<"${SBD_DATA_DIR}/xray_public.key")"
    xsid="$(<"${SBD_DATA_DIR}/xray_short_id")"
    echo "vless://$uuid@$ip:9443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=apple.com&fp=chrome&pbk=$xpkey&sid=$xsid&type=xhttp&path=%2F${uuid}-xh&mode=auto#sbd-vless-xhttp" >> "$SBD_NODES_FILE"
  fi
  if protocol_enabled "hysteria2" "${protocols[@]}"; then
    echo "hysteria2://$uuid@$ip:8443?security=tls&sni=www.bing.com&insecure=1#sbd-hysteria2" >> "$SBD_NODES_FILE"
  fi
  if protocol_enabled "trojan" "${protocols[@]}"; then
    echo "trojan://$uuid@$ip:4433?security=tls&sni=www.bing.com#sbd-trojan" >> "$SBD_NODES_FILE"
  fi
  if protocol_enabled "anytls" "${protocols[@]}"; then
    echo "anytls://$uuid@$ip:20443?security=tls&sni=www.bing.com#sbd-anytls" >> "$SBD_NODES_FILE"
  fi
  if protocol_enabled "any-reality" "${protocols[@]}"; then
    if [[ "$engine" == "sing-box" ]]; then
      local arpk arsid
      arpk="$(<"${SBD_DATA_DIR}/reality_public.key")"
      arsid="$(<"${SBD_DATA_DIR}/reality_short_id")"
      echo "anytls://$uuid@$ip:30443?security=reality&sni=apple.com&pbk=$arpk&sid=$arsid#sbd-any-reality" >> "$SBD_NODES_FILE"
    fi
  fi
  if protocol_enabled "wireguard" "${protocols[@]}"; then
    echo "wireguard://$ip:51820#sbd-wireguard-server" >> "$SBD_NODES_FILE"
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
    anytls) echo "anytls" ;;
    any-reality) echo "any-reality" ;;
    *) die "Unsupported protocol for set-port: $protocol" ;;
  esac
}
