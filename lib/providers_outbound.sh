#!/usr/bin/env bash

build_warp_outbound_singbox() {
  local private_key="${WARP_PRIVATE_KEY:-}"
  local peer_public_key="${WARP_PEER_PUBLIC_KEY:-}"
  local local_v4="${WARP_LOCAL_V4:-172.16.0.2/32}"
  local local_v6="${WARP_LOCAL_V6:-2606:4700:110:876d:4d3c:4206:c90c:6bd0/128}"
  local reserved="${WARP_RESERVED:-[0,0,0]}"
  local private_key_json peer_public_key_json local_v4_json local_v6_json

  [[ -n "$private_key" ]] || die "WARP_PRIVATE_KEY is required when warp protocol is enabled"
  [[ -n "$peer_public_key" ]] || die "WARP_PEER_PUBLIC_KEY is required when warp protocol is enabled"
  [[ "$local_v4" == */* ]] || local_v4="${local_v4}/32"
  [[ "$local_v6" == */* ]] || local_v6="${local_v6}/128"
  private_key_json="$(sbd_json_string "$private_key")"
  peer_public_key_json="$(sbd_json_string "$peer_public_key")"
  local_v4_json="$(sbd_json_string "$local_v4")"
  local_v6_json="$(sbd_json_string "$local_v6")"

  cat <<EOF
    {"type": "wireguard", "tag": "warp-out", "server": "engage.cloudflareclient.com", "server_port": 2408, "local_address": [${local_v4_json}, ${local_v6_json}], "private_key": ${private_key_json}, "peer_public_key": ${peer_public_key_json}, "reserved": ${reserved}, "mtu": 1280}
EOF
}

build_upstream_outbound_singbox() {
  local mode="${OUTBOUND_PROXY_MODE:-direct}"
  [[ "$mode" != "direct" ]] || return 0

  local host port user pass auth host_json user_json pass_json
  host="${OUTBOUND_PROXY_HOST}"
  port="${OUTBOUND_PROXY_PORT}"
  user="${OUTBOUND_PROXY_USER:-}"
  pass="${OUTBOUND_PROXY_PASS:-}"
  host_json="$(sbd_json_string "$host")"

  auth=""
  if [[ -n "$user" || -n "$pass" ]]; then
    user_json="$(sbd_json_string "$user")"
    pass_json="$(sbd_json_string "$pass")"
    auth=", \"username\": ${user_json}, \"password\": ${pass_json}"
  fi

  case "$mode" in
    socks)
      cat <<EOF
    {"type": "socks", "tag": "proxy-out", "server": ${host_json}, "server_port": ${port}${auth}}
EOF
      ;;
    http)
      cat <<EOF
    {"type": "http", "tag": "proxy-out", "server": ${host_json}, "server_port": ${port}${auth}}
EOF
      ;;
    https)
      cat <<EOF
    {"type": "http", "tag": "proxy-out", "server": ${host_json}, "server_port": ${port}${auth}, "tls": {"enabled": true, "server_name": ${host_json}}}
EOF
      ;;
  esac
}

build_psiphon_outbound_singbox() {
  local host="127.0.0.1"
  local port
  port="$(provider_psiphon_default_socks_port)"
  cat <<EOF
    {"type": "socks", "tag": "psiphon-out", "server": "${host}", "server_port": ${port}}
EOF
}

build_upstream_outbound_xray() {
  local mode="${OUTBOUND_PROXY_MODE:-direct}"
  [[ "$mode" != "direct" ]] || return 0

  local protocol host port user pass users_json stream_tls host_json user_json pass_json
  host="${OUTBOUND_PROXY_HOST}"
  port="${OUTBOUND_PROXY_PORT}"
  user="${OUTBOUND_PROXY_USER:-}"
  pass="${OUTBOUND_PROXY_PASS:-}"
  host_json="$(sbd_json_string "$host")"

  users_json="[]"
  if [[ -n "$user" || -n "$pass" ]]; then
    user_json="$(sbd_json_string "$user")"
    pass_json="$(sbd_json_string "$pass")"
    users_json="[{\"user\":${user_json},\"pass\":${pass_json}}]"
  fi

  case "$mode" in
    socks)
      protocol="socks"
      stream_tls=""
      ;;
    http)
      protocol="http"
      stream_tls=""
      ;;
    https)
      protocol="http"
      stream_tls=",\"streamSettings\":{\"security\":\"tls\"}"
      ;;
  esac

  cat <<EOF
    {"protocol":"${protocol}","tag":"proxy-out","settings":{"servers":[{"address":${host_json},"port":${port},"users":${users_json}}]}${stream_tls}}
EOF
}

build_psiphon_outbound_xray() {
  local host="127.0.0.1"
  local port
  port="$(provider_psiphon_default_socks_port)"
  cat <<EOF
    {"protocol":"socks","tag":"psiphon-out","settings":{"servers":[{"address":"${host}","port":${port},"users":[]}]}}
EOF
}

build_warp_outbound_xray() {
  local private_key="${WARP_PRIVATE_KEY:-}"
  local local_v6_raw="${WARP_LOCAL_V6:-2606:4700:110:876d:4d3c:4206:c90c:6bd0}"
  local local_v6
  local reserved="${WARP_RESERVED:-[0,0,0]}"
  local domain_strategy
  local private_key_json local_v6_json domain_strategy_json
  domain_strategy="$(xray_domain_strategy_from_warp_mode)"
  local_v6="${local_v6_raw%%/*}"
  [[ -n "$local_v6" ]] || local_v6="2606:4700:110:876d:4d3c:4206:c90c:6bd0"

  [[ -n "$private_key" ]] || die "WARP_PRIVATE_KEY is required when warp mode targets xray"
  private_key_json="$(sbd_json_string "$private_key")"
  local_v6_json="$(sbd_json_string "${local_v6}/128")"
  domain_strategy_json="$(sbd_json_string "$domain_strategy")"

  cat <<EOF
    {"tag":"x-warp-out","protocol":"wireguard","settings":{"secretKey":${private_key_json},"address":["172.16.0.2/32",${local_v6_json}],"peers":[{"publicKey":"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=","allowedIPs":["0.0.0.0/0","::/0"],"endpoint":"engage.cloudflareclient.com:2408"}],"reserved":${reserved}}},
    {"tag":"warp-out","protocol":"freedom","settings":{"domainStrategy":${domain_strategy_json}},"proxySettings":{"tag":"x-warp-out"}}
EOF
}

validate_generated_config() {
  local engine="$1"
  local with_rollback="${2:-false}"
  local output backup_file config_file

  case "$engine" in
    sing-box)
      config_file="${SBD_CONFIG_DIR}/config.json"
      backup_file="${config_file}.bak"
      [[ -x "${SBD_BIN_DIR}/sing-box" ]] || die "sing-box binary not found"
      if ! output="$("${SBD_BIN_DIR}/sing-box" check -c "$config_file" 2>&1)"; then
        if [[ "$with_rollback" == "true" && -f "$backup_file" ]]; then
          mv "$backup_file" "$config_file"
          log_warn "$(msg "配置验证失败，已回滚到上一版本" "Config validation failed, rolled back to previous version")"
        fi
        log_error "$output"
        die "sing-box config validation failed"
      fi
      rm -f "$backup_file"
      ;;
    xray)
      config_file="${SBD_CONFIG_DIR}/xray-config.json"
      backup_file="${config_file}.bak"
      [[ -x "${SBD_BIN_DIR}/xray" ]] || die "xray binary not found"
      if ! output="$("${SBD_BIN_DIR}/xray" run -test -config "$config_file" 2>&1)"; then
        if [[ "$with_rollback" == "true" && -f "$backup_file" ]]; then
          mv "$backup_file" "$config_file"
          log_warn "$(msg "配置验证失败，已回滚到上一版本" "Config validation failed, rolled back to previous version")"
        fi
        log_error "$output"
        die "xray config validation failed"
      fi
      rm -f "$backup_file"
      ;;
    *)
      die "Unsupported engine for config validation: $engine"
      ;;
  esac
}
