#!/usr/bin/env bash

validate_route_mode() {
  case "${ROUTE_MODE:-direct}" in
    direct|global-proxy|cn-direct|cn-proxy) ;;
    *) die "Invalid ROUTE_MODE: ${ROUTE_MODE}" ;;
  esac
}

validate_warp_mode_extended() {
  case "${WARP_MODE:-off}" in
    off|global|s|s4|s6|sx|xs|x|x4|x6|s4x4|s4x6|s6x4|s6x6|sx4|sx6|xs4|xs6|x4s|x6s|s4x|s6x|x4s4|x6s4|x4s6|x6s6) ;;
    *) die "Invalid WARP_MODE: ${WARP_MODE}" ;;
  esac
}

csv_to_json_array() {
  local csv="$1" out="[" first=true item
  IFS=',' read -r -a _items <<< "$csv"
  for item in "${_items[@]}"; do
    item="$(echo "$item" | xargs)"
    [[ -n "$item" ]] || continue
    if [[ "$first" == true ]]; then
      out+="\"${item}\""
      first=false
    else
      out+=",\"${item}\""
    fi
  done
  out+="]"
  echo "$out"
}

build_custom_domain_rules_singbox() {
  local primary_tag="$1" rules="" direct_arr proxy_arr block_arr
  direct_arr="$(csv_to_json_array "${DOMAIN_SPLIT_DIRECT:-}")"
  proxy_arr="$(csv_to_json_array "${DOMAIN_SPLIT_PROXY:-}")"
  block_arr="$(csv_to_json_array "${DOMAIN_SPLIT_BLOCK:-}")"

  if [[ "$direct_arr" != "[]" ]]; then
    rules+="{\"domain_suffix\":${direct_arr},\"outbound\":\"direct\"}"
  fi
  if [[ "$proxy_arr" != "[]" && "$primary_tag" != "direct" ]]; then
    [[ -n "$rules" ]] && rules+=","
    rules+="{\"domain_suffix\":${proxy_arr},\"outbound\":\"${primary_tag}\"}"
  fi
  if [[ "$block_arr" != "[]" ]]; then
    [[ -n "$rules" ]] && rules+=","
    rules+="{\"domain_suffix\":${block_arr},\"outbound\":\"block\"}"
  fi
  echo "$rules"
}

build_custom_domain_rules_xray() {
  local primary_tag="$1" rules="" direct_csv proxy_csv block_csv
  direct_csv="${DOMAIN_SPLIT_DIRECT:-}"
  proxy_csv="${DOMAIN_SPLIT_PROXY:-}"
  block_csv="${DOMAIN_SPLIT_BLOCK:-}"

  if [[ -n "$direct_csv" ]]; then
    rules+="{\"type\":\"field\",\"domain\":[$(printf '%s' "$direct_csv" | awk -F, '{for(i=1;i<=NF;i++){gsub(/^ +| +$/, "", $i); if(length($i)){printf "%s\"domain:%s\"", (j++?",":""), $i}}}')],\"outboundTag\":\"direct\"}"
  fi
  if [[ -n "$proxy_csv" && "$primary_tag" != "direct" ]]; then
    [[ -n "$rules" ]] && rules+=","
    rules+="{\"type\":\"field\",\"domain\":[$(printf '%s' "$proxy_csv" | awk -F, '{for(i=1;i<=NF;i++){gsub(/^ +| +$/, "", $i); if(length($i)){printf "%s\"domain:%s\"", (j++?",":""), $i}}}')],\"outboundTag\":\"${primary_tag}\"}"
  fi
  if [[ -n "$block_csv" ]]; then
    [[ -n "$rules" ]] && rules+=","
    rules+="{\"type\":\"field\",\"domain\":[$(printf '%s' "$block_csv" | awk -F, '{for(i=1;i<=NF;i++){gsub(/^ +| +$/, "", $i); if(length($i)){printf "%s\"domain:%s\"", (j++?",":""), $i}}}')],\"outboundTag\":\"block\"}"
  fi
  echo "$rules"
}

warp_mode_targets_singbox() {
  case "${1:-off}" in
    off|x|x4|x6) return 1 ;;
    *) return 0 ;;
  esac
}

warp_mode_targets_xray() {
  case "${1:-off}" in
    off|s|s4|s6) return 1 ;;
    *) return 0 ;;
  esac
}

xray_domain_strategy_from_warp_mode() {
  case "${WARP_MODE:-off}" in
    *x4*) echo "ForceIPv4" ;;
    *x6*) echo "ForceIPv6" ;;
    *) echo "ForceIPv6v4" ;;
  esac
}

build_singbox_warp_route_json() {
  case "${WARP_MODE:-off}" in
    global|s|sx|xs) echo '{"final":"warp-out"}' ;;
    s4|s4x4|s4x6|sx4|x4s|s4x|x4s4|x4s6) echo '{"rules":[{"ip_cidr":["0.0.0.0/0"],"outbound":"warp-out"}],"final":"direct"}' ;;
    s6|s6x4|s6x6|sx6|x6s|s6x|x6s4|x6s6) echo '{"rules":[{"ip_cidr":["::/0"],"outbound":"warp-out"}],"final":"direct"}' ;;
    *) echo '{"final":"direct"}' ;;
  esac
}

build_singbox_route_json() {
  local primary_tag="$1" inbound_map="${2:-}" available_outbounds="${3:-direct}" mode="${ROUTE_MODE:-direct}" rules="" rule_set="" final="direct" custom port_rules
  validate_route_mode

  if [[ "$mode" == "direct" && "$primary_tag" == "warp-out" ]] && warp_mode_targets_singbox "${WARP_MODE:-off}"; then
    port_rules="$(build_port_egress_rules_singbox "${PORT_EGRESS_MAP:-}" "$inbound_map" "$available_outbounds")"
    local base_rules="" base_final="direct"
    case "${WARP_MODE:-off}" in
      global|s|sx|xs)
        base_final="warp-out"
        ;;
      s4|s4x4|s4x6|sx4|x4s|s4x|x4s4|x4s6)
        base_rules='{"ip_cidr":["0.0.0.0/0"],"outbound":"warp-out"}'
        ;;
      s6|s6x4|s6x6|sx6|x6s|s6x|x6s4|x6s6)
        base_rules='{"ip_cidr":["::/0"],"outbound":"warp-out"}'
        ;;
      *)
        base_final="direct"
        ;;
    esac
    rules="${port_rules}"
    [[ -n "$base_rules" ]] && rules+="${rules:+,}${base_rules}"
    if [[ -n "$rules" ]]; then
      echo "{\"rules\":[${rules}],\"final\":\"${base_final}\"}"
    else
      echo "{\"final\":\"${base_final}\"}"
    fi
    return 0
  fi

  case "$mode" in
    direct)
      final="direct"
      ;;
    global-proxy)
      [[ "$primary_tag" != "direct" ]] || die "ROUTE_MODE=global-proxy requires proxy or warp"
      final="$primary_tag"
      ;;
    cn-direct)
      [[ "$primary_tag" != "direct" ]] || die "ROUTE_MODE=cn-direct requires proxy or warp"
      rule_set='"rule_set":[{"tag":"geosite-cn","type":"remote","format":"binary","url":"https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/geolocation-cn.srs","download_detour":"direct","update_interval":"1d"},{"tag":"geoip-cn","type":"remote","format":"binary","url":"https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geoip/cn.srs","download_detour":"direct","update_interval":"1d"}]'
      rules='{"rule_set":["geosite-cn","geoip-cn"],"outbound":"direct"}'
      final="$primary_tag"
      ;;
    cn-proxy)
      [[ "$primary_tag" != "direct" ]] || die "ROUTE_MODE=cn-proxy requires proxy or warp"
      rule_set='"rule_set":[{"tag":"geosite-cn","type":"remote","format":"binary","url":"https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/geolocation-cn.srs","download_detour":"direct","update_interval":"1d"},{"tag":"geoip-cn","type":"remote","format":"binary","url":"https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geoip/cn.srs","download_detour":"direct","update_interval":"1d"}]'
      rules="{\"rule_set\":[\"geosite-cn\",\"geoip-cn\"],\"outbound\":\"${primary_tag}\"}"
      final="direct"
      ;;
  esac

  custom="$(build_custom_domain_rules_singbox "$primary_tag")"
  [[ -n "$custom" ]] && rules+="${rules:+,}${custom}"
  port_rules="$(build_port_egress_rules_singbox "${PORT_EGRESS_MAP:-}" "$inbound_map" "$available_outbounds")"
  [[ -n "$port_rules" ]] && rules="${port_rules}${rules:+,}${rules}"

  if [[ -z "$rule_set" && -z "$rules" ]]; then
    echo "{\"final\":\"${final}\"}"
  elif [[ -z "$rule_set" ]]; then
    echo "{\"rules\":[${rules}],\"final\":\"${final}\"}"
  elif [[ -z "$rules" ]]; then
    echo "{${rule_set},\"final\":\"${final}\"}"
  else
    echo "{${rule_set},\"rules\":[${rules}],\"final\":\"${final}\"}"
  fi
}

build_xray_routing_fragment() {
  local primary_tag="$1" inbound_map="${2:-}" available_outbounds="${3:-direct}" mode="${ROUTE_MODE:-direct}" ds="AsIs" rules="" custom port_rules
  validate_route_mode
  [[ -n "$primary_tag" ]] || primary_tag="direct"
  [[ "${IP_PREFERENCE:-auto}" == "v4" ]] && ds="UseIPv4"
  [[ "${IP_PREFERENCE:-auto}" == "v6" ]] && ds="UseIPv6"

  case "$mode" in
    direct)
      [[ "$primary_tag" != "direct" ]] && rules="{\"type\":\"field\",\"network\":\"tcp,udp\",\"outboundTag\":\"${primary_tag}\"}"
      ;;
    global-proxy)
      [[ "$primary_tag" != "direct" ]] || die "ROUTE_MODE=global-proxy requires proxy or warp"
      rules="{\"type\":\"field\",\"network\":\"tcp,udp\",\"outboundTag\":\"${primary_tag}\"}"
      ;;
    cn-direct)
      [[ "$primary_tag" != "direct" ]] || die "ROUTE_MODE=cn-direct requires proxy or warp"
      rules="{\"type\":\"field\",\"domain\":[\"geosite:cn\"],\"outboundTag\":\"direct\"},{\"type\":\"field\",\"ip\":[\"geoip:cn\"],\"outboundTag\":\"direct\"},{\"type\":\"field\",\"network\":\"tcp,udp\",\"outboundTag\":\"${primary_tag}\"}"
      ;;
    cn-proxy)
      [[ "$primary_tag" != "direct" ]] || die "ROUTE_MODE=cn-proxy requires proxy or warp"
      rules="{\"type\":\"field\",\"domain\":[\"geosite:cn\"],\"outboundTag\":\"${primary_tag}\"},{\"type\":\"field\",\"ip\":[\"geoip:cn\"],\"outboundTag\":\"${primary_tag}\"},{\"type\":\"field\",\"network\":\"tcp,udp\",\"outboundTag\":\"direct\"}"
      ;;
  esac

  custom="$(build_custom_domain_rules_xray "$primary_tag")"
  [[ -n "$custom" ]] && rules+="${rules:+,}${custom}"
  port_rules="$(build_port_egress_rules_xray "${PORT_EGRESS_MAP:-}" "$inbound_map" "$available_outbounds")"
  [[ -n "$port_rules" ]] && rules="${port_rules}${rules:+,}${rules}"
  [[ -n "$rules" ]] || return 0

  cat <<EOF
,
  "routing": {"domainStrategy": "${ds}", "rules": [${rules}]}
EOF
}
