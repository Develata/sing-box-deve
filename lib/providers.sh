#!/usr/bin/env bash

protocol_port_map() {
  local proto="$1"
  case "$proto" in
    vless-reality) echo "tcp:443" ;;
    vmess-ws) echo "tcp:8443" ;;
    vless-xhttp) echo "tcp:9443" ;;
    vless-ws) echo "tcp:8444" ;;
    shadowsocks-2022) echo "tcp:2443" ;;
    socks5) echo "tcp:1080" ;;
    hysteria2) echo "udp:8443" ;;
    tuic) echo "udp:10443" ;;
    anytls) echo "tcp:20443" ;;
    any-reality) echo "tcp:30443" ;;
    argo) echo "tcp:8080" ;;
    warp) echo "udp:51820" ;;
    trojan) echo "tcp:4433" ;;
    wireguard) echo "udp:51820" ;;
    *) die "No port map for protocol: $proto" ;;
  esac
}

protocol_needs_local_listener() {
  local proto="$1"
  case "$proto" in
    argo|warp) return 1 ;;
    *) return 0 ;;
  esac
}

validate_feature_modes() {
  case "${ARGO_MODE:-off}" in
    off|temp|fixed) ;;
    *) die "Invalid ARGO_MODE: ${ARGO_MODE}" ;;
  esac

  case "${WARP_MODE:-off}" in
    off|global) ;;
    *) die "Invalid WARP_MODE: ${WARP_MODE}" ;;
  esac
}

detect_public_ip() {
  local ip
  ip="$(curl -fsS4 --max-time 5 https://icanhazip.com 2>/dev/null || true)"
  ip="${ip//$'\n'/}"
  if [[ -z "$ip" ]]; then
    ip="$(curl -fsS6 --max-time 5 https://icanhazip.com 2>/dev/null || true)"
    ip="${ip//$'\n'/}"
  fi
  [[ -n "$ip" ]] || ip="YOUR_SERVER_IP"
  echo "$ip"
}

ensure_uuid() {
  local uuid_file="${SBD_DATA_DIR}/uuid"
  if [[ ! -f "$uuid_file" ]]; then
    uuidgen > "$uuid_file"
  fi
  cat "$uuid_file"
}

ensure_self_signed_cert() {
  local cert_file="${SBD_DATA_DIR}/cert.pem"
  local key_file="${SBD_DATA_DIR}/private.key"
  if [[ ! -f "$cert_file" || ! -f "$key_file" ]]; then
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
      -keyout "$key_file" -out "$cert_file" -subj "/CN=www.bing.com" >/dev/null 2>&1
  fi
}

fetch_latest_release_tag() {
  local repo="$1"
  curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" | jq -r '.tag_name'
}

fetch_release_asset_url() {
  local repo="$1"
  local tag="$2"
  local asset_name="$3"
  curl -fsSL "https://api.github.com/repos/${repo}/releases/tags/${tag}" | jq -r \
    --arg name "$asset_name" '.assets[] | select(.name==$name) | .browser_download_url' | head -n1
}

verify_sha256_from_checksums_file() {
  local archive="$1"
  local checksums_file="$2"
  local filename
  filename="$(basename "$archive")"

  local expected
  expected="$(grep -F "${filename}" "$checksums_file" | awk '{print $1}' | head -n1)"
  [[ -n "$expected" ]] || die "Missing checksum entry for ${filename}"

  local actual
  actual="$(sha256sum "$archive" | awk '{print $1}')"
  [[ "$expected" == "$actual" ]] || die "Checksum mismatch for ${filename}"
}

verify_sha256_from_xray_dgst() {
  local archive="$1"
  local dgst_file="$2"
  local expected
  expected="$(awk '/SHA256/{print $NF}' "$dgst_file" | head -n1)"
  [[ -n "$expected" ]] || die "Unable to parse SHA256 from xray dgst"

  local actual
  actual="$(sha256sum "$archive" | awk '{print $1}')"
  [[ "$expected" == "$actual" ]] || die "Checksum mismatch for $(basename "$archive")"
}

install_sing_box_binary() {
  local arch
  arch="$(get_arch)"
  local tag
  tag="$(fetch_latest_release_tag "SagerNet/sing-box")"
  [[ -n "$tag" && "$tag" != "null" ]] || die "Unable to fetch latest sing-box release"

  local version="${tag#v}"
  local filename="sing-box-${version}-linux-${arch}.tar.gz"
  local url="https://github.com/SagerNet/sing-box/releases/download/${tag}/${filename}"
  local archive="${SBD_RUNTIME_DIR}/${filename}"
  local sums_file="${SBD_RUNTIME_DIR}/sing-box-${version}-checksums.txt"

  log_info "Installing sing-box ${tag}"
  download_file "$url" "$archive"
  download_file "https://github.com/SagerNet/sing-box/releases/download/${tag}/sing-box-${version}-checksums.txt" "$sums_file"
  verify_sha256_from_checksums_file "$archive" "$sums_file"
  tar -xzf "$archive" -C "$SBD_RUNTIME_DIR"
  install -m 0755 "${SBD_RUNTIME_DIR}/sing-box-${version}-linux-${arch}/sing-box" "${SBD_BIN_DIR}/sing-box"

  echo "$tag" > "${SBD_DATA_DIR}/engine-version"
}

install_xray_binary() {
  local arch
  arch="$(get_arch)"
  local x_arch="64"
  [[ "$arch" == "arm64" ]] && x_arch="arm64-v8a"

  local tag
  tag="$(fetch_latest_release_tag "XTLS/Xray-core")"
  [[ -n "$tag" && "$tag" != "null" ]] || die "Unable to fetch latest xray release"

  local filename="Xray-linux-${x_arch}.zip"
  local url="https://github.com/XTLS/Xray-core/releases/download/${tag}/${filename}"
  local archive="${SBD_RUNTIME_DIR}/${filename}"
  local dgst="${SBD_RUNTIME_DIR}/${filename}.dgst"

  log_info "Installing xray ${tag}"
  download_file "$url" "$archive"
  download_file "https://github.com/XTLS/Xray-core/releases/download/${tag}/${filename}.dgst" "$dgst"
  verify_sha256_from_xray_dgst "$archive" "$dgst"
  if ! command -v unzip >/dev/null 2>&1; then
    apt-get install -y unzip >/dev/null
  fi
  unzip -o "$archive" xray -d "$SBD_RUNTIME_DIR" >/dev/null
  install -m 0755 "${SBD_RUNTIME_DIR}/xray" "${SBD_BIN_DIR}/xray"

  echo "$tag" > "${SBD_DATA_DIR}/engine-version"
}

engine_supports_protocol() {
  local engine="$1"
  local protocol="$2"

  case "$engine" in
    sing-box)
      case "$protocol" in
        vless-reality|vmess-ws|vless-ws|shadowsocks-2022|socks5|hysteria2|tuic|trojan|wireguard|argo|warp|anytls|any-reality) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    xray)
      case "$protocol" in
        vless-reality|vmess-ws|vless-ws|vless-xhttp|socks5|trojan|argo) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    *) return 1 ;;
  esac
}

build_warp_outbound_singbox() {
  local private_key="${WARP_PRIVATE_KEY:-}"
  local peer_public_key="${WARP_PEER_PUBLIC_KEY:-}"
  local local_v4="${WARP_LOCAL_V4:-172.16.0.2/32}"
  local local_v6="${WARP_LOCAL_V6:-2606:4700:110:876d:4d3c:4206:c90c:6bd0/128}"
  local reserved="${WARP_RESERVED:-[0,0,0]}"

  [[ -n "$private_key" ]] || die "WARP_PRIVATE_KEY is required when warp protocol is enabled"
  [[ -n "$peer_public_key" ]] || die "WARP_PEER_PUBLIC_KEY is required when warp protocol is enabled"

  cat <<EOF
    {"type": "wireguard", "tag": "warp-out", "server": "engage.cloudflareclient.com", "server_port": 2408, "local_address": ["${local_v4}", "${local_v6}"], "private_key": "${private_key}", "peer_public_key": "${peer_public_key}", "reserved": ${reserved}, "mtu": 1280}
EOF
}

assert_engine_protocol_compatibility() {
  local engine="$1"
  local protocols_csv="$2"
  local protocols=()
  protocols_to_array "$protocols_csv" protocols

  if protocol_enabled "vmess-ws" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "type": "vmess",\n'
    inbounds+=$'      "tag": "vmess-ws",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+=$'      "listen_port": 8443,\n'
    inbounds+=$'      "users": [{"uuid": "'"${uuid}"'"}],\n'
    inbounds+=$'      "transport": {"type": "ws", "path": "/vmess"}\n'
    inbounds+=$'    }'
  fi

  if protocol_enabled "vless-xhttp" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "tag": "vless-xhttp",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+=$'      "port": 9443,\n'
    inbounds+=$'      "protocol": "vless",\n'
    inbounds+=$'      "settings": {"clients": [{"id": "'"${uuid}"'", "flow": "xtls-rprx-vision"}], "decryption": "none"},\n'
    inbounds+=$'      "streamSettings": {\n'
    inbounds+=$'        "network": "xhttp",\n'
    inbounds+=$'        "security": "reality",\n'
    inbounds+=$'        "realitySettings": {"show": false, "dest": "apple.com:443", "xver": 0, "serverNames": ["apple.com"], "privateKey": "'"${private_key}"'", "shortIds": ["'"${short_id}"'"]},\n'
    inbounds+=$'        "xhttpSettings": {"path": "/'"${uuid}"'-xh", "mode": "auto"}\n'
    inbounds+=$'      }\n'
    inbounds+=$'    }'
  fi

  if protocol_enabled "vless-ws" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "type": "vless",\n'
    inbounds+=$'      "tag": "vless-ws",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+=$'      "listen_port": 8444,\n'
    inbounds+=$'      "users": [{"uuid": "'"${uuid}"'"}],\n'
    inbounds+=$'      "transport": {"type": "ws", "path": "/vless"}\n'
    inbounds+=$'    }'
  fi

  if protocol_enabled "shadowsocks-2022" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "type": "shadowsocks",\n'
    inbounds+=$'      "tag": "ss-2022",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+=$'      "listen_port": 2443,\n'
    inbounds+=$'      "method": "2022-blake3-aes-128-gcm",\n'
    inbounds+=$'      "password": "'"${uuid}"'"\n'
    inbounds+=$'    }'
  fi

  if protocol_enabled "socks5" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "type": "socks",\n'
    inbounds+=$'      "tag": "socks5",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+=$'      "listen_port": 1080,\n'
    inbounds+=$'      "users": [{"username": "sbd", "password": "'"${uuid}"'"}]\n'
    inbounds+=$'    }'
  fi
  local p
  for p in "${protocols[@]}"; do
    engine_supports_protocol "$engine" "$p" || die "Protocol '${p}' is not implemented for engine '${engine}' yet"
  done
}

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

install_engine_binary() {
  local engine="$1"
  case "$engine" in
    sing-box) install_sing_box_binary ;;
    xray) install_xray_binary ;;
    *) die "Unsupported engine: $engine" ;;
  esac
}

generate_reality_keys() {
  local private_key_file="${SBD_DATA_DIR}/reality_private.key"
  local public_key_file="${SBD_DATA_DIR}/reality_public.key"
  local short_id_file="${SBD_DATA_DIR}/reality_short_id"

  if [[ -f "$private_key_file" && -f "$public_key_file" && -f "$short_id_file" ]]; then
    return 0
  fi

  local out
  out="$(${SBD_BIN_DIR}/sing-box generate reality-keypair)"
  echo "$out" | awk -F': ' '/PrivateKey/{print $2}' > "$private_key_file"
  echo "$out" | awk -F': ' '/PublicKey/{print $2}' > "$public_key_file"
  openssl rand -hex 4 > "$short_id_file"
}

build_sing_box_config() {
  local protocols_csv="$1"
  local config_file="${SBD_CONFIG_DIR}/sing-box.json"
  local uuid
  uuid="$(ensure_uuid)"
  ensure_self_signed_cert
  generate_reality_keys

  local private_key public_key short_id
  private_key="$(<"${SBD_DATA_DIR}/reality_private.key")"
  public_key="$(<"${SBD_DATA_DIR}/reality_public.key")"
  short_id="$(<"${SBD_DATA_DIR}/reality_short_id")"

  local inbounds=""
  inbounds+=$'    {\n'
  inbounds+=$'      "type": "vless",\n'
  inbounds+=$'      "tag": "vless-reality",\n'
  inbounds+=$'      "listen": "::",\n'
  inbounds+=$'      "listen_port": 443,\n'
  inbounds+=$'      "users": [{"uuid": "'"${uuid}"'", "flow": "xtls-rprx-vision"}],\n'
  inbounds+=$'      "tls": {\n'
  inbounds+=$'        "enabled": true,\n'
  inbounds+=$'        "server_name": "apple.com",\n'
  inbounds+=$'        "reality": {\n'
  inbounds+=$'          "enabled": true,\n'
  inbounds+=$'          "handshake": {"server": "apple.com", "server_port": 443},\n'
  inbounds+=$'          "private_key": "'"${private_key}"'",\n'
  inbounds+=$'          "short_id": ["'"${short_id}"'"]\n'
  inbounds+=$'        }\n'
  inbounds+=$'      }\n'
  inbounds+=$'    }'

  local protocols=()
  protocols_to_array "$protocols_csv" protocols

  local has_warp="false"
  if protocol_enabled "warp" "${protocols[@]}"; then
    if [[ "${WARP_MODE:-off}" == "global" ]]; then
      has_warp="true"
    else
      log_warn "Protocol 'warp' enabled but WARP_MODE is '${WARP_MODE:-off}', warp outbound disabled"
    fi
  fi

  if protocol_enabled "hysteria2" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "type": "hysteria2",\n'
    inbounds+=$'      "tag": "hy2",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+=$'      "listen_port": 8443,\n'
    inbounds+=$'      "users": [{"password": "'"${uuid}"'"}],\n'
    inbounds+=$'      "tls": {\n'
    inbounds+=$'        "enabled": true,\n'
    inbounds+=$'        "server_name": "www.bing.com",\n'
    inbounds+=$'        "certificate_path": "'"${SBD_DATA_DIR}/cert.pem"'",\n'
    inbounds+=$'        "key_path": "'"${SBD_DATA_DIR}/private.key"'"\n'
    inbounds+=$'      }\n'
    inbounds+=$'    }'
  fi

  if protocol_enabled "tuic" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "type": "tuic",\n'
    inbounds+=$'      "tag": "tuic",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+=$'      "listen_port": 10443,\n'
    inbounds+=$'      "users": [{"uuid": "'"${uuid}"'", "password": "'"${uuid}"'"}],\n'
    inbounds+=$'      "congestion_control": "bbr",\n'
    inbounds+=$'      "tls": {\n'
    inbounds+=$'        "enabled": true,\n'
    inbounds+=$'        "server_name": "www.bing.com",\n'
    inbounds+=$'        "certificate_path": "'"${SBD_DATA_DIR}/cert.pem"'",\n'
    inbounds+=$'        "key_path": "'"${SBD_DATA_DIR}/private.key"'"\n'
    inbounds+=$'      }\n'
    inbounds+=$'    }'
  fi

  if protocol_enabled "trojan" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "type": "trojan",\n'
    inbounds+=$'      "tag": "trojan",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+=$'      "listen_port": 4433,\n'
    inbounds+=$'      "users": [{"password": "'"${uuid}"'"}],\n'
    inbounds+=$'      "tls": {\n'
    inbounds+=$'        "enabled": true,\n'
    inbounds+=$'        "server_name": "www.bing.com",\n'
    inbounds+=$'        "certificate_path": "'"${SBD_DATA_DIR}/cert.pem"'",\n'
    inbounds+=$'        "key_path": "'"${SBD_DATA_DIR}/private.key"'"\n'
    inbounds+=$'      }\n'
    inbounds+=$'    }'
  fi

  if protocol_enabled "anytls" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "type": "anytls",\n'
    inbounds+=$'      "tag": "anytls",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+=$'      "listen_port": 20443,\n'
    inbounds+=$'      "users": [{"password": "'"${uuid}"'"}],\n'
    inbounds+=$'      "padding_scheme": [],\n'
    inbounds+=$'      "tls": {\n'
    inbounds+=$'        "enabled": true,\n'
    inbounds+=$'        "certificate_path": "'"${SBD_DATA_DIR}/cert.pem"'",\n'
    inbounds+=$'        "key_path": "'"${SBD_DATA_DIR}/private.key"'"\n'
    inbounds+=$'      }\n'
    inbounds+=$'    }'
  fi

  if protocol_enabled "any-reality" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "type": "anytls",\n'
    inbounds+=$'      "tag": "any-reality",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+=$'      "listen_port": 30443,\n'
    inbounds+=$'      "users": [{"password": "'"${uuid}"'"}],\n'
    inbounds+=$'      "padding_scheme": [],\n'
    inbounds+=$'      "tls": {\n'
    inbounds+=$'        "enabled": true,\n'
    inbounds+=$'        "server_name": "apple.com",\n'
    inbounds+=$'        "reality": {\n'
    inbounds+=$'          "enabled": true,\n'
    inbounds+=$'          "handshake": {"server": "apple.com", "server_port": 443},\n'
    inbounds+=$'          "private_key": "'"${private_key}"'",\n'
    inbounds+=$'          "short_id": ["'"${short_id}"'"]\n'
    inbounds+=$'        }\n'
    inbounds+=$'      }\n'
    inbounds+=$'    }'
  fi

  if protocol_enabled "wireguard" "${protocols[@]}"; then
    local wg_private wg_public
    if [[ ! -f "${SBD_DATA_DIR}/wg_private.key" ]]; then
      wg_private="$(wg genkey)"
      wg_public="$(printf '%s' "$wg_private" | wg pubkey)"
      echo "$wg_private" > "${SBD_DATA_DIR}/wg_private.key"
      echo "$wg_public" > "${SBD_DATA_DIR}/wg_public.key"
    fi
    wg_private="$(<"${SBD_DATA_DIR}/wg_private.key")"
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "type": "wireguard",\n'
    inbounds+=$'      "tag": "wireguard",\n'
    inbounds+=$'      "listen_port": 51820,\n'
    inbounds+=$'      "address": ["10.66.66.1/24"],\n'
    inbounds+=$'      "private_key": "'"${wg_private}"'",\n'
    inbounds+=$'      "peers": []\n'
    inbounds+=$'    }'
  fi

  local outbounds
  local final_tag="direct"
  outbounds=$'    {"type": "direct", "tag": "direct"},\n'
  outbounds+=$'    {"type": "block", "tag": "block"}'
  if [[ "$has_warp" == "true" ]]; then
    outbounds+=$',\n'
    outbounds+="$(build_warp_outbound_singbox)"
    if [[ "${WARP_MODE:-off}" == "global" ]]; then
      final_tag="warp-out"
    fi
  fi

  cat > "$config_file" <<EOF
{
  "log": {"level": "info"},
  "inbounds": [
${inbounds}
  ],
  "outbounds": [
${outbounds}
  ],
  "route": {
    "final": "${final_tag}"
  }
}
EOF

  echo "$public_key" > "${SBD_DATA_DIR}/reality_public.key"
}

build_xray_config() {
  local protocols_csv="$1"
  local config_file="${SBD_CONFIG_DIR}/xray.json"
  local uuid
  uuid="$(ensure_uuid)"
  local private_key public_key short_id

  if [[ ! -f "${SBD_DATA_DIR}/xray_private.key" ]]; then
    local out
    out="$(${SBD_BIN_DIR}/xray x25519)"
    echo "$out" | awk '/Private key/{print $3}' > "${SBD_DATA_DIR}/xray_private.key"
    echo "$out" | awk '/Public key/{print $3}' > "${SBD_DATA_DIR}/xray_public.key"
    openssl rand -hex 4 > "${SBD_DATA_DIR}/xray_short_id"
  fi

  private_key="$(<"${SBD_DATA_DIR}/xray_private.key")"
  public_key="$(<"${SBD_DATA_DIR}/xray_public.key")"
  short_id="$(<"${SBD_DATA_DIR}/xray_short_id")"

  local inbounds=""
  inbounds+=$'    {\n'
  inbounds+=$'      "tag": "vless-reality",\n'
  inbounds+=$'      "listen": "::",\n'
  inbounds+=$'      "port": 443,\n'
  inbounds+=$'      "protocol": "vless",\n'
  inbounds+=$'      "settings": {\n'
  inbounds+=$'        "clients": [{"id": "'"${uuid}"'", "flow": "xtls-rprx-vision"}],\n'
  inbounds+=$'        "decryption": "none"\n'
  inbounds+=$'      },\n'
  inbounds+=$'      "streamSettings": {\n'
  inbounds+=$'        "network": "tcp",\n'
  inbounds+=$'        "security": "reality",\n'
  inbounds+=$'        "realitySettings": {\n'
  inbounds+=$'          "show": false,\n'
  inbounds+=$'          "dest": "apple.com:443",\n'
  inbounds+=$'          "xver": 0,\n'
  inbounds+=$'          "serverNames": ["apple.com"],\n'
  inbounds+=$'          "privateKey": "'"${private_key}"'",\n'
  inbounds+=$'          "shortIds": ["'"${short_id}"'"]\n'
  inbounds+=$'        }\n'
  inbounds+=$'      }\n'
  inbounds+=$'    }'

  local protocols=()
  protocols_to_array "$protocols_csv" protocols

  if protocol_enabled "vmess-ws" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "tag": "vmess-ws",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+=$'      "port": 8443,\n'
    inbounds+=$'      "protocol": "vmess",\n'
    inbounds+=$'      "settings": {"clients": [{"id": "'"${uuid}"'"}]},\n'
    inbounds+=$'      "streamSettings": {"network": "ws", "wsSettings": {"path": "/vmess"}}\n'
    inbounds+=$'    }'
  fi

  if protocol_enabled "vless-ws" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "tag": "vless-ws",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+=$'      "port": 8444,\n'
    inbounds+=$'      "protocol": "vless",\n'
    inbounds+=$'      "settings": {"clients": [{"id": "'"${uuid}"'"}], "decryption": "none"},\n'
    inbounds+=$'      "streamSettings": {"network": "ws", "wsSettings": {"path": "/vless"}}\n'
    inbounds+=$'    }'
  fi

  if protocol_enabled "trojan" "${protocols[@]}"; then
    ensure_self_signed_cert
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "tag": "trojan",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+=$'      "port": 4433,\n'
    inbounds+=$'      "protocol": "trojan",\n'
    inbounds+=$'      "settings": {"clients": [{"password": "'"${uuid}"'"}]},\n'
    inbounds+=$'      "streamSettings": {\n'
    inbounds+=$'        "security": "tls",\n'
    inbounds+=$'        "tlsSettings": {"certificates": [{"certificateFile": "'"${SBD_DATA_DIR}/cert.pem"'", "keyFile": "'"${SBD_DATA_DIR}/private.key"'"}]}\n'
    inbounds+=$'      }\n'
    inbounds+=$'    }'
  fi

  if protocol_enabled "socks5" "${protocols[@]}"; then
    inbounds+=$',\n'
    inbounds+=$'    {\n'
    inbounds+=$'      "tag": "socks5",\n'
    inbounds+=$'      "listen": "::",\n'
    inbounds+=$'      "port": 1080,\n'
    inbounds+=$'      "protocol": "socks",\n'
    inbounds+=$'      "settings": {"auth": "password", "accounts": [{"user": "sbd", "pass": "'"${uuid}"'"}]}\n'
    inbounds+=$'    }'
  fi

  cat > "$config_file" <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [
${inbounds}
  ],
  "outbounds": [
    {"protocol": "freedom", "tag": "direct"},
    {"protocol": "blackhole", "tag": "block"}
  ]
}
EOF

  echo "$public_key" > "${SBD_DATA_DIR}/xray_public.key"
}

write_systemd_service() {
  local engine="$1"
  local config_path
  local binary_path
  local exec_args

  case "$engine" in
    sing-box)
      config_path="${SBD_CONFIG_DIR}/sing-box.json"
      binary_path="${SBD_BIN_DIR}/sing-box"
      exec_args="run -c ${config_path}"
      ;;
    xray)
      config_path="${SBD_CONFIG_DIR}/xray.json"
      binary_path="${SBD_BIN_DIR}/xray"
      exec_args="run -config ${config_path}"
      ;;
    *) die "Unsupported engine for service: $engine" ;;
  esac

  cat > "$SBD_SERVICE_FILE" <<EOF
[Unit]
Description=sing-box-deve core service
After=network.target

[Service]
Type=simple
ExecStart=${binary_path} ${exec_args}
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  systemd_reload_and_enable
  safe_service_restart
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

provider_install() {
  local provider="$1"
  local profile="$2"
  local engine="$3"
  local protocols_csv="$4"

  case "$provider" in
    vps)
      provider_vps_install "$profile" "$engine" "$protocols_csv"
      ;;
    serv00)
      provider_serv00_install "$profile" "$engine" "$protocols_csv"
      ;;
    sap)
      provider_sap_install "$profile" "$engine" "$protocols_csv"
      ;;
    docker)
      provider_docker_install "$profile" "$engine" "$protocols_csv"
      ;;
    *)
      die "Unsupported provider: $provider"
      ;;
  esac
}

provider_vps_install() {
  local profile="$1"
  local engine="$2"
  local protocols_csv="$3"

  log_info "Installing for provider=vps profile=${profile} engine=${engine}"
  install_apt_dependencies
  validate_feature_modes
  assert_engine_protocol_compatibility "$engine" "$protocols_csv"

  local protocols=()
  protocols_to_array "$protocols_csv" protocols
  local protocol mapping proto port
  for protocol in "${protocols[@]}"; do
    if [[ "$protocol" == "argo" || "$protocol" == "warp" ]]; then
      continue
    fi
    mapping="$(protocol_port_map "$protocol")"
    proto="${mapping%%:*}"
    port="${mapping##*:}"
    fw_apply_rule "$proto" "$port"
  done

  install_engine_binary "$engine"

  case "$engine" in
    sing-box) build_sing_box_config "$protocols_csv" ;;
    xray) build_xray_config "$protocols_csv" ;;
  esac

  write_systemd_service "$engine"
  configure_argo_tunnel "$protocols_csv"
  write_nodes_output "$engine" "$protocols_csv"

  mkdir -p /etc/sing-box-deve
  cat > /etc/sing-box-deve/runtime.env <<EOF
provider=vps
profile=${profile}
engine=${engine}
protocols=${protocols_csv}
argo_mode=${ARGO_MODE:-off}
warp_mode=${WARP_MODE:-off}
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

  log_success "VPS provider setup complete"
}

validate_serv00_accounts_json() {
  local json="$1"
  echo "$json" | jq -e . >/dev/null 2>&1 || die "SERV00_ACCOUNTS_JSON is not valid JSON"
  echo "$json" | jq -e 'type=="array"' >/dev/null 2>&1 || die "SERV00_ACCOUNTS_JSON must be a JSON array"
  echo "$json" | jq -e 'length>0' >/dev/null 2>&1 || die "SERV00_ACCOUNTS_JSON array cannot be empty"

  local idx=0
  while IFS= read -r item; do
    idx=$((idx + 1))
    [[ "$(echo "$item" | jq -r 'type')" == "object" ]] || die "SERV00_ACCOUNTS_JSON item #${idx} must be an object"
    for required_key in host user pass; do
      if [[ -z "$(echo "$item" | jq -r --arg k "$required_key" '.[$k] // empty')" ]]; then
        die "SERV00_ACCOUNTS_JSON item #${idx} missing required key '${required_key}'"
      fi
    done
  done < <(echo "$json" | jq -c '.[]')
}

validate_sap_accounts_json() {
  local json="$1"
  echo "$json" | jq -e . >/dev/null 2>&1 || die "SAP_ACCOUNTS_JSON is not valid JSON"
  echo "$json" | jq -e 'type=="array"' >/dev/null 2>&1 || die "SAP_ACCOUNTS_JSON must be a JSON array"
  echo "$json" | jq -e 'length>0' >/dev/null 2>&1 || die "SAP_ACCOUNTS_JSON array cannot be empty"

  local idx=0
  while IFS= read -r item; do
    idx=$((idx + 1))
    [[ "$(echo "$item" | jq -r 'type')" == "object" ]] || die "SAP_ACCOUNTS_JSON item #${idx} must be an object"
    for required_key in api username password org space app_name; do
      if [[ -z "$(echo "$item" | jq -r --arg k "$required_key" '.[$k] // empty')" ]]; then
        die "SAP_ACCOUNTS_JSON item #${idx} missing required key '${required_key}'"
      fi
    done
  done < <(echo "$json" | jq -c '.[]')
}

provider_serv00_install() {
  local profile="$1"
  local engine="$2"
  local protocols_csv="$3"

  validate_feature_modes
  install_apt_dependencies
  mkdir -p /etc/sing-box-deve
  cat > /etc/sing-box-deve/serv00.env <<EOF
profile=${profile}
engine=${engine}
protocols=${protocols_csv}
argo_mode=${ARGO_MODE:-off}
warp_mode=${WARP_MODE:-off}
generated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

  if ! command -v sshpass >/dev/null 2>&1; then
    apt-get update -y >/dev/null
    apt-get install -y sshpass >/dev/null
  fi

  local remote_cmd
  remote_cmd="${SERV00_BOOTSTRAP_CMD:-bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/serv00.sh)}"

  if [[ -n "${SERV00_ACCOUNTS_JSON:-}" ]]; then
    if ! command -v jq >/dev/null 2>&1; then
      die "jq is required for SERV00_ACCOUNTS_JSON"
    fi
    validate_serv00_accounts_json "$SERV00_ACCOUNTS_JSON"
    local count=0
    while IFS= read -r item; do
      [[ -z "$item" ]] && continue
      local host user pass cmd
      host="$(echo "$item" | jq -r '.host // empty')"
      user="$(echo "$item" | jq -r '.user // empty')"
      pass="$(echo "$item" | jq -r '.pass // empty')"
      cmd="$(echo "$item" | jq -r '.cmd // empty')"
      [[ -n "$cmd" ]] || cmd="$remote_cmd"
      count=$((count + 1))
      log_info "Executing remote Serv00 bootstrap for account #${count} (${user}@${host})"
      if ! prompt_yes_no "$(msg "确认为 ${user}@${host} 执行远程 Serv00 引导吗？" "Confirm remote bootstrap for ${user}@${host}?")" "Y"; then
        log_warn "$(msg "用户已跳过 ${user}@${host}" "Skipped ${user}@${host} by user choice")"
        continue
      fi
      sshpass -p "$pass" ssh -o StrictHostKeyChecking=no "${user}@${host}" "$cmd" || \
        die "Remote Serv00 bootstrap failed for ${user}@${host}"
    done < <(echo "$SERV00_ACCOUNTS_JSON" | jq -c '.[]')
    log_success "Serv00 remote bootstrap completed for ${count} account(s)"
  elif [[ -n "${SERV00_HOST:-}" && -n "${SERV00_USER:-}" && -n "${SERV00_PASS:-}" ]]; then
    log_info "Executing remote Serv00 bootstrap on ${SERV00_HOST}"
    if ! prompt_yes_no "$(msg "确认为 ${SERV00_USER}@${SERV00_HOST} 执行远程 Serv00 引导吗？" "Confirm remote bootstrap for ${SERV00_USER}@${SERV00_HOST}?")" "Y"; then
      log_warn "$(msg "用户取消了 Serv00 远程引导" "Serv00 remote bootstrap cancelled by user")"
      return 0
    fi
    sshpass -p "${SERV00_PASS}" ssh -o StrictHostKeyChecking=no "${SERV00_USER}@${SERV00_HOST}" "$remote_cmd" || \
      die "Remote Serv00 bootstrap failed"
    log_success "Serv00 remote bootstrap completed"
  else
    log_warn "SERV00 credentials not set; generated local bundle only"
  fi

  cat > /etc/sing-box-deve/serv00-run.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ -z "${SERV00_HOST:-}" ] || [ -z "${SERV00_USER:-}" ] || [ -z "${SERV00_PASS:-}" ]; then
  echo "Please export SERV00_HOST SERV00_USER SERV00_PASS first"
  exit 1
fi

cmd="${SERV00_BOOTSTRAP_CMD:-bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/serv00.sh)}"
sshpass -p "${SERV00_PASS}" ssh -o StrictHostKeyChecking=no "${SERV00_USER}@${SERV00_HOST}" "${cmd}"
EOF
  chmod +x /etc/sing-box-deve/serv00-run.sh
  log_success "Serv00 deployment bundle generated at /etc/sing-box-deve/serv00.env and /etc/sing-box-deve/serv00-run.sh"
  return 0
}

provider_sap_install() {
  local profile="$1"
  local engine="$2"
  local protocols_csv="$3"

  validate_feature_modes
  mkdir -p /etc/sing-box-deve
  cat > /etc/sing-box-deve/sap.env <<EOF
profile=${profile}
engine=${engine}
protocols=${protocols_csv}
argo_mode=${ARGO_MODE:-off}
warp_mode=${WARP_MODE:-off}
generated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

  local sap_image
  sap_image="${SAP_DOCKER_IMAGE:-ygkkk/argosbx}"

  ensure_cf_cli() {
    if command -v cf >/dev/null 2>&1; then
      return 0
    fi
    local cf_tgz="${SBD_RUNTIME_DIR}/cf8-cli.tgz"
    download_file "https://github.com/cloudfoundry/cli/releases/download/v8.16.0/cf8-cli_8.16.0_linux_x86-64.tgz" "$cf_tgz"
    tar -xzf "$cf_tgz" -C "$SBD_RUNTIME_DIR"
    install -m 0755 "${SBD_RUNTIME_DIR}/cf8" /usr/local/bin/cf
  }

  deploy_single_sap() {
    local api="$1" username="$2" password="$3" org="$4" space="$5" app="$6" memory="$7" image="$8" uuid="$9"
    local agn="${10}" agk="${11}"
    [[ -n "$api" && -n "$username" && -n "$password" && -n "$org" && -n "$space" && -n "$app" ]] || \
      die "SAP single deployment parameters missing"

    cf login -a "$api" -u "$username" -p "$password" -o "$org" -s "$space" >/dev/null
    cf push "$app" --docker-image "$image" -m "$memory" --health-check-type port >/dev/null
    [[ -n "$uuid" ]] && cf set-env "$app" uuid "$uuid" >/dev/null
    [[ -n "$agn" ]] && cf set-env "$app" agn "$agn" >/dev/null
    if [[ -n "$agk" ]]; then
      cf set-env "$app" agk "$agk" >/dev/null
      cf set-env "$app" argo "y" >/dev/null
    fi
    cf restage "$app" >/dev/null
  }

  if [[ -n "${SAP_ACCOUNTS_JSON:-}" ]]; then
    ensure_cf_cli
    if ! command -v jq >/dev/null 2>&1; then
      die "jq is required for SAP_ACCOUNTS_JSON"
    fi
    validate_sap_accounts_json "$SAP_ACCOUNTS_JSON"
    local idx=0
    while IFS= read -r item; do
      [[ -z "$item" ]] && continue
      local api username password org space app memory image uuid agn agk
      api="$(echo "$item" | jq -r '.api // empty')"
      username="$(echo "$item" | jq -r '.username // empty')"
      password="$(echo "$item" | jq -r '.password // empty')"
      org="$(echo "$item" | jq -r '.org // empty')"
      space="$(echo "$item" | jq -r '.space // empty')"
      app="$(echo "$item" | jq -r '.app_name // empty')"
      memory="$(echo "$item" | jq -r '.memory // "512M"')"
      image="$(echo "$item" | jq -r '.image // "'"${sap_image}"'"')"
      uuid="$(echo "$item" | jq -r '.uuid // empty')"
      agn="$(echo "$item" | jq -r '.agn // empty')"
      agk="$(echo "$item" | jq -r '.agk // empty')"
      idx=$((idx + 1))
      log_info "Deploying SAP account #${idx}: app=${app}"
      if ! prompt_yes_no "$(msg "确认部署 SAP 应用 '${app}'（账号 #${idx}）吗？" "Confirm SAP deploy for app '${app}' (account #${idx})?")" "Y"; then
        log_warn "$(msg "用户已跳过 SAP 应用 ${app}" "Skipped SAP app ${app} by user choice")"
        continue
      fi
      deploy_single_sap "$api" "$username" "$password" "$org" "$space" "$app" "$memory" "$image" "$uuid" "$agn" "$agk"
    done < <(echo "$SAP_ACCOUNTS_JSON" | jq -c '.[]')
    log_success "SAP deployment completed for ${idx} account(s)"
  elif [[ -n "${SAP_CF_API:-}" && -n "${SAP_CF_USERNAME:-}" && -n "${SAP_CF_PASSWORD:-}" && -n "${SAP_CF_ORG:-}" && -n "${SAP_CF_SPACE:-}" && -n "${SAP_APP_NAME:-}" ]]; then
    ensure_cf_cli
    log_info "Deploying single SAP app: ${SAP_APP_NAME}"
    if ! prompt_yes_no "$(msg "确认部署 SAP 应用 '${SAP_APP_NAME}' 吗？" "Confirm SAP deploy for app '${SAP_APP_NAME}'?")" "Y"; then
      log_warn "$(msg "用户取消了 SAP 部署" "SAP deployment cancelled by user")"
      return 0
    fi
    deploy_single_sap "${SAP_CF_API}" "${SAP_CF_USERNAME}" "${SAP_CF_PASSWORD}" "${SAP_CF_ORG}" "${SAP_CF_SPACE}" "${SAP_APP_NAME}" "${SAP_APP_MEMORY:-512M}" "${sap_image}" "${SAP_UUID:-}" "${ARGO_DOMAIN:-}" "${ARGO_TOKEN:-}"
    log_success "SAP deployment completed"
  else
    log_warn "SAP credentials not fully set; generated templates only"
  fi

  cat > /etc/sing-box-deve/sap-github-workflow.yml <<'EOF'
name: SAP Deploy
on:
  workflow_dispatch:
jobs:
  deploy:
    runs-on: ubuntu-latest
    env:
      SAP_CF_API: ${{ secrets.SAP_CF_API }}
      SAP_CF_USERNAME: ${{ secrets.SAP_CF_USERNAME }}
      SAP_CF_PASSWORD: ${{ secrets.SAP_CF_PASSWORD }}
      SAP_CF_ORG: ${{ secrets.SAP_CF_ORG }}
      SAP_CF_SPACE: ${{ secrets.SAP_CF_SPACE }}
      SAP_APP_NAME: ${{ secrets.SAP_APP_NAME }}
    steps:
      - uses: actions/checkout@v4
      - name: Install CF CLI
        run: |
          wget -q https://github.com/cloudfoundry/cli/releases/download/v8.16.0/cf8-cli_8.16.0_linux_x86-64.tgz
          tar -xzf cf8-cli_8.16.0_linux_x86-64.tgz
          sudo mv cf8 /usr/local/bin/cf
      - name: Deploy
        run: |
          cf login -a "$SAP_CF_API" -u "$SAP_CF_USERNAME" -p "$SAP_CF_PASSWORD" -o "$SAP_CF_ORG" -s "$SAP_CF_SPACE"
          cf push "$SAP_APP_NAME" --docker-image ${SAP_DOCKER_IMAGE:-ygkkk/argosbx} -m 512M --health-check-type port
EOF
  log_success "SAP deployment templates generated under /etc/sing-box-deve"
  return 0
}

provider_docker_install() {
  local profile="$1"
  local engine="$2"
  local protocols_csv="$3"

  validate_feature_modes
  mkdir -p /etc/sing-box-deve
  local docker_image
  docker_image="${SBD_DOCKER_IMAGE:-ghcr.io/sing-box-deve/sing-box-deve:latest}"

  cat > /etc/sing-box-deve/docker.env <<EOF
PROFILE=${profile}
ENGINE=${engine}
PROTOCOLS=${protocols_csv}
ARGO_MODE=${ARGO_MODE:-off}
ARGO_DOMAIN=${ARGO_DOMAIN:-}
ARGO_TOKEN=${ARGO_TOKEN:-}
WARP_MODE=${WARP_MODE:-off}
WARP_PRIVATE_KEY=${WARP_PRIVATE_KEY:-}
WARP_PEER_PUBLIC_KEY=${WARP_PEER_PUBLIC_KEY:-}
EOF
  cat > /etc/sing-box-deve/docker-compose.yml <<EOF
services:
  sing-box-deve:
    image: ${docker_image}
    container_name: sing-box-deve
    restart: unless-stopped
    env_file:
      - /etc/sing-box-deve/docker.env
    network_mode: host
EOF

  if command -v docker >/dev/null 2>&1; then
    if docker compose version >/dev/null 2>&1; then
      if prompt_yes_no "$(msg "现在启动 docker compose 部署吗？" "Start docker compose deployment now?")" "Y"; then
        docker compose -f /etc/sing-box-deve/docker-compose.yml up -d || die "docker compose up failed"
      else
        log_warn "$(msg "用户已跳过 docker compose 启动" "Docker compose start skipped by user")"
      fi
      log_success "Docker provider deployed via docker compose"
    else
      if prompt_yes_no "$(msg "现在通过 docker run 启动容器吗？" "Start docker container now (docker run)?")" "Y"; then
        docker run -d --name sing-box-deve --restart unless-stopped --network host --env-file /etc/sing-box-deve/docker.env "${docker_image}" || \
          log_warn "Docker run failed; verify image and env values"
      else
        log_warn "$(msg "用户已跳过 docker run 启动" "Docker run skipped by user")"
      fi
    fi
  else
    log_warn "Docker not installed; generated compose/env files only"
  fi

  cat > /etc/sing-box-deve/docker-run.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if command -v docker >/dev/null 2>&1; then
  if docker compose version >/dev/null 2>&1; then
    docker compose -f /etc/sing-box-deve/docker-compose.yml up -d
  else
    echo "docker compose not available, use docker run manually"
  fi
else
  echo "docker is not installed"
  exit 1
fi
EOF
  chmod +x /etc/sing-box-deve/docker-run.sh

  cat > /etc/sing-box-deve/docker-healthcheck.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if ! command -v docker >/dev/null 2>&1; then
  echo "docker not installed"
  exit 1
fi

docker ps --format '{{.Names}} {{.Status}}' | grep '^sing-box-deve ' || {
  echo "sing-box-deve container not running"
  exit 1
}

echo "sing-box-deve container is running"
EOF
  chmod +x /etc/sing-box-deve/docker-healthcheck.sh

  log_success "Docker deployment bundle generated at /etc/sing-box-deve/docker.env and docker-compose.yml"
  return 0
}

provider_list() {
  if [[ -f /etc/sing-box-deve/runtime.env ]]; then
    log_info "Current runtime state:"
    cat /etc/sing-box-deve/runtime.env
  else
    log_warn "No runtime state found"
  fi

  if [[ -f "$SBD_NODES_FILE" ]]; then
    echo
    log_info "Node links:"
    cat "$SBD_NODES_FILE"
  fi
}

provider_restart() {
  if [[ -f "$SBD_SERVICE_FILE" ]]; then
    safe_service_restart
    log_success "sing-box-deve service restarted"
  else
    log_warn "Service not installed"
  fi

  if [[ -f "$SBD_ARGO_SERVICE_FILE" ]]; then
    if systemctl is-active --quiet sing-box-deve-argo.service; then
      log_success "Argo service status: active"
    else
      log_warn "Argo service status: inactive"
    fi
  fi
  if [[ -f "$SBD_ARGO_SERVICE_FILE" ]]; then
    systemctl restart sing-box-deve-argo.service
    log_success "sing-box-deve argo service restarted"
  fi
}

provider_update() {
  if [[ ! -f /etc/sing-box-deve/runtime.env ]]; then
    die "No installed runtime found"
  fi

  # shellcheck disable=SC1091
  source /etc/sing-box-deve/runtime.env
  install_engine_binary "$engine"
  safe_service_restart
  if [[ -f "$SBD_ARGO_SERVICE_FILE" ]]; then
    systemctl restart sing-box-deve-argo.service
  fi
  log_success "Engine updated and service restarted"
}

provider_doctor() {
  if [[ -f "$SBD_SERVICE_FILE" ]]; then
    if systemctl is-active --quiet sing-box-deve.service; then
      log_success "Service status: active"
    else
      log_warn "Service status: inactive"
      systemctl status sing-box-deve.service --no-pager -l || true
    fi
  else
    log_warn "Service file not found: $SBD_SERVICE_FILE"
  fi

  if [[ -f /etc/sing-box-deve/runtime.env ]]; then
    log_info "Runtime state detected"
    # shellcheck disable=SC1091
    source /etc/sing-box-deve/runtime.env
    if [[ "${engine:-}" == "sing-box" && -f "${SBD_CONFIG_DIR}/sing-box.json" && -x "${SBD_BIN_DIR}/sing-box" ]]; then
      if "${SBD_BIN_DIR}/sing-box" check -c "${SBD_CONFIG_DIR}/sing-box.json" >/dev/null 2>&1; then
        log_success "sing-box config check passed"
      else
        log_warn "sing-box config check failed"
      fi
    elif [[ "${engine:-}" == "xray" && -f "${SBD_CONFIG_DIR}/xray.json" && -x "${SBD_BIN_DIR}/xray" ]]; then
      if "${SBD_BIN_DIR}/xray" run -test -config "${SBD_CONFIG_DIR}/xray.json" >/dev/null 2>&1; then
        log_success "xray config check passed"
      else
        log_warn "xray config check failed"
      fi
    fi

    if [[ "${protocols:-}" == *"argo"* ]]; then
      if [[ -f "$SBD_ARGO_SERVICE_FILE" ]]; then
        if systemctl is-active --quiet sing-box-deve-argo.service; then
          log_success "Argo diagnostic: service active"
        else
          log_warn "Argo diagnostic: service inactive"
        fi
      else
        log_warn "Argo diagnostic: service file missing"
      fi

      if [[ -f "${SBD_DATA_DIR}/argo_domain" ]]; then
        local adomain
        adomain="$(<"${SBD_DATA_DIR}/argo_domain")"
        if [[ -n "$adomain" ]]; then
          log_success "Argo diagnostic: domain detected (${adomain})"
        else
          log_warn "Argo diagnostic: domain file empty"
        fi
      else
        log_warn "Argo diagnostic: domain file missing"
      fi
    fi

    if [[ "${protocols:-}" == *"warp"* ]]; then
      if [[ "${warp_mode:-off}" != "global" ]]; then
        log_warn "WARP diagnostic: warp protocol enabled but warp_mode is not global"
      else
        if [[ -n "${WARP_PRIVATE_KEY:-}" && -n "${WARP_PEER_PUBLIC_KEY:-}" ]]; then
          log_success "WARP diagnostic: keys found in current environment"
        elif [[ -f "${SBD_CONFIG_DIR}/sing-box.json" ]] && grep -q '"tag": "warp-out"' "${SBD_CONFIG_DIR}/sing-box.json"; then
          log_success "WARP diagnostic: warp-out configured in sing-box.json"
        else
          log_warn "WARP diagnostic: warp keys not found in env and warp-out not detected"
        fi
      fi
    fi
  else
    log_warn "Runtime state file missing"
  fi

  if [[ -f "$SBD_NODES_FILE" ]]; then
    log_success "Node output file present: $SBD_NODES_FILE"
    local bad_nodes
    bad_nodes="$(awk '!/^(vless|vmess|hysteria2|trojan|wireguard|anytls|argo-domain|warp-mode):\/\//{print NR":"$0}' "$SBD_NODES_FILE" || true)"
    if [[ -n "$bad_nodes" ]]; then
      log_warn "Node output contains unrecognized lines:"
      printf '%s\n' "$bad_nodes"
    else
      log_success "Node output format check passed"
    fi
  else
    log_warn "Node output file missing"
  fi

  if [[ -f /etc/sing-box-deve/runtime.env ]]; then
    # shellcheck disable=SC1091
    source /etc/sing-box-deve/runtime.env
    local p mapping proto port
    IFS=',' read -r -a _plist <<< "${protocols:-}"
    for p in "${_plist[@]}"; do
      p="$(echo "$p" | xargs)"
      [[ -n "$p" ]] || continue
      protocol_needs_local_listener "$p" || continue
      mapping="$(protocol_port_map "$p")"
      proto="${mapping%%:*}"
      port="${mapping##*:}"
      if ss -lntup 2>/dev/null | grep -E "[.:]${port}[[:space:]]" >/dev/null; then
        log_success "Port listening detected for ${p}: ${proto}/${port}"
      else
        log_warn "Port not detected for ${p}: ${proto}/${port}"
      fi
    done
  fi
}

provider_uninstall() {
  ensure_root
  log_warn "Uninstall requested; removing only managed firewall rules and sing-box-deve state"
  if systemctl list-unit-files | grep -q '^sing-box-deve.service'; then
    systemctl disable --now sing-box-deve.service >/dev/null 2>&1 || true
  fi
  if systemctl list-unit-files | grep -q '^sing-box-deve-argo.service'; then
    systemctl disable --now sing-box-deve-argo.service >/dev/null 2>&1 || true
  fi
  rm -f "$SBD_SERVICE_FILE"
  rm -f "$SBD_ARGO_SERVICE_FILE"
  systemctl daemon-reload
  fw_detect_backend
  fw_clear_managed_rules
  rm -rf /etc/sing-box-deve "$SBD_STATE_DIR" "$SBD_RUNTIME_DIR" "$SBD_INSTALL_DIR"
  log_success "Uninstall complete"
}
