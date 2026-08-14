#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

assert_jq() {
  local file="$1" query="$2" message="$3"
  jq -e "$query" "$file" >/dev/null || fail "$message"
}

assert_socks_outbounds() {
  local file="$1" message="$2"
  assert_jq "$file" '([.outbounds[].tag] | sort) == ["direct","proxy-out"]
    and any(.outbounds[]; .tag == "direct" and .type == "direct")
    and all(.outbounds[]; .type != "block")
    and any(.outbounds[]; .tag == "proxy-out" and .type == "socks"
      and .server == "192.0.2.10" and .server_port == 1080)' "$message"
}

assert_runtime_udp() {
  local file="$1" mode="$2" message="$3"
  grep -q "^outbound_proxy_udp_mode=\"${mode}\"$" "$file" || fail "$message"
}

export HOME="${TMP_DIR}/home"
mkdir -p "$HOME"

# shellcheck disable=SC2034
PROJECT_ROOT="$ROOT_DIR"
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/protocols.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/security.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/providers.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/cli_args.sh"

SBD_STATE_DIR="${TMP_DIR}/state"
SBD_CONFIG_DIR="${TMP_DIR}/config"
SBD_DATA_DIR="${TMP_DIR}/data"
SBD_BIN_DIR="${TMP_DIR}/bin"
SBD_CACHE_DIR="${TMP_DIR}/cache"
mkdir -p "$SBD_STATE_DIR" "$SBD_CONFIG_DIR" "$SBD_DATA_DIR" "$SBD_BIN_DIR" "$SBD_CACHE_DIR"

if [[ -n "${SBD_TEST_SINGBOX_BIN:-}" ]]; then
  install -m 0755 "$SBD_TEST_SINGBOX_BIN" "${SBD_BIN_DIR}/sing-box"
else
  cat > "${SBD_BIN_DIR}/sing-box" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "${SBD_BIN_DIR}/sing-box"
fi
if [[ -n "${SBD_TEST_XRAY_BIN:-}" ]]; then
  install -m 0755 "$SBD_TEST_XRAY_BIN" "${SBD_BIN_DIR}/xray"
fi
printf '%s\n' '11111111-1111-4111-8111-111111111111' > "${SBD_DATA_DIR}/uuid"
printf '%s\n' 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' > "${SBD_DATA_DIR}/reality_private.key"
printf '%s\n' 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB' > "${SBD_DATA_DIR}/reality_public.key"
printf '%s\n' 'abcd1234' > "${SBD_DATA_DIR}/reality_short_id"
printf '%s\n' 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' > "${SBD_DATA_DIR}/xray_private.key"
printf '%s\n' 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB' > "${SBD_DATA_DIR}/xray_public.key"
printf '%s\n' 'abcd1234' > "${SBD_DATA_DIR}/xray_short_id"
printf '%s\n' 'test cert' > "${SBD_DATA_DIR}/cert.pem"
printf '%s\n' 'test key' > "${SBD_DATA_DIR}/private.key"

ensure_root() { :; }
provider_restart() { :; }
provider_prepare_domain_runtime_artifacts() { :; }
provider_commit_domain_web_front() { :; }
provider_cfg_protocol_ensure_firewall_for_current() { :; }
write_nodes_output() { :; }
ensure_sing_route_rulesets_local() { :; }
build_sing_route_rule_set_json() {
  if [[ -n "${SBD_TEST_SINGBOX_BIN:-}" ]]; then
    printf '"rule_set":[{"tag":"geosite-cn","type":"local","format":"binary","path":"%s"},{"tag":"geoip-cn","type":"local","format":"binary","path":"%s"}]\n' \
      "${ROOT_DIR}/rulesets/sing/geosite-cn.srs" "${ROOT_DIR}/rulesets/sing/geoip-cn.srs"
  else
    printf '%s\n' '"rule_set":[{"tag":"geosite-cn"},{"tag":"geoip-cn"}]'
  fi
}

export ARGO_MODE=off WARP_MODE=off ROUTE_MODE=direct IP_PREFERENCE=auto
export OUTBOUND_PROXY_MODE=direct OUTBOUND_PROXY_UDP_MODE=proxy
export OUTBOUND_PROXY_HOST='' OUTBOUND_PROXY_PORT='' OUTBOUND_PROXY_USER='' OUTBOUND_PROXY_PASS=''
export DOMAIN_SPLIT_DIRECT='' DOMAIN_SPLIT_PROXY='' DOMAIN_SPLIT_BLOCK=''
export TLS_MODE=self-signed REALITY_HANDSHAKE_PORT=443 SBD_PORT_VLESS_REALITY=443
persist_runtime_state vps lite sing-box vless-reality

parse_set_egress_args --mode socks --host 192.0.2.10 --port 1080
[[ "$SET_EGRESS_UDP_MODE" == "proxy" ]] || fail "set-egress default UDP mode is not proxy"
(
  unset OUTBOUND_PROXY_MODE OUTBOUND_PROXY_UDP_MODE OUTBOUND_PROXY_HOST OUTBOUND_PROXY_PORT
  parse_install_args --outbound-proxy-mode socks --outbound-proxy-udp-mode direct \
    --outbound-proxy-host 192.0.2.10 --outbound-proxy-port 1080
  [[ "$OUTBOUND_PROXY_UDP_MODE" == "direct" ]]
) || fail "install UDP option was not parsed"
provider_set_egress "$SET_EGRESS_MODE" "$SET_EGRESS_HOST" "$SET_EGRESS_PORT" \
  "$SET_EGRESS_USER" "$SET_EGRESS_PASS" "$SET_EGRESS_UDP_MODE"
provider_set_route global-proxy

config="${SBD_CONFIG_DIR}/config.json"
runtime="${SBD_CONFIG_DIR}/runtime.env"
assert_jq "$config" '.route.final == "proxy-out" and (.route.rules == null)' \
  "socks global-proxy udp=proxy route mismatch"
assert_socks_outbounds "$config" "socks global-proxy udp=proxy outbounds mismatch"
assert_runtime_udp "$runtime" proxy "runtime missing udp=proxy"

parse_set_egress_args --mode socks --host 192.0.2.10 --port 1080 --udp direct
provider_set_egress "$SET_EGRESS_MODE" "$SET_EGRESS_HOST" "$SET_EGRESS_PORT" \
  "$SET_EGRESS_USER" "$SET_EGRESS_PASS" "$SET_EGRESS_UDP_MODE"
assert_jq "$config" '.route.final == "proxy-out" and .route.rules[0] == {"network":"udp","outbound":"direct"}' \
  "socks global-proxy udp=direct route mismatch"
assert_socks_outbounds "$config" "socks global-proxy udp=direct outbounds mismatch"
assert_runtime_udp "$runtime" direct "runtime missing udp=direct"

parse_set_egress_args --mode socks --host 192.0.2.10 --port 1080 --udp block
provider_set_egress "$SET_EGRESS_MODE" "$SET_EGRESS_HOST" "$SET_EGRESS_PORT" \
  "$SET_EGRESS_USER" "$SET_EGRESS_PASS" "$SET_EGRESS_UDP_MODE"
assert_jq "$config" '.route.final == "proxy-out" and .route.rules[0] == {"network":"udp","action":"reject"}' \
  "socks global-proxy udp=block route mismatch"
assert_socks_outbounds "$config" "socks global-proxy udp=block outbounds mismatch"
assert_runtime_udp "$runtime" block "runtime missing udp=block"

parse_set_egress_args --mode socks --host 192.0.2.10 --port 1080 --udp direct
provider_set_egress "$SET_EGRESS_MODE" "$SET_EGRESS_HOST" "$SET_EGRESS_PORT" \
  "$SET_EGRESS_USER" "$SET_EGRESS_PASS" "$SET_EGRESS_UDP_MODE"
provider_set_route cn-direct
assert_jq "$config" '.route.final == "proxy-out"
  and .route.rules[0] == {"network":"udp","outbound":"direct"}
  and .route.rules[1].rule_set == ["geosite-cn","geoip-cn"]
  and .route.rules[1].outbound == "direct"' "socks cn-direct udp=direct route mismatch"
assert_socks_outbounds "$config" "socks cn-direct udp=direct outbounds mismatch"
assert_runtime_udp "$runtime" direct "runtime missing cn-direct udp=direct"

provider_set_route cn-proxy
assert_jq "$config" '.route.final == "direct"
  and .route.rules[0] == {"network":"udp","outbound":"direct"}
  and .route.rules[1].rule_set == ["geosite-cn","geoip-cn"]
  and .route.rules[1].outbound == "proxy-out"' "socks cn-proxy udp=direct route mismatch"
assert_socks_outbounds "$config" "socks cn-proxy udp=direct outbounds mismatch"
assert_runtime_udp "$runtime" direct "runtime missing cn-proxy udp=direct"

provider_cfg_set_ip_preference v4
grep -q '^outbound_proxy_udp_mode="direct"$' "$runtime" || fail "cfg ip-pref lost UDP mode"
provider_cfg_set_domain_split direct.example proxy.example ""
grep -q '^outbound_proxy_udp_mode="direct"$' "$runtime" || fail "cfg domain-split lost UDP mode"
assert_jq "$config" '.route.rules[0] == {"network":"udp","outbound":"direct"}
  and .route.rules[1].rule_set == ["geosite-cn","geoip-cn"]
  and .route.rules[2].domain_suffix == ["direct.example"]
  and .route.rules[3].domain_suffix == ["proxy.example"]' "UDP rule did not precede CN/domain rules"
provider_cfg_rebuild_runtime
grep -q '^outbound_proxy_udp_mode="direct"$' "$runtime" || fail "cfg rebuild lost UDP mode"
provider_cfg_set_domain_split "" "" ""

provider_set_route direct
parse_set_egress_args --mode direct
provider_set_egress "$SET_EGRESS_MODE" "$SET_EGRESS_HOST" "$SET_EGRESS_PORT" \
  "$SET_EGRESS_USER" "$SET_EGRESS_PASS" "$SET_EGRESS_UDP_MODE"
assert_jq "$config" '.route == {"final":"direct"} and ([.outbounds[].tag] | sort) == ["direct"]' \
  "direct egress route or outbounds mismatch"
grep -q '^outbound_proxy_udp_mode="proxy"$' "$runtime" || fail "direct egress did not reset UDP mode default"

unset OUTBOUND_PROXY_UDP_MODE
provider_cfg_load_runtime_exports
[[ "$OUTBOUND_PROXY_UDP_MODE" == "proxy" ]] || fail "runtime loader did not restore UDP mode"

if invalid_output="$(OUTBOUND_PROXY_UDP_MODE=xxx validate_feature_modes 2>&1)"; then
  fail "invalid UDP mode unexpectedly passed validation"
fi
grep -q 'Invalid OUTBOUND_PROXY_UDP_MODE: xxx' <<< "$invalid_output" || fail "invalid UDP mode error mismatch"

if http_output="$(OUTBOUND_PROXY_MODE=http OUTBOUND_PROXY_UDP_MODE=proxy \
  OUTBOUND_PROXY_HOST=192.0.2.10 OUTBOUND_PROXY_PORT=8080 validate_feature_modes 2>&1)"; then
  fail "HTTP udp=proxy unexpectedly passed validation"
fi
grep -q 'OUTBOUND_PROXY_UDP_MODE=proxy is unsupported for OUTBOUND_PROXY_MODE=http' <<< "$http_output" || \
  fail "HTTP UDP incompatibility error mismatch"

OUTBOUND_PROXY_MODE=socks
OUTBOUND_PROXY_HOST=192.0.2.10
OUTBOUND_PROXY_PORT=1080
OUTBOUND_PROXY_USER=''
OUTBOUND_PROXY_PASS=''
OUTBOUND_PROXY_UDP_MODE=proxy
ROUTE_MODE=direct
xray_fragment="$(build_xray_routing_fragment proxy-out)"
[[ -z "$xray_fragment" ]] || fail "Xray ROUTE_MODE=direct does not mean direct"

OUTBOUND_PROXY_UDP_MODE=block
singbox_direct_route="$(build_singbox_route_json proxy-out)"
jq -e '. == {"rules":[{"network":"udp","action":"reject"}],"final":"direct"}' \
  <<< "$singbox_direct_route" >/dev/null || fail "sing-box direct route UDP override mismatch"
xray_fragment="$(build_xray_routing_fragment proxy-out)"
jq -e '.routing.rules == [{"type":"field","network":"udp","outboundTag":"block"}]' \
  <<< "{\"sentinel\":true${xray_fragment}}" >/dev/null || fail "Xray direct route UDP override mismatch"

OUTBOUND_PROXY_UDP_MODE=direct
ROUTE_MODE=global-proxy
xray_fragment="$(build_xray_routing_fragment proxy-out)"
jq -e '.routing.rules[0] == {"type":"field","network":"udp","outboundTag":"direct"}' \
  <<< "{\"sentinel\":true${xray_fragment}}" >/dev/null || fail "Xray UDP override priority mismatch"

OUTBOUND_PROXY_UDP_MODE=block
xray_fragment="$(build_xray_routing_fragment proxy-out)"
jq -e '.routing.rules[0] == {"type":"field","network":"udp","outboundTag":"block"}
  and .routing.rules[1] == {"type":"field","network":"tcp,udp","outboundTag":"proxy-out"}' \
  <<< "{\"sentinel\":true${xray_fragment}}" >/dev/null || fail "Xray UDP block route mismatch"

OUTBOUND_PROXY_UDP_MODE=direct
DOMAIN_SPLIT_DIRECT=direct.example
DOMAIN_SPLIT_PROXY=proxy.example
DOMAIN_SPLIT_BLOCK=block.example
xray_fragment="$(build_xray_routing_fragment proxy-out)"
jq -e '.routing.rules == [
    {"type":"field","network":"udp","outboundTag":"direct"},
    {"type":"field","domain":["domain:direct.example"],"outboundTag":"direct"},
    {"type":"field","domain":["domain:proxy.example"],"outboundTag":"proxy-out"},
    {"type":"field","domain":["domain:block.example"],"outboundTag":"block"},
    {"type":"field","network":"tcp,udp","outboundTag":"proxy-out"}
  ]' <<< "{\"sentinel\":true${xray_fragment}}" >/dev/null || fail "Xray domain rules must precede catch-all"

IP_PREFERENCE=v4
xray_upstream="$(build_upstream_outbound_xray)"
jq -e '.targetStrategy == "UseIPv4"' <<< "$xray_upstream" >/dev/null || \
  fail "Xray upstream outbound did not apply IPv4 preference"
ROUTE_MODE=direct
OUTBOUND_PROXY_UDP_MODE=proxy
DOMAIN_SPLIT_DIRECT=''
DOMAIN_SPLIT_PROXY=''
DOMAIN_SPLIT_BLOCK=''
build_xray_config vless-reality
xray_config="${SBD_CONFIG_DIR}/xray-config.json"
assert_jq "$xray_config" '(.routing == null)
  and any(.outbounds[]; .tag == "direct" and .targetStrategy == "UseIPv4")
  and any(.outbounds[]; .tag == "proxy-out" and .targetStrategy == "UseIPv4")' \
  "Xray IP preference must be emitted on active outbounds"
if [[ -n "${SBD_TEST_XRAY_BIN:-}" ]]; then
  validate_generated_config xray false
fi

if warp_proxy_output="$(WARP_MODE=s4 OUTBOUND_PROXY_MODE=socks OUTBOUND_PROXY_UDP_MODE=direct \
  OUTBOUND_PROXY_HOST=192.0.2.10 OUTBOUND_PROXY_PORT=1080 validate_feature_modes 2>&1)"; then
  fail "WARP plus upstream proxy unexpectedly passed validation"
fi
grep -q 'chained WARP plus upstream proxy is not supported' <<< "$warp_proxy_output" || \
  fail "WARP plus upstream proxy error mismatch"

OUTBOUND_PROXY_MODE=direct
OUTBOUND_PROXY_UDP_MODE=block
WARP_MODE=global
ROUTE_MODE=direct
warp_route="$(build_singbox_route_json warp-out)"
jq -e '. == {"final":"warp-out"}' <<< "$warp_route" >/dev/null || fail "WARP route was changed by proxy UDP mode"

echo "[OK] egress UDP configuration checks passed"
