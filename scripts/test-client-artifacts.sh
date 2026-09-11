#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="$root_dir"
source "${PROJECT_ROOT}/lib/common.sh"
source "${PROJECT_ROOT}/lib/providers_params.sh"
source "${PROJECT_ROOT}/lib/protocol_links_common.sh"
source "${PROJECT_ROOT}/lib/protocol_links_direct.sh"
source "${PROJECT_ROOT}/lib/providers_node_model.sh"
source "${PROJECT_ROOT}/lib/providers_client_renderers.sh"
source "${PROJECT_ROOT}/lib/providers_client_templates.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT INT TERM HUP
SBD_INSTALL_DIR="${tmp_dir}/install"
SBD_DATA_DIR="${SBD_INSTALL_DIR}/data"
SBD_CONFIG_DIR="${tmp_dir}/config"
SBD_NODES_FILE="${SBD_DATA_DIR}/nodes.txt"
SBD_SUB_FILE="${SBD_DATA_DIR}/nodes-sub.txt"
SBD_NODE_MODEL_FILE="${SBD_DATA_DIR}/nodes-model.json"
export SBD_NODE_MODEL_FILE
mkdir -p "$SBD_DATA_DIR" "$SBD_CONFIG_DIR"

# sing-box Naive explicitly rejects tls.insecure. A legacy/self-signed Naive
# node must therefore be excluded instead of rendered as a falsely usable
# outbound. Supported installs require a trusted domain certificate.
node_model_init
node_model_add_naive 00000000-0000-4000-8000-000000000000 naive.example 443 naive.example true
jq -e '.nodes[0].singbox_compatible == false' "$SBD_NODE_MODEL_FILE" >/dev/null || \
  die "self-signed Naive node was not marked incompatible"
jq -e 'length == 0' <<< "$(singbox_client_proxy_outbounds)" >/dev/null || \
  die "self-signed Naive node was rendered despite unsupported tls.insecure"

node_model_init
node_model_add_vless_reality \
  11111111-1111-1111-1111-111111111111 2001:db8::10 443 www.microsoft.com chrome \
  jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0 0123456789abcdef
node_model_add_vless_ws \
  22222222-2222-4222-8222-222222222222 edge.example.com 8443 none /ws cdn.example.com \
  sbd-vless-ws true cdn.example.com
node_model_add_ss2022 MDEyMzQ1Njc4OWFiY2RlZg== 192.0.2.1 8388
node_model_add_naive 33333333-3333-4333-8333-333333333333 2001:db8::11 443 www.bing.com false
node_model_add_hysteria2 44444444-4444-4444-8444-444444444444 2001:db8::12 8443 www.bing.com true off ''
# Retained legacy models must not reintroduce the retired protocol into exports.
node_model_append '{"kind":"tuic","tag":"legacy-tuic","uuid":"55555555-5555-4555-8555-555555555555","password":"test-only","server":"192.0.2.13","port":10443,"sni":"example.com","insecure":false}'

node_model_render_uri_file "$SBD_NODES_FILE"
if grep -qi 'tuic' "$SBD_NODES_FILE"; then die "Retired TUIC URI was exported"; fi
base64 -w 0 < "$SBD_NODES_FILE" > "$SBD_SUB_FILE"
grep -Fq '@[2001:db8::10]:443' "$SBD_NODES_FILE" || die "IPv6 URI authority is not bracketed"
grep -Fq '@[2001:db8::11]:443' "$SBD_NODES_FILE" || die "Naive IPv6 URI authority is not bracketed"
grep -Fq '@[2001:db8::12]:8443' "$SBD_NODES_FILE" || die "Hysteria2 IPv6 URI authority is not bracketed"

sing_client="${SBD_DATA_DIR}/sing_box_client.json"
render_singbox_client_json "$sing_client"
if grep -qi 'tuic' "$sing_client"; then die "Retired TUIC sing-box outbound was exported"; fi
jq -e '
  any(.outbounds[]; .type == "vless" and .tag == "sbd-vless-reality") and
  any(.outbounds[]; .type == "shadowsocks" and .tag == "sbd-shadowsocks-2022") and
  any(.outbounds[]; .type == "naive" and .tag == "sbd-naive" and (.tls | has("insecure") | not)) and
  (any(.outbounds[]; .type == "block") | not) and
  (.outbounds[] | select(.tag == "auto") | .outbounds | length >= 3) and
  (.inbounds[] | has("sniff") | not) and
  (.inbounds[] | has("domain_strategy") | not) and
  all(.dns.servers[]; has("type")) and
  any(.route.rules[]; .action == "sniff")
' "$sing_client" >/dev/null || die "sing-box client is missing real proxies or still uses legacy fields"

if [[ -n "${SBD_TEST_SINGBOX_BIN:-}" ]]; then
  mkdir -p "${SBD_DATA_DIR}/sing-ruleset"
  cp "${PROJECT_ROOT}/rulesets/sing/geosite-cn.srs" "${SBD_DATA_DIR}/sing-ruleset/"
  cp "${PROJECT_ROOT}/rulesets/sing/geoip-cn.srs" "${SBD_DATA_DIR}/sing-ruleset/"
  (cd "$SBD_DATA_DIR" && "$SBD_TEST_SINGBOX_BIN" check -c "$sing_client")
fi

clash_client="${SBD_DATA_DIR}/clash_meta_client.yaml"
render_clash_meta_yaml "$clash_client"
if grep -qi 'tuic' "$clash_client"; then die "Retired TUIC Clash proxy was exported"; fi
proxy_json="$(sed -n 's/^proxies: //p' "$clash_client" | head -n1)"
jq -e 'length >= 3 and any(.[]; .name == "sbd-vless-reality")' <<< "$proxy_json" >/dev/null || \
  die "Clash client does not contain real proxies"
grep -Fq 'proxies: ["sbd-vless-reality"' "$clash_client" || die "AUTO group does not reference real proxies"
python3 - "$clash_client" <<'PY'
import sys
import yaml

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    config = yaml.safe_load(handle)
proxies = config.get("proxies") or []
groups = config.get("proxy-groups") or []
assert proxies and any(item.get("name") == "sbd-vless-reality" for item in proxies)
assert groups and all(group.get("proxies") for group in groups)
PY

printf '[OK] structured client artifact checks passed\n'
