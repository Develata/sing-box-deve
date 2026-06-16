#!/usr/bin/env bash

# Cloudflare CDN port constants
CDN_TLS_PORTS=(443 8443 2053 2083 2087 2096)
CDN_PLAIN_PORTS=(80 8080 8880 2052 2082 2086 2095)

# Auto-generate CDN endpoints if none provided
# Uses Cloudflare-compatible TLS and non-TLS ports with the argo domain as host
sbd_auto_cdn_endpoints() {
  local domain="$1"
  [[ -n "$domain" ]] || return 0
  local parts=() port
  for port in "${CDN_TLS_PORTS[@]}"; do
    parts+=("${domain}:${port}:tls")
  done
  for port in "${CDN_PLAIN_PORTS[@]}"; do
    parts+=("${domain}:${port}:none")
  done
  local IFS=','
  echo "${parts[*]}"
}

append_argo_cdn_templates() {
  local file="$1" uuid="$2" domain="$3" vl="$4" enc="${5:-none}"
  local vl_host vl_path
  vl_host="$(sbd_cdn_host_vless_ws)"; [[ -n "$vl_host" ]] || vl_host="$domain"
  vl_path="$(uri_encode "$(sbd_vless_ws_path)")"
  local cdn_endpoints="${ARGO_CDN_ENDPOINTS:-}"

  # Auto-expand: when no explicit endpoints, generate all 13 Cloudflare CDN ports
  if [[ -z "$cdn_endpoints" ]]; then
    cdn_endpoints="$(sbd_auto_cdn_endpoints "$domain")"
    [[ -n "$cdn_endpoints" ]] || return 0
  fi

  local ep host port tls
  for ep in ${cdn_endpoints//,/ }; do
    if [[ "$ep" =~ ^(\[[^]]+\]|[^:]+):([0-9]+):(tls|none)$ ]]; then
      host="${BASH_REMATCH[1]}"; port="${BASH_REMATCH[2]}"; tls="${BASH_REMATCH[3]}"
    else
      continue
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
  local vless_ws_path_uri vl_cdn_host
  vless_ws_path_uri="$(uri_encode "$(sbd_vless_ws_path)")"
  vl_cdn_host="$(sbd_cdn_host_vless_ws)"

  local vl_enable="false"
  protocol_csv_has "$protocols_csv" "vless-ws" && vl_enable="true"
  [[ "$vl_enable" == "true" ]] || return 0

  local argo_vl_host="${vl_cdn_host:-$argo_domain}"
  echo "argo-domain://${argo_domain}" >> "$file"

  echo "vless://$uuid@$argo_domain:443?encryption=$enc_vless&security=tls&sni=$argo_vl_host&type=ws&host=$argo_vl_host&path=${vless_ws_path_uri}#sbd-vless-argo" >> "$file"

  append_argo_cdn_templates "$file" "$uuid" "$argo_domain" "$vl_enable" "$enc_vless"
}
