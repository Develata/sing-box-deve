#!/usr/bin/env bash

sbd_inbounds_append() {
  local in_var="$1" map_var="$2" tag="$3" port="$4" fragment="$5"
  local -n in_ref="$in_var"
  local -n map_ref="$map_var"
  [[ -n "$in_ref" ]] && in_ref+=$',\n'
  in_ref+="$fragment"
  if [[ -n "$map_ref" ]]; then
    map_ref+=",${tag}:${port}"
  else
    map_ref="${tag}:${port}"
  fi
}

singbox_fragment_vless_reality() {
  local uuid="$1" port="$2" server_name="$3" reality_port="$4" private_key="$5" short_id="$6"
  local uuid_json server_name_json private_key_json short_id_json
  uuid_json="$(sbd_json_string "$uuid")"
  server_name_json="$(sbd_json_string "$server_name")"
  private_key_json="$(sbd_json_string "$private_key")"
  short_id_json="$(sbd_json_string "$short_id")"
  cat <<EOF
    {
      "type": "vless",
      "tag": "vless-reality",
      "listen": "::",
      "listen_port": ${port},
      "users": [{"uuid": ${uuid_json}, "flow": "xtls-rprx-vision"}],
      "tls": {
        "enabled": true,
        "server_name": ${server_name_json},
        "reality": {
          "enabled": true,
          "handshake": {"server": ${server_name_json}, "server_port": ${reality_port}},
          "private_key": ${private_key_json},
          "short_id": [${short_id_json}]
        }
      }
    }
EOF
}

singbox_fragment_vless_ws() {
  local uuid="$1" port="$2" ws_path="$3"
  local uuid_json ws_path_json
  uuid_json="$(sbd_json_string "$uuid")"
  ws_path_json="$(sbd_json_string "$ws_path")"
  cat <<EOF
    {
      "type": "vless",
      "tag": "vless-ws",
      "listen": "::",
      "listen_port": ${port},
      "users": [{"uuid": ${uuid_json}}],
      "transport": {"type": "ws", "path": ${ws_path_json}}
    }
EOF
}

singbox_fragment_ss2022() {
  local password="$1" port="$2"
  local password_json
  password_json="$(sbd_json_string "$password")"
  cat <<EOF
    {
      "type": "shadowsocks",
      "tag": "ss-2022",
      "listen": "::",
      "listen_port": ${port},
      "method": "2022-blake3-aes-128-gcm",
      "password": ${password_json}
    }
EOF
}

singbox_fragment_naive() {
  local uuid="$1" port="$2" tls_sni="$3" cert_file="$4" key_file="$5"
  local uuid_json tls_sni_json cert_file_json key_file_json
  uuid_json="$(sbd_json_string "$uuid")"
  tls_sni_json="$(sbd_json_string "$tls_sni")"
  cert_file_json="$(sbd_json_string "$cert_file")"
  key_file_json="$(sbd_json_string "$key_file")"
  cat <<EOF
    {
      "type": "naive",
      "tag": "naive",
      "listen": "::",
      "listen_port": ${port},
      "network": "tcp",
      "users": [{"username": ${uuid_json}, "password": ${uuid_json}}],
      "tls": {
        "enabled": true,
        "server_name": ${tls_sni_json},
        "certificate_path": ${cert_file_json},
        "key_path": ${key_file_json}
      }
    }
EOF
}

singbox_fragment_hysteria2() {
  local uuid="$1" port="$2" tls_sni="$3" cert_file="$4" key_file="$5" masquerade_dir="${6:-}"
  local uuid_json tls_sni_json cert_file_json key_file_json masquerade_json masquerade_line=""
  uuid_json="$(sbd_json_string "$uuid")"
  tls_sni_json="$(sbd_json_string "$tls_sni")"
  cert_file_json="$(sbd_json_string "$cert_file")"
  key_file_json="$(sbd_json_string "$key_file")"
  if [[ -n "$masquerade_dir" ]]; then
    masquerade_json="$(sbd_json_string "file://${masquerade_dir}")"
    masquerade_line=$',\n      "masquerade": '
    masquerade_line+="${masquerade_json}"
  fi
  cat <<EOF
    {
      "type": "hysteria2",
      "tag": "hy2",
      "listen": "::",
      "listen_port": ${port},
      "users": [{"password": ${uuid_json}}],
      "tls": {
        "enabled": true,
        "server_name": ${tls_sni_json},
        "certificate_path": ${cert_file_json},
        "key_path": ${key_file_json}
      }${masquerade_line}
    }
EOF
}

singbox_fragment_tuic() {
  local uuid="$1" port="$2" tls_sni="$3" cert_file="$4" key_file="$5"
  local uuid_json tls_sni_json cert_file_json key_file_json
  uuid_json="$(sbd_json_string "$uuid")"
  tls_sni_json="$(sbd_json_string "$tls_sni")"
  cert_file_json="$(sbd_json_string "$cert_file")"
  key_file_json="$(sbd_json_string "$key_file")"
  cat <<EOF
    {
      "type": "tuic",
      "tag": "tuic",
      "listen": "::",
      "listen_port": ${port},
      "users": [{"uuid": ${uuid_json}, "password": ${uuid_json}}],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "server_name": ${tls_sni_json},
        "certificate_path": ${cert_file_json},
        "key_path": ${key_file_json}
      }
    }
EOF
}
