#!/usr/bin/env bash

build_client_names_csv() {
  local names
  names="$(awk -F'#' '/#/{print $NF}' "$SBD_NODES_FILE" | sed 's/^ *//;s/ *$//' | grep -v '^$' | paste -sd ',' -)"
  echo "${names:-sbd-default}"
}

render_singbox_client_json() {
  local out_file="$1"
  local names_csv names_json
  names_csv="$(build_client_names_csv)"
  names_json="[$(printf '%s' "$names_csv" | awk -F, '{for(i=1;i<=NF;i++){gsub(/^ +| +$/, "", $i); if(length($i)){printf "%s\"%s\"", (j++?",":""), $i}}}')]"

  cat > "$out_file" <<EOF
{
  "log": {"level": "warn"},
  "experimental": {
    "clash_api": {
      "external_controller": "127.0.0.1:9090",
      "external_ui": "ui",
      "external_ui_download_url": "",
      "default_mode": "Rule"
    }
  },
  "dns": {
    "servers": [
      {"tag":"dns-remote","address":"https://1.1.1.1/dns-query","detour":"select"},
      {"tag":"dns-local","address":"223.5.5.5","detour":"direct"}
    ],
    "rules": [
      {"rule_set":["geosite-cn"],"server":"dns-local"},
      {"rule_set":["geosite-geolocation-!cn"],"server":"dns-remote"}
    ],
    "strategy": "prefer_ipv4"
  },
  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "address": ["172.19.0.1/30", "fd00::1/126"],
      "auto_route": true,
      "strict_route": true,
      "sniff": true,
      "sniff_override_destination": true,
      "domain_strategy": "prefer_ipv4"
    }
  ],
  "outbounds": [
    {"type":"selector","tag":"select","default":"auto","outbounds":["auto","direct","block"]},
    {"type":"urltest","tag":"auto","outbounds":["direct"],"url":"https://www.gstatic.com/generate_204","interval":"3m"},
    {"type":"direct","tag":"direct"},
    {"type":"block","tag":"block"}
  ],
  "route": {
    "rule_set": [
      {"tag":"geosite-geolocation-!cn","type":"remote","format":"binary","url":"https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/geolocation-!cn.srs","download_detour":"direct","update_interval":"1d"},
      {"tag":"geosite-cn","type":"remote","format":"binary","url":"https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/geolocation-cn.srs","download_detour":"direct","update_interval":"1d"},
      {"tag":"geoip-cn","type":"remote","format":"binary","url":"https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geoip/cn.srs","download_detour":"direct","update_interval":"1d"}
    ],
    "rules": [
      {"rule_set":["geosite-cn","geoip-cn"],"outbound":"direct"},
      {"clash_mode":"Direct","outbound":"direct"},
      {"clash_mode":"Global","outbound":"select"}
    ],
    "final": "select"
  },
  "sbd_subscription": {
    "aggregate_base64": "$(cat "$SBD_SUB_FILE")",
    "node_names": ${names_json},
    "nodes_file": "${SBD_NODES_FILE}"
  }
}
EOF
}

render_clash_meta_yaml() {
  local out_file="$1"
  cat > "$out_file" <<EOF
# sing-box-deve clash-meta template
# generated_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
mixed-port: 7890
allow-lan: false
mode: rule
log-level: info

dns:
  enable: true
  ipv6: true
  nameserver:
    - 223.5.5.5
    - 119.29.29.29
  fallback:
    - https://1.1.1.1/dns-query
    - https://8.8.8.8/dns-query

proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - AUTO
      - DIRECT
  - name: AUTO
    type: url-test
    url: https://www.gstatic.com/generate_204
    interval: 180
    proxies:
      - DIRECT

rules:
  - GEOSITE,cn,DIRECT
  - GEOIP,cn,DIRECT
  - MATCH,PROXY

# aggregate_base64:
# $(cat "$SBD_SUB_FILE")
# nodes:
EOF
  sed 's/^/# /' "$SBD_NODES_FILE" >> "$out_file"
}

render_sfa_sfi_sfw() {
  local app="$1" out_file="$2"
  cat > "$out_file" <<EOF
{
  "app": "${app}",
  "generated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "subscription_base64": "$(cat "$SBD_SUB_FILE")",
  "nodes_file": "${SBD_NODES_FILE}",
  "hint": "import aggregate_base64 as subscription"
}
EOF
}
