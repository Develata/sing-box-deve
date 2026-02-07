#!/usr/bin/env bash

install_cloudflared_binary() {
  local arch
  arch="$(get_arch)"
  local asset="cloudflared-linux-amd64"
  [[ "$arch" == "arm64" ]] && asset="cloudflared-linux-arm64"

  local tag
  tag="$(fetch_latest_release_tag "cloudflare/cloudflared")"
  [[ -n "$tag" && "$tag" != "null" ]] || die "Unable to fetch latest cloudflared release"

  local url sha_url
  url="$(fetch_release_asset_url "cloudflare/cloudflared" "$tag" "$asset")"
  sha_url="$(fetch_release_asset_url "cloudflare/cloudflared" "$tag" "${asset}.sha256")"
  [[ -n "$url" ]] || die "Unable to locate cloudflared asset ${asset}"
  [[ -n "$sha_url" ]] || die "Unable to locate cloudflared sha256 asset"

  local bin_out sha_out
  bin_out="${SBD_BIN_DIR}/cloudflared"
  sha_out="${SBD_RUNTIME_DIR}/${asset}.sha256"

  download_file "$url" "$bin_out"
  chmod 0755 "$bin_out"
  download_file "$sha_url" "$sha_out"

  local expected actual
  expected="$(awk '{print $1}' "$sha_out" | head -n1)"
  actual="$(sha256sum "$bin_out" | awk '{print $1}')"
  [[ "$expected" == "$actual" ]] || die "Checksum mismatch for cloudflared"
}

configure_argo_tunnel() {
  local protocols_csv="$1"
  local protocols=()
  protocols_to_array "$protocols_csv" protocols
  if ! protocol_enabled "argo" "${protocols[@]}"; then
    return 0
  fi

  if ! protocol_enabled "vmess-ws" "${protocols[@]}" && ! protocol_enabled "vless-ws" "${protocols[@]}"; then
    die "Argo requires vmess-ws or vless-ws protocol"
  fi

  install_cloudflared_binary

  local target_port="8443"
  protocol_enabled "vless-ws" "${protocols[@]}" && target_port="8444"

  local mode="${ARGO_MODE:-temp}"
  local token="${ARGO_TOKEN:-}"
  local domain="${ARGO_DOMAIN:-}"
  local argo_log="${SBD_DATA_DIR}/argo.log"

  if [[ "$mode" == "off" ]]; then
    die "Protocol 'argo' enabled but ARGO_MODE is off; use --argo temp or --argo fixed"
  fi

  if [[ "$mode" == "fixed" && -z "$token" ]]; then
    die "Argo fixed mode requires ARGO_TOKEN or --argo-token"
  fi

  local exec_cmd
  if [[ "$mode" == "fixed" ]]; then
    exec_cmd="${SBD_BIN_DIR}/cloudflared tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token ${token}"
  else
    mode="temp"
    exec_cmd="${SBD_BIN_DIR}/cloudflared tunnel --url http://127.0.0.1:${target_port} --edge-ip-version auto --no-autoupdate --protocol http2"
  fi

  cat > "$SBD_ARGO_SERVICE_FILE" <<EOF
[Unit]
Description=sing-box-deve argo tunnel
After=network.target sing-box-deve.service
Requires=sing-box-deve.service

[Service]
Type=simple
ExecStart=${exec_cmd}
StandardOutput=append:${argo_log}
StandardError=append:${argo_log}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable sing-box-deve-argo.service >/dev/null
  systemctl restart sing-box-deve-argo.service

  echo "$mode" > "${SBD_DATA_DIR}/argo_mode"
  [[ -n "$domain" ]] && echo "$domain" > "${SBD_DATA_DIR}/argo_domain"

  if [[ "$mode" == "temp" ]]; then
    sleep 3
    local temp_domain
    temp_domain="$(grep -aEo 'https://[^ ]*trycloudflare.com' "$argo_log" | head -n1 | sed 's#https://##')"
    [[ -n "$temp_domain" ]] && echo "$temp_domain" > "${SBD_DATA_DIR}/argo_domain"
  fi
}
