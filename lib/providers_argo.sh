#!/usr/bin/env bash

install_cloudflared_binary() {
  local arch
  arch="$(get_arch)"
  local asset="cloudflared-linux-amd64"
  [[ "$arch" == "arm64" ]] && asset="cloudflared-linux-arm64"

  local tag
  tag="$(fetch_latest_release_tag "cloudflare/cloudflared")"
  [[ -n "$tag" && "$tag" != "null" ]] || die "Unable to fetch latest cloudflared release"

  local url digest expected
  url="$(fetch_release_asset_url "cloudflare/cloudflared" "$tag" "$asset")"
  digest="$(fetch_release_asset_digest "cloudflare/cloudflared" "$tag" "$asset")"
  [[ -n "$url" ]] || die "Unable to locate cloudflared asset ${asset}"
  [[ "$digest" == sha256:* ]] || die "Unable to locate cloudflared sha256 digest metadata for ${asset}"
  expected="${digest#sha256:}"

  local bin_out
  bin_out="${SBD_BIN_DIR}/cloudflared"
  mkdir -p "$SBD_BIN_DIR"

  download_file "$url" "$bin_out"
  chmod 0755 "$bin_out"
  verify_sha256_expected "$bin_out" "$expected"
}

configure_argo_tunnel() {
  local protocols_csv="$1"
  local engine="${2:-sing-box}"
  local protocols=()
  protocols_to_array "$protocols_csv" protocols
  if [[ "${ARGO_MODE:-off}" == "off" ]]; then
    return 0
  fi

  if ! protocol_enabled "vless-ws" "${protocols[@]}"; then
    die "Argo requires vless-ws protocol"
  fi

  install_cloudflared_binary

  local target_port
  target_port="$(resolve_protocol_port_for_engine "$engine" "vless-ws")"

  local mode="${ARGO_MODE:-temp}"
  local token="${ARGO_TOKEN:-}"
  local domain="${ARGO_DOMAIN:-}"
  local argo_log="${SBD_DATA_DIR}/argo.log"

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
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=read-only
StandardOutput=append:${argo_log}
StandardError=append:${argo_log}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

  sbd_service_enable_and_start "sing-box-deve-argo" "$exec_cmd"

  echo "$mode" > "${SBD_DATA_DIR}/argo_mode"
  [[ -n "$domain" ]] && echo "$domain" > "${SBD_DATA_DIR}/argo_domain"

  if [[ "$mode" == "temp" ]]; then
    sleep 3
    local temp_domain
    temp_domain="$(grep -aEo 'https://[^ ]*trycloudflare.com' "$argo_log" | head -n1 | sed 's#https://##')"
    [[ -n "$temp_domain" ]] && echo "$temp_domain" > "${SBD_DATA_DIR}/argo_domain"
  fi
}
