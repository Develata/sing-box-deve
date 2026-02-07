#!/usr/bin/env bash

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

build_upstream_outbound_singbox() {
  local mode="${OUTBOUND_PROXY_MODE:-direct}"
  [[ "$mode" != "direct" ]] || return 0

  local host port user pass auth
  host="${OUTBOUND_PROXY_HOST}"
  port="${OUTBOUND_PROXY_PORT}"
  user="${OUTBOUND_PROXY_USER:-}"
  pass="${OUTBOUND_PROXY_PASS:-}"

  auth=""
  if [[ -n "$user" || -n "$pass" ]]; then
    auth=", \"username\": \"${user}\", \"password\": \"${pass}\""
  fi

  case "$mode" in
    socks)
      cat <<EOF
    {"type": "socks", "tag": "proxy-out", "server": "${host}", "server_port": ${port}${auth}}
EOF
      ;;
    http)
      cat <<EOF
    {"type": "http", "tag": "proxy-out", "server": "${host}", "server_port": ${port}${auth}}
EOF
      ;;
    https)
      cat <<EOF
    {"type": "http", "tag": "proxy-out", "server": "${host}", "server_port": ${port}${auth}, "tls": {"enabled": true, "server_name": "${host}"}}
EOF
      ;;
  esac
}

build_upstream_outbound_xray() {
  local mode="${OUTBOUND_PROXY_MODE:-direct}"
  [[ "$mode" != "direct" ]] || return 0

  local protocol host port user pass users_json stream_tls
  host="${OUTBOUND_PROXY_HOST}"
  port="${OUTBOUND_PROXY_PORT}"
  user="${OUTBOUND_PROXY_USER:-}"
  pass="${OUTBOUND_PROXY_PASS:-}"

  users_json="[]"
  if [[ -n "$user" || -n "$pass" ]]; then
    users_json="[{\"user\":\"${user}\",\"pass\":\"${pass}\"}]"
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
    {"protocol":"${protocol}","tag":"proxy-out","settings":{"servers":[{"address":"${host}","port":${port},"users":${users_json}}]}${stream_tls}}
EOF
}

validate_generated_config() {
  local engine="$1"
  local output
  case "$engine" in
    sing-box)
      [[ -x "${SBD_BIN_DIR}/sing-box" ]] || die "sing-box binary not found"
      if ! output="$("${SBD_BIN_DIR}/sing-box" check -c "${SBD_CONFIG_DIR}/config.json" 2>&1)"; then
        log_error "$output"
        die "sing-box config validation failed"
      fi
      ;;
    xray)
      [[ -x "${SBD_BIN_DIR}/xray" ]] || die "xray binary not found"
      if ! output="$("${SBD_BIN_DIR}/xray" run -test -config "${SBD_CONFIG_DIR}/xray-config.json" 2>&1)"; then
        log_error "$output"
        die "xray config validation failed"
      fi
      ;;
    *)
      die "Unsupported engine for config validation: $engine"
      ;;
  esac
}
