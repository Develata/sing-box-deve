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

warp_mode_targets_singbox() {
  local mode="${1:-off}"
  case "$mode" in
    off) return 1 ;;
    global|s|s4|s6|sx|xs|s4x4|s4x6|s6x4|s6x6|sx4|sx6|xs4|xs6|x4s|x6s|s4x|s6x|x4s4|x6s4|x4s6|x6s6) return 0 ;;
    x|x4|x6) return 1 ;;
    *) return 1 ;;
  esac
}

warp_mode_targets_xray() {
  local mode="${1:-off}"
  case "$mode" in
    off) return 1 ;;
    global|x|x4|x6|sx|xs|s4x4|s4x6|s6x4|s6x6|sx4|sx6|xs4|xs6|x4s|x6s|s4x|s6x|x4s4|x6s4|x4s6|x6s6) return 0 ;;
    s|s4|s6) return 1 ;;
    *) return 1 ;;
  esac
}

xray_domain_strategy_from_warp_mode() {
  local mode="${WARP_MODE:-off}"
  case "$mode" in
    *x4*) echo "ForceIPv4" ;;
    *x6*) echo "ForceIPv6" ;;
    *) echo "ForceIPv6v4" ;;
  esac
}

build_singbox_warp_route_json() {
  local mode="${WARP_MODE:-off}"
  case "$mode" in
    global|s|sx|xs)
      cat <<EOF
{"final":"warp-out"}
EOF
      ;;
    s4|s4x4|s4x6|sx4|x4s|s4x|x4s4|x4s6)
      cat <<EOF
{"rules":[{"ip_cidr":["0.0.0.0/0"],"outbound":"warp-out"}],"final":"direct"}
EOF
      ;;
    s6|s6x4|s6x6|sx6|x6s|s6x|x6s4|x6s6)
      cat <<EOF
{"rules":[{"ip_cidr":["::/0"],"outbound":"warp-out"}],"final":"direct"}
EOF
      ;;
    *)
      cat <<EOF
{"final":"direct"}
EOF
      ;;
  esac
}

build_singbox_route_json() {
  local proxy_tag="$1"
  local mode="${ROUTE_MODE:-direct}"
  validate_route_mode

  case "$mode" in
    direct)
      if [[ "$proxy_tag" == "warp-out" ]] && warp_mode_targets_singbox "${WARP_MODE:-off}"; then
        build_singbox_warp_route_json
        return 0
      fi
      cat <<EOF
{"final":"direct"}
EOF
      ;;
    global-proxy)
      [[ "$proxy_tag" != "direct" ]] || die "ROUTE_MODE=global-proxy requires outbound proxy or warp"
      cat <<EOF
{"final":"${proxy_tag}"}
EOF
      ;;
    cn-direct)
      [[ "$proxy_tag" != "direct" ]] || die "ROUTE_MODE=cn-direct requires outbound proxy or warp"
      cat <<EOF
{"rule_set":[{"tag":"geosite-cn","type":"remote","format":"binary","url":"https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/geolocation-cn.srs","download_detour":"direct","update_interval":"1d"},{"tag":"geoip-cn","type":"remote","format":"binary","url":"https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geoip/cn.srs","download_detour":"direct","update_interval":"1d"}],"rules":[{"rule_set":["geosite-cn","geoip-cn"],"outbound":"direct"}],"final":"${proxy_tag}"}
EOF
      ;;
    cn-proxy)
      [[ "$proxy_tag" != "direct" ]] || die "ROUTE_MODE=cn-proxy requires outbound proxy or warp"
      cat <<EOF
{"rule_set":[{"tag":"geosite-cn","type":"remote","format":"binary","url":"https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/geolocation-cn.srs","download_detour":"direct","update_interval":"1d"},{"tag":"geoip-cn","type":"remote","format":"binary","url":"https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geoip/cn.srs","download_detour":"direct","update_interval":"1d"}],"rules":[{"rule_set":["geosite-cn","geoip-cn"],"outbound":"${proxy_tag}"}],"final":"direct"}
EOF
      ;;
  esac
}

build_xray_routing_fragment() {
  local primary_tag="$1"
  local mode="${ROUTE_MODE:-direct}"
  validate_route_mode

  [[ -n "$primary_tag" ]] || primary_tag="direct"

  case "$mode" in
    direct)
      if [[ "$primary_tag" != "direct" ]]; then
        cat <<EOF
,
  "routing": {"domainStrategy": "AsIs", "rules": [{"type": "field", "network": "tcp,udp", "outboundTag": "${primary_tag}"}]}
EOF
      fi
      ;;
    global-proxy)
      [[ "$primary_tag" != "direct" ]] || die "ROUTE_MODE=global-proxy requires outbound proxy or warp"
      cat <<EOF
,
  "routing": {"domainStrategy": "AsIs", "rules": [{"type": "field", "network": "tcp,udp", "outboundTag": "${primary_tag}"}]}
EOF
      ;;
    cn-direct)
      [[ "$primary_tag" != "direct" ]] || die "ROUTE_MODE=cn-direct requires outbound proxy or warp"
      cat <<EOF
,
  "routing": {"domainStrategy": "AsIs", "rules": [{"type": "field", "domain": ["geosite:cn"], "outboundTag": "direct"}, {"type": "field", "ip": ["geoip:cn"], "outboundTag": "direct"}, {"type": "field", "network": "tcp,udp", "outboundTag": "${primary_tag}"}]}
EOF
      ;;
    cn-proxy)
      [[ "$primary_tag" != "direct" ]] || die "ROUTE_MODE=cn-proxy requires outbound proxy or warp"
      cat <<EOF
,
  "routing": {"domainStrategy": "AsIs", "rules": [{"type": "field", "domain": ["geosite:cn"], "outboundTag": "${primary_tag}"}, {"type": "field", "ip": ["geoip:cn"], "outboundTag": "${primary_tag}"}, {"type": "field", "network": "tcp,udp", "outboundTag": "direct"}]}
EOF
      ;;
  esac
}
