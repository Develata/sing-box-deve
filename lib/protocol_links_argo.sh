#!/usr/bin/env bash

append_argo_cdn_templates() {
  local file="$1" uuid="$2" domain="$3" vm="$4" vl="$5" enc="${6:-none}"
  local vm_host vl_host vm_path vl_path
  vm_host="$(sbd_cdn_host_vmess)"; [[ -n "$vm_host" ]] || vm_host="$domain"
  vl_host="$(sbd_cdn_host_vless_ws)"; [[ -n "$vl_host" ]] || vl_host="$domain"
  vm_path="$(sbd_vmess_ws_path)"
  vl_path="$(uri_encode "$(sbd_vless_ws_path)")"
  local cdn_endpoints="${ARGO_CDN_ENDPOINTS:-}"
  if [[ -z "$cdn_endpoints" ]]; then
    return 0
  fi

  local ep host port tls
  for ep in ${cdn_endpoints//,/ }; do
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

append_argo_primary_links() {
  local file="$1" protocols_csv="$2" uuid="$3" argo_domain="$4" enc_vless="$5"
  local vm_path vless_ws_path_uri vm_cdn_host vl_cdn_host
  vm_path="$(sbd_vmess_ws_path)"
  vless_ws_path_uri="$(uri_encode "$(sbd_vless_ws_path)")"
  vm_cdn_host="$(sbd_cdn_host_vmess)"
  vl_cdn_host="$(sbd_cdn_host_vless_ws)"

  local vm_enable="false" vl_enable="false"
  protocol_csv_has "$protocols_csv" "vmess-ws" && vm_enable="true"
  protocol_csv_has "$protocols_csv" "vless-ws" && vl_enable="true"
  [[ "$vm_enable" == "true" || "$vl_enable" == "true" ]] || return 0

  local argo_vm_host="${vm_cdn_host:-$argo_domain}"
  local argo_vl_host="${vl_cdn_host:-$argo_domain}"
  echo "argo-domain://${argo_domain}" >> "$file"

  if [[ "$vm_enable" == "true" ]]; then
    echo "vmess://$(printf '{"v":"2","ps":"sbd-vmess-argo","add":"%s","port":"443","id":"%s","aid":"0","net":"ws","type":"none","host":"%s","path":"%s","tls":"tls","sni":"%s"}' "$argo_domain" "$uuid" "$argo_vm_host" "$vm_path" "$argo_vm_host" | base64 -w 0)" >> "$file"
  fi
  if [[ "$vl_enable" == "true" ]]; then
    echo "vless://$uuid@$argo_domain:443?encryption=$enc_vless&security=tls&sni=$argo_vl_host&type=ws&host=$argo_vl_host&path=${vless_ws_path_uri}#sbd-vless-argo" >> "$file"
  fi

  append_argo_cdn_templates "$file" "$uuid" "$argo_domain" "$vm_enable" "$vl_enable" "$enc_vless"
}
