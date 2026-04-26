#!/usr/bin/env bash

xray_fragment_vless_reality() {
  local uuid="$1" port="$2" server_name="$3" reality_port="$4" private_key="$5" short_id="$6"
  local uuid_json server_name_json dest_json private_key_json short_id_json
  uuid_json="$(sbd_json_string "$uuid")"
  server_name_json="$(sbd_json_string "$server_name")"
  dest_json="$(sbd_json_string "${server_name}:${reality_port}")"
  private_key_json="$(sbd_json_string "$private_key")"
  short_id_json="$(sbd_json_string "$short_id")"
  cat <<EOF
    {
      "tag": "vless-reality",
      "listen": "::",
      "port": ${port},
      "protocol": "vless",
      "settings": {"clients": [{"id": ${uuid_json}, "flow": "xtls-rprx-vision"}], "decryption": "none"},
      "streamSettings": {"network": "tcp", "security": "reality", "realitySettings": {"show": false, "dest": ${dest_json}, "xver": 0, "serverNames": [${server_name_json}], "privateKey": ${private_key_json}, "shortIds": [${short_id_json}]}}
    }
EOF
}

xray_fragment_vmess_ws() {
  local uuid="$1" port="$2" ws_path="$3"
  local uuid_json ws_path_json
  uuid_json="$(sbd_json_string "$uuid")"
  ws_path_json="$(sbd_json_string "$ws_path")"
  cat <<EOF
    {
      "tag": "vmess-ws",
      "listen": "::",
      "port": ${port},
      "protocol": "vmess",
      "settings": {"clients": [{"id": ${uuid_json}}]},
      "streamSettings": {"network": "ws", "wsSettings": {"path": ${ws_path_json}}}
    }
EOF
}

xray_fragment_vless_ws() {
  local uuid="$1" port="$2" ws_path="$3" decryption="$4"
  local uuid_json ws_path_json decryption_json
  uuid_json="$(sbd_json_string "$uuid")"
  ws_path_json="$(sbd_json_string "$ws_path")"
  decryption_json="$(sbd_json_string "$decryption")"
  cat <<EOF
    {
      "tag": "vless-ws",
      "listen": "::",
      "port": ${port},
      "protocol": "vless",
      "settings": {"clients": [{"id": ${uuid_json}}], "decryption": ${decryption_json}},
      "streamSettings": {"network": "ws", "wsSettings": {"path": ${ws_path_json}}}
    }
EOF
}

xray_fragment_vless_xhttp() {
  local uuid="$1" port="$2" decryption="$3" xhttp_path="$4" xhttp_mode="$5"
  local use_reality="$6" server_name="$7" reality_port="$8" private_key="$9" short_id="${10}"
  local uuid_json decryption_json xhttp_path_json xhttp_mode_json server_name_json dest_json private_key_json short_id_json
  uuid_json="$(sbd_json_string "$uuid")"
  decryption_json="$(sbd_json_string "$decryption")"
  xhttp_path_json="$(sbd_json_string "$xhttp_path")"
  xhttp_mode_json="$(sbd_json_string "$xhttp_mode")"
  server_name_json="$(sbd_json_string "$server_name")"
  dest_json="$(sbd_json_string "${server_name}:${reality_port}")"
  private_key_json="$(sbd_json_string "$private_key")"
  short_id_json="$(sbd_json_string "$short_id")"
  if [[ "$use_reality" == "true" ]]; then
    cat <<EOF
    {
      "tag": "vless-xhttp",
      "listen": "::",
      "port": ${port},
      "protocol": "vless",
      "settings": {"clients": [{"id": ${uuid_json}, "flow": "xtls-rprx-vision"}], "decryption": ${decryption_json}},
      "streamSettings": {"network": "xhttp", "security": "reality", "realitySettings": {"show": false, "dest": ${dest_json}, "xver": 0, "serverNames": [${server_name_json}], "privateKey": ${private_key_json}, "shortIds": [${short_id_json}]}, "xhttpSettings": {"path": ${xhttp_path_json}, "mode": ${xhttp_mode_json}}}
    }
EOF
  else
    cat <<EOF
    {
      "tag": "vless-xhttp",
      "listen": "::",
      "port": ${port},
      "protocol": "vless",
      "settings": {"clients": [{"id": ${uuid_json}, "flow": "xtls-rprx-vision"}], "decryption": ${decryption_json}},
      "streamSettings": {"network": "xhttp", "xhttpSettings": {"path": ${xhttp_path_json}, "mode": ${xhttp_mode_json}}}
    }
EOF
  fi
}

xray_fragment_trojan() {
  local uuid="$1" port="$2" cert_file="$3" key_file="$4"
  local uuid_json cert_file_json key_file_json
  uuid_json="$(sbd_json_string "$uuid")"
  cert_file_json="$(sbd_json_string "$cert_file")"
  key_file_json="$(sbd_json_string "$key_file")"
  cat <<EOF
    {
      "tag": "trojan",
      "listen": "::",
      "port": ${port},
      "protocol": "trojan",
      "settings": {"clients": [{"password": ${uuid_json}}]},
      "streamSettings": {"security": "tls", "tlsSettings": {"certificates": [{"certificateFile": ${cert_file_json}, "keyFile": ${key_file_json}}]}}
    }
EOF
}

xray_fragment_socks5() {
  local uuid="$1" port="$2"
  local uuid_json
  uuid_json="$(sbd_json_string "$uuid")"
  cat <<EOF
    {
      "tag": "socks5",
      "listen": "::",
      "port": ${port},
      "protocol": "socks",
      "settings": {"auth": "password", "accounts": [{"user": ${uuid_json}, "pass": ${uuid_json}}], "udp": true}
    }
EOF
}
