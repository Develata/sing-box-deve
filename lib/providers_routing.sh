#!/usr/bin/env bash

validate_route_mode() {
  case "${ROUTE_MODE:-direct}" in
    direct|global-proxy|cn-direct|cn-proxy) ;;
    *) die "Invalid ROUTE_MODE: ${ROUTE_MODE}" ;;
  esac
}

build_singbox_route_json() {
  local proxy_tag="$1"
  local mode="${ROUTE_MODE:-direct}"
  validate_route_mode

  case "$mode" in
    direct)
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
  local proxy_tag="$1"
  local mode="${ROUTE_MODE:-direct}"
  validate_route_mode

  case "$mode" in
    direct)
      if [[ "$proxy_tag" == "proxy-out" ]]; then
        cat <<EOF
,
  "routing": {"domainStrategy": "AsIs", "rules": [{"type": "field", "network": "tcp,udp", "outboundTag": "direct"}]}
EOF
      fi
      ;;
    global-proxy)
      [[ "$proxy_tag" == "proxy-out" ]] || die "ROUTE_MODE=global-proxy requires outbound proxy"
      cat <<EOF
,
  "routing": {"domainStrategy": "AsIs", "rules": [{"type": "field", "network": "tcp,udp", "outboundTag": "proxy-out"}]}
EOF
      ;;
    cn-direct)
      [[ "$proxy_tag" == "proxy-out" ]] || die "ROUTE_MODE=cn-direct requires outbound proxy"
      cat <<EOF
,
  "routing": {"domainStrategy": "AsIs", "rules": [{"type": "field", "domain": ["geosite:cn"], "outboundTag": "direct"}, {"type": "field", "ip": ["geoip:cn"], "outboundTag": "direct"}, {"type": "field", "network": "tcp,udp", "outboundTag": "proxy-out"}]}
EOF
      ;;
    cn-proxy)
      [[ "$proxy_tag" == "proxy-out" ]] || die "ROUTE_MODE=cn-proxy requires outbound proxy"
      cat <<EOF
,
  "routing": {"domainStrategy": "AsIs", "rules": [{"type": "field", "domain": ["geosite:cn"], "outboundTag": "proxy-out"}, {"type": "field", "ip": ["geoip:cn"], "outboundTag": "proxy-out"}, {"type": "field", "network": "tcp,udp", "outboundTag": "direct"}]}
EOF
      ;;
  esac
}
