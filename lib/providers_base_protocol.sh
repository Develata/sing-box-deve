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
  local proto="$1" mapping default_port key
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

protocol_inbound_tag() {
  local protocol="$1"
  case "$protocol" in
    vless-reality) echo "vless-reality" ;;
    vmess-ws) echo "vmess-ws" ;;
    vless-ws) echo "vless-ws" ;;
    vless-xhttp) echo "vless-xhttp" ;;
    shadowsocks-2022) echo "ss-2022" ;;
    hysteria2) echo "hy2" ;;
    tuic) echo "tuic" ;;
    trojan) echo "trojan" ;;
    wireguard) echo "wireguard" ;;
    anytls) echo "anytls" ;;
    any-reality) echo "any-reality" ;;
    socks5) echo "socks5" ;;
    *) return 1 ;;
  esac
}

config_port_for_tag() {
  local engine="$1" tag="$2"
  command -v jq >/dev/null 2>&1 || return 1
  case "$engine" in
    sing-box)
      [[ -f "${SBD_CONFIG_DIR}/config.json" ]] || return 1
      jq -r --arg t "$tag" '.inbounds[] | select(.tag==$t) | (.listen_port // .port // empty)' "${SBD_CONFIG_DIR}/config.json" | head -n1
      ;;
    xray)
      [[ -f "${SBD_CONFIG_DIR}/xray-config.json" ]] || return 1
      jq -r --arg t "$tag" '.inbounds[] | select(.tag==$t) | (.port // empty)' "${SBD_CONFIG_DIR}/xray-config.json" | head -n1
      ;;
    *) return 1 ;;
  esac
}

resolve_protocol_port_for_engine() {
  local engine="$1" protocol="$2" default_port tag current_port
  default_port="$(get_protocol_port "$protocol")"
  if ! tag="$(protocol_inbound_tag "$protocol")"; then
    echo "$default_port"
    return 0
  fi
  current_port="$(config_port_for_tag "$engine" "$tag" 2>/dev/null || true)"
  if [[ "$current_port" =~ ^[0-9]+$ ]] && (( current_port >= 1 && current_port <= 65535 )); then
    echo "$current_port"
  else
    echo "$default_port"
  fi
}

protocol_needs_local_listener() {
  local proto="$1"
  case "$proto" in
    argo|warp) return 1 ;;
    *) return 0 ;;
  esac
}

engine_supports_protocol() {
  local engine="$1" protocol="$2"

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
  local engine="$1" protocols_csv="$2" p
  local protocols=()
  protocols_to_array "$protocols_csv" protocols
  for p in "${protocols[@]}"; do
    engine_supports_protocol "$engine" "$p" || die "Protocol '${p}' is not implemented for engine '${engine}' yet"
  done
}
