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
  cat <<EOF
    {
      "type": "vless",
      "tag": "vless-reality",
      "listen": "::",
      "listen_port": ${port},
      "users": [{"uuid": "${uuid}", "flow": "xtls-rprx-vision"}],
      "tls": {
        "enabled": true,
        "server_name": "${server_name}",
        "reality": {
          "enabled": true,
          "handshake": {"server": "${server_name}", "server_port": ${reality_port}},
          "private_key": "${private_key}",
          "short_id": ["${short_id}"]
        }
      }
    }
EOF
}

singbox_fragment_vmess_ws() {
  local uuid="$1" port="$2" ws_path="$3"
  cat <<EOF
    {
      "type": "vmess",
      "tag": "vmess-ws",
      "listen": "::",
      "listen_port": ${port},
      "users": [{"uuid": "${uuid}"}],
      "transport": {"type": "ws", "path": "${ws_path}"}
    }
EOF
}

singbox_fragment_vless_ws() {
  local uuid="$1" port="$2" ws_path="$3"
  cat <<EOF
    {
      "type": "vless",
      "tag": "vless-ws",
      "listen": "::",
      "listen_port": ${port},
      "users": [{"uuid": "${uuid}"}],
      "transport": {"type": "ws", "path": "${ws_path}"}
    }
EOF
}

singbox_fragment_ss2022() {
  local uuid="$1" port="$2"
  cat <<EOF
    {
      "type": "shadowsocks",
      "tag": "ss-2022",
      "listen": "::",
      "listen_port": ${port},
      "method": "2022-blake3-aes-128-gcm",
      "password": "${uuid}"
    }
EOF
}

singbox_fragment_hysteria2() {
  local uuid="$1" port="$2" tls_sni="$3" cert_file="$4" key_file="$5"
  cat <<EOF
    {
      "type": "hysteria2",
      "tag": "hy2",
      "listen": "::",
      "listen_port": ${port},
      "users": [{"password": "${uuid}"}],
      "tls": {
        "enabled": true,
        "server_name": "${tls_sni}",
        "certificate_path": "${cert_file}",
        "key_path": "${key_file}"
      }
    }
EOF
}

singbox_fragment_tuic() {
  local uuid="$1" port="$2" tls_sni="$3" cert_file="$4" key_file="$5"
  cat <<EOF
    {
      "type": "tuic",
      "tag": "tuic",
      "listen": "::",
      "listen_port": ${port},
      "users": [{"uuid": "${uuid}", "password": "${uuid}"}],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "server_name": "${tls_sni}",
        "certificate_path": "${cert_file}",
        "key_path": "${key_file}"
      }
    }
EOF
}

singbox_fragment_trojan() {
  local uuid="$1" port="$2" tls_sni="$3" cert_file="$4" key_file="$5"
  cat <<EOF
    {
      "type": "trojan",
      "tag": "trojan",
      "listen": "::",
      "listen_port": ${port},
      "users": [{"password": "${uuid}"}],
      "tls": {
        "enabled": true,
        "server_name": "${tls_sni}",
        "certificate_path": "${cert_file}",
        "key_path": "${key_file}"
      }
    }
EOF
}

singbox_fragment_anytls() {
  local uuid="$1" port="$2" cert_file="$3" key_file="$4"
  cat <<EOF
    {
      "type": "anytls",
      "tag": "anytls",
      "listen": "::",
      "listen_port": ${port},
      "users": [{"password": "${uuid}"}],
      "padding_scheme": [],
      "tls": {
        "enabled": true,
        "certificate_path": "${cert_file}",
        "key_path": "${key_file}"
      }
    }
EOF
}

singbox_fragment_any_reality() {
  local uuid="$1" port="$2" server_name="$3" reality_port="$4" private_key="$5" short_id="$6"
  cat <<EOF
    {
      "type": "anytls",
      "tag": "any-reality",
      "listen": "::",
      "listen_port": ${port},
      "users": [{"password": "${uuid}"}],
      "padding_scheme": [],
      "tls": {
        "enabled": true,
        "server_name": "${server_name}",
        "reality": {
          "enabled": true,
          "handshake": {"server": "${server_name}", "server_port": ${reality_port}},
          "private_key": "${private_key}",
          "short_id": ["${short_id}"]
        }
      }
    }
EOF
}

singbox_fragment_wireguard() {
  local port="$1" wg_private="$2"
  cat <<EOF
    {
      "type": "wireguard",
      "tag": "wireguard",
      "listen_port": ${port},
      "address": ["10.66.66.1/24"],
      "private_key": "${wg_private}",
      "peers": []
    }
EOF
}
