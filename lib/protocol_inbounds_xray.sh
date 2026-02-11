#!/usr/bin/env bash

xray_fragment_vless_reality() {
  local uuid="$1" port="$2" server_name="$3" reality_port="$4" private_key="$5" short_id="$6"
  cat <<EOF
    {
      "tag": "vless-reality",
      "listen": "::",
      "port": ${port},
      "protocol": "vless",
      "settings": {"clients": [{"id": "${uuid}", "flow": "xtls-rprx-vision"}], "decryption": "none"},
      "streamSettings": {"network": "tcp", "security": "reality", "realitySettings": {"show": false, "dest": "${server_name}:${reality_port}", "xver": 0, "serverNames": ["${server_name}"], "privateKey": "${private_key}", "shortIds": ["${short_id}"]}}
    }
EOF
}

xray_fragment_vmess_ws() {
  local uuid="$1" port="$2" ws_path="$3"
  cat <<EOF
    {
      "tag": "vmess-ws",
      "listen": "::",
      "port": ${port},
      "protocol": "vmess",
      "settings": {"clients": [{"id": "${uuid}"}]},
      "streamSettings": {"network": "ws", "wsSettings": {"path": "${ws_path}"}}
    }
EOF
}

xray_fragment_vless_ws() {
  local uuid="$1" port="$2" ws_path="$3" decryption="$4"
  cat <<EOF
    {
      "tag": "vless-ws",
      "listen": "::",
      "port": ${port},
      "protocol": "vless",
      "settings": {"clients": [{"id": "${uuid}"}], "decryption": "${decryption}"},
      "streamSettings": {"network": "ws", "wsSettings": {"path": "${ws_path}"}}
    }
EOF
}

xray_fragment_vless_xhttp() {
  local uuid="$1" port="$2" decryption="$3" xhttp_path="$4" xhttp_mode="$5"
  local use_reality="$6" server_name="$7" reality_port="$8" private_key="$9" short_id="${10}"
  if [[ "$use_reality" == "true" ]]; then
    cat <<EOF
    {
      "tag": "vless-xhttp",
      "listen": "::",
      "port": ${port},
      "protocol": "vless",
      "settings": {"clients": [{"id": "${uuid}", "flow": "xtls-rprx-vision"}], "decryption": "${decryption}"},
      "streamSettings": {"network": "xhttp", "security": "reality", "realitySettings": {"show": false, "dest": "${server_name}:${reality_port}", "xver": 0, "serverNames": ["${server_name}"], "privateKey": "${private_key}", "shortIds": ["${short_id}"]}, "xhttpSettings": {"path": "${xhttp_path}", "mode": "${xhttp_mode}"}}
    }
EOF
  else
    cat <<EOF
    {
      "tag": "vless-xhttp",
      "listen": "::",
      "port": ${port},
      "protocol": "vless",
      "settings": {"clients": [{"id": "${uuid}", "flow": "xtls-rprx-vision"}], "decryption": "${decryption}"},
      "streamSettings": {"network": "xhttp", "xhttpSettings": {"path": "${xhttp_path}", "mode": "${xhttp_mode}"}}
    }
EOF
  fi
}

xray_fragment_trojan() {
  local uuid="$1" port="$2" cert_file="$3" key_file="$4"
  cat <<EOF
    {
      "tag": "trojan",
      "listen": "::",
      "port": ${port},
      "protocol": "trojan",
      "settings": {"clients": [{"password": "${uuid}"}]},
      "streamSettings": {"security": "tls", "tlsSettings": {"certificates": [{"certificateFile": "${cert_file}", "keyFile": "${key_file}"}]}}
    }
EOF
}

xray_fragment_socks5() {
  local uuid="$1" port="$2"
  cat <<EOF
    {
      "tag": "socks5",
      "listen": "::",
      "port": ${port},
      "protocol": "socks",
      "settings": {"auth": "password", "accounts": [{"user": "${uuid}", "pass": "${uuid}"}], "udp": true}
    }
EOF
}
