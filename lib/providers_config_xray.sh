#!/usr/bin/env bash

build_xray_config() {
  local protocols_csv="$1"
  local config_file="${SBD_CONFIG_DIR}/xray-config.json"
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

  local xray_outbounds xray_routing
  xray_outbounds=$'    {"protocol": "freedom", "tag": "direct"},\n'
  xray_outbounds+=$'    {"protocol": "blackhole", "tag": "block"}'
  xray_routing=""

  if [[ "${OUTBOUND_PROXY_MODE:-direct}" != "direct" ]]; then
    xray_outbounds+=$',\n'
    xray_outbounds+="$(build_upstream_outbound_xray)"
    xray_routing=$',\n  "routing": {"domainStrategy": "AsIs", "rules": [{"type": "field", "network": "tcp,udp", "outboundTag": "proxy-out"}]}'
  fi

  cat > "$config_file" <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [
${inbounds}
  ],
  "outbounds": [
${xray_outbounds}
  ]${xray_routing}
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
      config_path="${SBD_CONFIG_DIR}/config.json"
      binary_path="${SBD_BIN_DIR}/sing-box"
      exec_args="run -c ${config_path}"
      ;;
    xray)
      config_path="${SBD_CONFIG_DIR}/xray-config.json"
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
