#!/usr/bin/env bash

ALL_PROTOCOLS=(
  vless-reality
  vmess-ws
  vless-xhttp
  vless-ws
  shadowsocks-2022
  naive
  hysteria2
  tuic
  anytls
  any-reality
  trojan
  wireguard
  socks5
)

validate_provider() {
  local provider="$1"
  case "$provider" in
    vps|serv00|sap) return 0 ;;
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
  protocol_is_feature_token "$protocol" && return 0
  return 1
}

protocol_is_feature_token() {
  case "$1" in
    argo|warp) return 0 ;;
    *) return 1 ;;
  esac
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
  local protocols=()

  validate_protocols_csv "$protocols_csv"
  protocols_to_array "$protocols_csv" protocols
  if (( ${#protocols[@]} == 0 )); then
    die "At least one listener protocol is required"
  fi

  case "$profile" in
    lite)
      local count
      count="${#protocols[@]}"
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
    [[ -n "$protocol" ]] || continue
    protocol_is_feature_token "$protocol" && continue
    cleaned+=("$protocol")
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
    naive)
      echo "risk=medium;resource=medium;note=sing-box only; production needs a trusted certificate"
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
    trojan)
      echo "risk=low;resource=low;note=tls cert hygiene required"
      ;;
    wireguard)
      echo "risk=medium;resource=low;note=needs peer config management"
      ;;
    socks5)
      echo "risk=medium;resource=low;note=for app proxy integration, not public node sharing"
      ;;
    *)
      echo "risk=unknown;resource=unknown;note=n/a"
      ;;
  esac
}

protocol_capability() {
  local protocol="$1"
  case "$protocol" in
    vless-reality) echo "tls=yes;reality=yes;multi-port=yes;warp-egress=yes;share=yes" ;;
    vmess-ws) echo "tls=yes;reality=no;multi-port=yes;warp-egress=yes;share=yes" ;;
    vless-xhttp) echo "tls=yes;reality=optional;multi-port=yes;warp-egress=yes;share=yes" ;;
    vless-ws) echo "tls=yes;reality=no;multi-port=yes;warp-egress=yes;share=yes" ;;
    shadowsocks-2022) echo "tls=no;reality=no;multi-port=yes;warp-egress=yes;share=yes" ;;
    naive) echo "tls=yes;reality=no;multi-port=yes;warp-egress=yes;share=limited" ;;
    hysteria2) echo "tls=yes;reality=no;multi-port=yes;warp-egress=yes;share=yes" ;;
    tuic) echo "tls=yes;reality=no;multi-port=yes;warp-egress=yes;share=yes" ;;
    anytls) echo "tls=yes;reality=no;multi-port=yes;warp-egress=yes;share=yes" ;;
    any-reality) echo "tls=yes;reality=yes;multi-port=yes;warp-egress=yes;share=yes" ;;
    trojan) echo "tls=yes;reality=no;multi-port=yes;warp-egress=yes;share=yes" ;;
    wireguard) echo "tls=no;reality=no;multi-port=yes;warp-egress=yes;share=yes" ;;
    socks5) echo "tls=no;reality=no;multi-port=yes;warp-egress=yes;share=limited" ;;
    *) echo "tls=unknown;reality=unknown;multi-port=unknown;warp-egress=unknown;share=unknown" ;;
  esac
}

protocol_matrix_rows() {
  local engine="$1" include_unsupported="${2:-false}" protocol cap support
  for protocol in "${ALL_PROTOCOLS[@]}"; do
    support="no"
    if engine_supports_protocol "$engine" "$protocol"; then
      support="yes"
    elif [[ "$include_unsupported" != "true" ]]; then
      continue
    fi
    cap="$(protocol_capability "$protocol")"
    printf '%s|%s|%s\n' "$protocol" "$support" "$cap"
  done
}
