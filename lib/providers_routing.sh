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
    item="$(sbd_trim_whitespace "$item")"
    [[ -n "$item" ]] || continue
    if [[ "$first" == true ]]; then
      out+="$(sbd_json_string "$item")"
      first=false
    else
      out+=",$(sbd_json_string "$item")"
    fi
  done
  out+="]"
  echo "$out"
}

csv_to_xray_domain_array() {
  local csv="$1" out="" item domain
  IFS=',' read -r -a _items <<< "$csv"
  for item in "${_items[@]}"; do
    item="$(sbd_trim_whitespace "$item")"
    [[ -n "$item" ]] || continue
    domain="domain:${item}"
    out+="${out:+,}$(sbd_json_string "$domain")"
  done
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
    rules+="{\"domain_suffix\":${block_arr},\"action\":\"reject\"}"
  fi
  echo "$rules"
}

build_custom_domain_rules_xray() {
  local primary_tag="$1" rules="" direct_csv proxy_csv block_csv
  local direct_arr proxy_arr block_arr
  direct_csv="${DOMAIN_SPLIT_DIRECT:-}"
  proxy_csv="${DOMAIN_SPLIT_PROXY:-}"
  block_csv="${DOMAIN_SPLIT_BLOCK:-}"
  direct_arr="$(csv_to_xray_domain_array "$direct_csv")"
  proxy_arr="$(csv_to_xray_domain_array "$proxy_csv")"
  block_arr="$(csv_to_xray_domain_array "$block_csv")"

  if [[ -n "$direct_arr" ]]; then
    rules+="{\"type\":\"field\",\"domain\":[${direct_arr}],\"outboundTag\":\"direct\"}"
  fi
  if [[ -n "$proxy_arr" && "$primary_tag" != "direct" ]]; then
    [[ -n "$rules" ]] && rules+=","
    rules+="{\"type\":\"field\",\"domain\":[${proxy_arr}],\"outboundTag\":\"${primary_tag}\"}"
  fi
  if [[ -n "$block_arr" ]]; then
    [[ -n "$rules" ]] && rules+=","
    rules+="{\"type\":\"field\",\"domain\":[${block_arr}],\"outboundTag\":\"block\"}"
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
    s4|s4x4|s4x6|sx4|xs4|x4s|s4x|x4s4|x4s6) echo '{"rules":[{"ip_cidr":["0.0.0.0/0"],"outbound":"warp-out"}],"final":"direct"}' ;;
    s6|s6x4|s6x6|sx6|xs6|x6s|s6x|x6s4|x6s6) echo '{"rules":[{"ip_cidr":["::/0"],"outbound":"warp-out"}],"final":"direct"}' ;;
    *) echo '{"final":"direct"}' ;;
  esac
}

build_singbox_proxy_udp_rule() {
  [[ "${OUTBOUND_PROXY_MODE:-direct}" != "direct" ]] || return 0
  case "${OUTBOUND_PROXY_UDP_MODE:-proxy}" in
    proxy) ;;
    direct) echo '{"network":"udp","outbound":"direct"}' ;;
    block) echo '{"network":"udp","action":"reject"}' ;;
  esac
}

build_xray_proxy_udp_rule() {
  [[ "${OUTBOUND_PROXY_MODE:-direct}" != "direct" ]] || return 0
  case "${OUTBOUND_PROXY_UDP_MODE:-proxy}" in
    proxy) ;;
    direct) echo '{"type":"field","network":"udp","outboundTag":"direct"}' ;;
    block) echo '{"type":"field","network":"udp","outboundTag":"block"}' ;;
  esac
}

build_singbox_route_json() {
  local primary_tag="$1" mode="${ROUTE_MODE:-direct}" rules="" rule_set="" final="direct" custom udp_rule
  validate_route_mode
  if [[ "$mode" == "cn-direct" || "$mode" == "cn-proxy" ]]; then
    # Callers capture this function's stdout as JSON.
    ensure_sing_route_rulesets_local >&2
  fi

  if [[ "$mode" == "direct" && "$primary_tag" == "warp-out" ]] && warp_mode_targets_singbox "${WARP_MODE:-off}"; then
    local base_rules="" base_final="direct"
    case "${WARP_MODE:-off}" in
      global|s|sx|xs)
        base_final="warp-out"
        ;;
      s4|s4x4|s4x6|sx4|xs4|x4s|s4x|x4s4|x4s6)
        base_rules='{"ip_cidr":["0.0.0.0/0"],"outbound":"warp-out"}'
        ;;
      s6|s6x4|s6x6|sx6|xs6|x6s|s6x|x6s4|x6s6)
        base_rules='{"ip_cidr":["::/0"],"outbound":"warp-out"}'
        ;;
      *)
        base_final="direct"
        ;;
    esac
    rules=""
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
      rule_set="$(build_sing_route_rule_set_json)"
      rules='{"rule_set":["geosite-cn","geoip-cn"],"outbound":"direct"}'
      final="$primary_tag"
      ;;
    cn-proxy)
      [[ "$primary_tag" != "direct" ]] || die "ROUTE_MODE=cn-proxy requires proxy or warp"
      rule_set="$(build_sing_route_rule_set_json)"
      rules="{\"rule_set\":[\"geosite-cn\",\"geoip-cn\"],\"outbound\":\"${primary_tag}\"}"
      final="direct"
      ;;
  esac

  udp_rule="$(build_singbox_proxy_udp_rule)"
  [[ -n "$udp_rule" ]] && rules="${udp_rule}${rules:+,${rules}}"
  custom="$(build_custom_domain_rules_singbox "$primary_tag")"
  [[ -n "$custom" ]] && rules+="${rules:+,}${custom}"

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
  local primary_tag="$1" mode="${ROUTE_MODE:-direct}" rules="" catch_all="" custom udp_rule
  validate_route_mode
  [[ -n "$primary_tag" ]] || primary_tag="direct"

  case "$mode" in
    direct)
      ;;
    global-proxy)
      [[ "$primary_tag" != "direct" ]] || die "ROUTE_MODE=global-proxy requires proxy or warp"
      catch_all="{\"type\":\"field\",\"network\":\"tcp,udp\",\"outboundTag\":\"${primary_tag}\"}"
      ;;
    cn-direct)
      [[ "$primary_tag" != "direct" ]] || die "ROUTE_MODE=cn-direct requires proxy or warp"
      rules="{\"type\":\"field\",\"domain\":[\"geosite:cn\"],\"outboundTag\":\"direct\"},{\"type\":\"field\",\"ip\":[\"geoip:cn\"],\"outboundTag\":\"direct\"}"
      catch_all="{\"type\":\"field\",\"network\":\"tcp,udp\",\"outboundTag\":\"${primary_tag}\"}"
      ;;
    cn-proxy)
      [[ "$primary_tag" != "direct" ]] || die "ROUTE_MODE=cn-proxy requires proxy or warp"
      rules="{\"type\":\"field\",\"domain\":[\"geosite:cn\"],\"outboundTag\":\"${primary_tag}\"},{\"type\":\"field\",\"ip\":[\"geoip:cn\"],\"outboundTag\":\"${primary_tag}\"}"
      catch_all='{"type":"field","network":"tcp,udp","outboundTag":"direct"}'
      ;;
  esac

  udp_rule="$(build_xray_proxy_udp_rule)"
  [[ -n "$udp_rule" ]] && rules="${udp_rule}${rules:+,${rules}}"
  custom="$(build_custom_domain_rules_xray "$primary_tag")"
  [[ -n "$custom" ]] && rules+="${rules:+,}${custom}"
  [[ -n "$catch_all" ]] && rules+="${rules:+,}${catch_all}"
  [[ -n "$rules" ]] || return 0

  cat <<EOF
,
  "routing": {"domainStrategy": "AsIs", "rules": [${rules}]}
EOF
}
