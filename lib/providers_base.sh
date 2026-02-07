#!/usr/bin/env bash

protocol_port_map() {
  local proto="$1"
  case "$proto" in
    vless-reality) echo "tcp:443" ;;
    vmess-ws) echo "tcp:8443" ;;
    vless-xhttp) echo "tcp:9443" ;;
    vless-ws) echo "tcp:8444" ;;
    shadowsocks-2022) echo "tcp:2443" ;;
    hysteria2) echo "udp:8443" ;;
    tuic) echo "udp:10443" ;;
    anytls) echo "tcp:20443" ;;
    any-reality) echo "tcp:30443" ;;
    argo) echo "tcp:8080" ;;
    warp) echo "udp:51820" ;;
    trojan) echo "tcp:4433" ;;
    wireguard) echo "udp:51820" ;;
    socks5) echo "tcp:10808" ;;
    *) die "No port map for protocol: $proto" ;;
  esac
}

get_protocol_port() {
  local proto="$1"
  local mapping default_port key
  mapping="$(protocol_port_map "$proto")"
  default_port="${mapping##*:}"
  key="SBD_PORT_$(echo "$proto" | tr '[:lower:]-' '[:upper:]_')"
  if [[ -n "${!key:-}" ]]; then
    [[ "${!key}" =~ ^[0-9]+$ ]] || die "${key} must be numeric"
    (( ${!key} >= 1 && ${!key} <= 65535 )) || die "${key} must be within 1..65535"
    echo "${!key}"
    return 0
  fi
  echo "$default_port"
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

  validate_warp_mode_extended

  case "${OUTBOUND_PROXY_MODE:-direct}" in
    direct|socks|http|https) ;;
    *) die "Invalid OUTBOUND_PROXY_MODE: ${OUTBOUND_PROXY_MODE}" ;;
  esac

  validate_route_mode

  if [[ "${OUTBOUND_PROXY_MODE:-direct}" != "direct" ]]; then
    [[ -n "${OUTBOUND_PROXY_HOST:-}" ]] || die "OUTBOUND_PROXY_HOST is required when outbound proxy mode is not direct"
    [[ -n "${OUTBOUND_PROXY_PORT:-}" ]] || die "OUTBOUND_PROXY_PORT is required when outbound proxy mode is not direct"
    [[ "${OUTBOUND_PROXY_PORT}" =~ ^[0-9]+$ ]] || die "OUTBOUND_PROXY_PORT must be numeric"
    (( OUTBOUND_PROXY_PORT >= 1 && OUTBOUND_PROXY_PORT <= 65535 )) || die "OUTBOUND_PROXY_PORT must be between 1 and 65535"
  fi

  if [[ "${OUTBOUND_PROXY_MODE:-direct}" != "direct" && "${WARP_MODE:-off}" == "global" ]]; then
    die "WARP_MODE=global conflicts with OUTBOUND_PROXY_MODE!=direct; choose one outbound strategy"
  fi
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

engine_supports_protocol() {
  local engine="$1"
  local protocol="$2"

  case "$engine" in
    sing-box)
      case "$protocol" in
        vless-reality|vmess-ws|vless-ws|shadowsocks-2022|hysteria2|tuic|trojan|wireguard|argo|warp|anytls|any-reality) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    xray)
      case "$protocol" in
        vless-reality|vmess-ws|vless-ws|vless-xhttp|trojan|argo|socks5|warp) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    *) return 1 ;;
  esac
}

assert_engine_protocol_compatibility() {
  local engine="$1"
  local protocols_csv="$2"
  local protocols=()
  protocols_to_array "$protocols_csv" protocols
  local p
  for p in "${protocols[@]}"; do
    engine_supports_protocol "$engine" "$p" || die "Protocol '${p}' is not implemented for engine '${engine}' yet"
  done
}
