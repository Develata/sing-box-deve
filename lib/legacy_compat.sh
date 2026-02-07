#!/usr/bin/env bash
# shellcheck disable=SC2034

legacy_env_detected() {
  local keys=(vlpt vmpt vwpt xhpt vxpt sspt anpt arpt hypt tupt sopt argo agn agk warp)
  local k
  for k in "${keys[@]}"; do
    [[ -n "${!k:-}" ]] && return 0
  done
  return 1
}

legacy_set_port_override() {
  local protocol="$1"
  local val="$2"
  [[ -n "$val" ]] || return 0
  [[ "$val" =~ ^[0-9]+$ ]] || die "Legacy port for ${protocol} must be numeric"
  (( val >= 1 && val <= 65535 )) || die "Legacy port for ${protocol} must be 1..65535"
  local key
  key="SBD_PORT_$(echo "$protocol" | tr '[:lower:]-' '[:upper:]_')"
  printf -v "$key" '%s' "$val"
  export "${key}=${!key}"
}

legacy_apply_install_defaults() {
  legacy_env_detected || return 0

  PROVIDER="vps"
  PROFILE="full"
  AUTO_YES="true"

  local protocols=()
  add_legacy_proto() {
    local p="$1"
    case " ${protocols[*]} " in
      *" $p "*) ;;
      *) protocols+=("$p") ;;
    esac
  }

  [[ -n "${vlpt:-}" ]] && add_legacy_proto "vless-reality" && legacy_set_port_override "vless-reality" "${vlpt}"
  [[ -n "${vmpt:-}" ]] && add_legacy_proto "vmess-ws" && legacy_set_port_override "vmess-ws" "${vmpt}"
  [[ -n "${vwpt:-}" ]] && add_legacy_proto "vless-ws" && legacy_set_port_override "vless-ws" "${vwpt}"
  [[ -n "${xhpt:-}" ]] && add_legacy_proto "vless-xhttp" && legacy_set_port_override "vless-xhttp" "${xhpt}" && export SBD_XHTTP_REALITY_ENC="true"
  [[ -n "${vxpt:-}" ]] && add_legacy_proto "vless-xhttp" && legacy_set_port_override "vless-xhttp" "${vxpt}"
  [[ -n "${sspt:-}" ]] && add_legacy_proto "shadowsocks-2022" && legacy_set_port_override "shadowsocks-2022" "${sspt}"
  [[ -n "${anpt:-}" ]] && add_legacy_proto "anytls" && legacy_set_port_override "anytls" "${anpt}"
  [[ -n "${arpt:-}" ]] && add_legacy_proto "any-reality" && legacy_set_port_override "any-reality" "${arpt}"
  [[ -n "${hypt:-}" ]] && add_legacy_proto "hysteria2" && legacy_set_port_override "hysteria2" "${hypt}"
  [[ -n "${tupt:-}" ]] && add_legacy_proto "tuic" && legacy_set_port_override "tuic" "${tupt}"
  [[ -n "${sopt:-}" ]] && add_legacy_proto "socks5" && legacy_set_port_override "socks5" "${sopt}"

  if [[ -n "${argo:-}" ]]; then
    add_legacy_proto "argo"
    if [[ "$argo" == "vmpt" ]]; then
      add_legacy_proto "vmess-ws"
    elif [[ "$argo" == "vwpt" ]]; then
      add_legacy_proto "vless-ws"
    fi
  fi

  if [[ "${warp:-}" != "" ]]; then
    add_legacy_proto "warp"
    case "${warp}" in
      sx|xs|s|s4|s6|x|x4|x6|s4x4|s4x6|s6x4|s6x6|sx4|sx6|xs4|xs6|x4s|x6s|s4x|s6x|x4s4|x6s4|x4s6|x6s6)
        WARP_MODE="${warp}"
        ;;
      *)
        WARP_MODE="global"
        ;;
    esac
  fi

  if [[ -n "${agn:-}" && -n "${agk:-}" ]]; then
    ARGO_MODE="fixed"
    ARGO_DOMAIN="${agn}"
    ARGO_TOKEN="${agk}"
  elif [[ " ${protocols[*]} " == *" argo "* ]]; then
    ARGO_MODE="temp"
  fi

  local need_xray="false"
  local need_sing="false"
  local p
  for p in "${protocols[@]}"; do
    case "$p" in
      vless-xhttp|socks5) need_xray="true" ;;
      shadowsocks-2022|hysteria2|tuic|anytls|any-reality|warp|wireguard) need_sing="true" ;;
    esac
  done
  if [[ "$need_xray" == "true" && "$need_sing" == "true" ]]; then
    die "Legacy mixed protocol set needs both engines; split into separate installs"
  fi

  if [[ "$need_xray" == "true" ]]; then
    ENGINE="xray"
  else
    ENGINE="sing-box"
  fi

  if [[ "${#protocols[@]}" -eq 0 ]]; then
    protocols=("vless-reality")
  fi
  PROTOCOLS="$(IFS=,; echo "${protocols[*]}")"
}
