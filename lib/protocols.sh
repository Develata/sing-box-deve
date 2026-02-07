#!/usr/bin/env bash

ALL_PROTOCOLS=(
  vless-reality
  vmess-ws
  vless-xhttp
  vless-ws
  shadowsocks-2022
  hysteria2
  tuic
  anytls
  any-reality
  argo
  warp
  trojan
  wireguard
)

validate_provider() {
  local provider="$1"
  case "$provider" in
    vps|serv00|sap|docker) return 0 ;;
    *) die "Unsupported provider: $provider" ;;
  esac
}

validate_engine() {
  local engine="$1"
  case "$engine" in
    sing-box|xray) return 0 ;;
    *) die "Unsupported engine: $engine" ;;
  esac
}

contains_protocol() {
  local protocol="$1"
  local p
  for p in "${ALL_PROTOCOLS[@]}"; do
    if [[ "$p" == "$protocol" ]]; then
      return 0
    fi
  done
  return 1
}

validate_protocols_csv() {
  local protocols_csv="$1"
  local IFS=','
  local items=()
  read -r -a items <<< "$protocols_csv"

  if [[ "${#items[@]}" -eq 0 ]]; then
    die "At least one protocol is required"
  fi

  local protocol
  for protocol in "${items[@]}"; do
    protocol="$(echo "$protocol" | xargs)"
    if [[ -z "$protocol" ]]; then
      die "Empty protocol item in list"
    fi
    if ! contains_protocol "$protocol"; then
      die "Unsupported protocol: $protocol"
    fi
  done
}

validate_profile_protocols() {
  local profile="$1"
  local protocols_csv="$2"

  validate_protocols_csv "$protocols_csv"

  case "$profile" in
    lite)
      local count
      count="$(echo "$protocols_csv" | tr ',' '\n' | grep -c .)"
      if (( count > 2 )); then
        die "Lite profile allows up to 2 protocols"
      fi
      ;;
    full)
      return 0 ;;
    *)
      die "Unsupported profile: $profile" ;;
  esac
}

protocols_to_array() {
  local protocols_csv="$1"
  local _out_var="$2"
  local IFS=','
  local items=()
  read -r -a items <<< "$protocols_csv"

  local cleaned=()
  local protocol
  for protocol in "${items[@]}"; do
    protocol="$(echo "$protocol" | xargs)"
    [[ -n "$protocol" ]] && cleaned+=("$protocol")
  done

  # shellcheck disable=SC2034
  local -n out_ref="$_out_var"
  # shellcheck disable=SC2034
  out_ref=("${cleaned[@]}")
}

protocol_enabled() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

protocol_hint() {
  local protocol="$1"
  case "$protocol" in
    vless-reality)
      echo "risk=low;resource=low;note=default secure choice"
      ;;
    vmess-ws)
      echo "risk=medium;resource=low;note=easy CDN compatibility"
      ;;
    vless-xhttp)
      echo "risk=medium;resource=medium;note=requires xray runtime"
      ;;
    vless-ws)
      echo "risk=medium;resource=low;note=simple ws profile"
      ;;
    shadowsocks-2022)
      echo "risk=low;resource=low;note=password management required"
      ;;
    hysteria2)
      echo "risk=medium;resource=medium;note=udp heavy at high throughput"
      ;;
    tuic)
      echo "risk=medium;resource=medium;note=udp + tls cert overhead"
      ;;
    anytls)
      echo "risk=medium;resource=medium;note=less common client ecosystem"
      ;;
    any-reality)
      echo "risk=medium;resource=medium;note=reality key management required"
      ;;
    argo)
      echo "risk=medium;resource=low;note=depends on cloudflared stability"
      ;;
    warp)
      echo "risk=medium;resource=low;note=requires valid wireguard keys"
      ;;
    trojan)
      echo "risk=low;resource=low;note=tls cert hygiene required"
      ;;
    wireguard)
      echo "risk=medium;resource=low;note=needs peer config management"
      ;;
    *)
      echo "risk=unknown;resource=unknown;note=n/a"
      ;;
  esac
}
