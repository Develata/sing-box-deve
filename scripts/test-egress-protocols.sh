#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034,SC2317
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$PROJECT_ROOT/lib/load.sh"
egress_root="$(mktemp -d)"
trap 'rm -rf "$egress_root"' EXIT
SBD_INSTALL_DIR="$egress_root/install"
SBD_CONFIG_DIR="$egress_root/config"
SBD_STATE_DIR="$egress_root/state"
SBD_HOST_STATE_DIR="$egress_root/control"
SBD_RUNTIME_DIR="$egress_root/run"
SBD_BIN_DIR="$SBD_INSTALL_DIR/bin"
SBD_DATA_DIR="$SBD_INSTALL_DIR/data"
SBD_CACHE_DIR="$SBD_INSTALL_DIR/cache"
SBD_RULES_FILE="$SBD_STATE_DIR/firewall-rules.db"
SBD_SERVICE_FILE="$egress_root/services/core"
SBD_ARGO_SERVICE_FILE="$egress_root/services/argo"
SBD_FW_REPLAY_SERVICE_FILE="$egress_root/services/firewall"
SBD_WARP_SOCKS_SERVICE_FILE="$egress_root/services/warp"
SBD_INIT_SYSTEM="nohup"
outbound_proxy_link="" outbound_proxy_mode=""
mkdir -p "$SBD_CONFIG_DIR" "$SBD_BIN_DIR" "$SBD_DATA_DIR" "$SBD_STATE_DIR" "$SBD_CACHE_DIR"
for core in sing-box xray; do
  binary="${SBD_TEST_SINGBOX_BIN:-}"
  [[ "$core" != xray ]] || binary="${SBD_TEST_XRAY_BIN:-}"
  if [[ -n "$binary" ]]; then
    cp -p "$binary" "$SBD_BIN_DIR/$core"
    if [[ "$core" == sing-box && -f "$(dirname "$binary")/libcronet.so" ]]; then
      cp -p "$(dirname "$binary")/libcronet.so" "$SBD_BIN_DIR/libcronet.so"
    fi
  else
    printf '#!/usr/bin/env bash\nexit 0\n' > "$SBD_BIN_DIR/$core"
    chmod +x "$SBD_BIN_DIR/$core"
  fi
done
uid=11111111-1111-4111-8111-111111111111
printf '%s\n' "$uid" > "$SBD_DATA_DIR/uuid"
for family in reality xray; do
  printf 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n' > "$SBD_DATA_DIR/${family}_private.key"
  printf 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB\n' > "$SBD_DATA_DIR/${family}_public.key"
  printf 'abcd1234\n' > "$SBD_DATA_DIR/${family}_short_id"
done
ensure_root() { :; }
sbd_service_probe() { echo 'inactive disabled'; }
sbd_service_stop() { printf 'stop\n' >> "$egress_root/stops"; }
sbd_service_daemon_reload() { :; }
provider_prepare_domain_runtime_artifacts() { :; }
provider_commit_domain_web_front() { :; }
write_nodes_output() { :; }
fw_replay() { :; }
provider_restart() { [[ "${egress_restart_fail:-false}" == false ]]; }
ensure_sing_route_rulesets_local() { :; }
build_sing_route_rule_set_json() {
  printf '"rule_set":[{"tag":"geosite-cn","type":"local","format":"binary","path":"%s"},{"tag":"geoip-cn","type":"local","format":"binary","path":"%s"}]' \
    "$PROJECT_ROOT/rulesets/sing/geosite-cn.srs" "$PROJECT_ROOT/rulesets/sing/geoip-cn.srs"
}
export ARGO_MODE=off WARP_MODE=off ROUTE_MODE=global-proxy IP_PREFERENCE=auto TLS_MODE=self-signed
export OUTBOUND_PROXY_MODE=direct OUTBOUND_PROXY_UDP_MODE=proxy OUTBOUND_PROXY_LINK=''
persist_runtime_state vps lite sing-box vless-reality
reality="$(node_link_vless_reality "$uid" 192.0.2.10 443 cover.example chrome BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB abcd1234)"
reality_base="$reality"
reality="${reality_base%%#*}&allowInsecure=1&udp=1#exported-node"
ws="$(node_link_vless_ws "$uid" 192.0.2.10 443 none %2Fws cdn.example tls cdn.example)"
hy2="$(node_link_hysteria2 "$uid" 192.0.2.10 443 cert.example salamander obfs-password)"
hy2_base="$hy2"
hy2="${hy2_base%%#*}&udp=1#exported-node"
ss="$(node_link_ss2022 AAAAAAAAAAAAAAAAAAAAAA== 192.0.2.10 443)"
ss_base="$ss"
ss="${ss_base%%#*}?udp=1#exported-node"
naive="$(node_link_naive "$uid" 192.0.2.10 443 cert.example)"
xhttp="$(node_link_vless_xhttp "$uid" 192.0.2.10 443 none cert.example chrome BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB abcd1234 %2Fxh auto cert.example)"
links=("$reality" "$ws" "$hy2" "$ss" "$naive" "$xhttp")
kinds=(vless-reality vless-ws hysteria2 shadowsocks-2022 naive vless-xhttp)

for core in sing-box xray; do
  OUTBOUND_PROXY_LINK=''
  OUTBOUND_PROXY_MODE=direct
  persist_runtime_state vps lite "$core" vless-reality
  for i in "${!links[@]}"; do
    kind="${kinds[$i]}" link="${links[$i]}"
    if [[ "$core:$kind" == sing-box:vless-xhttp || "$core:$kind" == xray:naive ]]; then
      before="$(sha256sum "$SBD_CONFIG_DIR/runtime.env")"
      if provider_set_egress direct '' '' '' '' direct "$link"; then echo '[FAIL] incompatible core accepted'; exit 1; fi
      [[ "$before" == "$(sha256sum "$SBD_CONFIG_DIR/runtime.env")" && ! -f "$egress_root/stops" ]]
      continue
    fi
    udp=proxy
    [[ "$kind" != naive ]] || udp=block
    provider_set_egress direct '' '' '' '' "$udp" "$link"
    sbd_load_runtime_env
    [[ "$outbound_proxy_link" == "$link" && "$outbound_proxy_mode" == "$kind" ]]
    [[ "$(stat -c %a "$SBD_CONFIG_DIR/runtime.env")" == 600 ]]
    config="$SBD_CONFIG_DIR/config.json"
    [[ "$core" != xray ]] || config="$SBD_CONFIG_DIR/xray-config.json"
    jq -e '[.outbounds[] | select(.tag == "proxy-out")] | length == 1' "$config" >/dev/null
    printf '[OK] %s egress: %s\n' "$core" "$kind"
  done
  for udp_disabled in "${reality_base%%#*}&udp=0" "${hy2_base%%#*}&udp=0" "${ss_base%%#*}?udp=0"; do
    before="$(sha256sum "$SBD_CONFIG_DIR/runtime.env")"
    if (provider_set_egress direct '' '' '' '' proxy "$udp_disabled"); then
      echo '[FAIL] UDP-disabled link accepted with proxy policy'; exit 1
    fi
    [[ "$before" == "$(sha256sum "$SBD_CONFIG_DIR/runtime.env")" ]]
    provider_set_egress direct '' '' '' '' direct "$udp_disabled"
    provider_cfg_load_runtime_exports
    [[ "$OUTBOUND_PROXY_LINK" == "$udp_disabled" && "$OUTBOUND_PROXY_UDP_MODE" == direct ]]
  done
  printf '[OK] %s VLESS/HY2/SS UDP export flags respect policy and rejected state\n' "$core"
  # Importing a node under direct routing must not silently enable proxy use.
  provider_set_route direct
  provider_set_egress direct '' '' '' '' proxy "$reality"
  provider_cfg_load_runtime_exports
  [[ "$ROUTE_MODE" == direct && "$OUTBOUND_PROXY_LINK" == "$reality" ]]
  if [[ "$core" == sing-box ]]; then
    jq -e '.route.final == "direct"' "$config" >/dev/null
  else
    jq -e '.outbounds[0].tag == "direct" and ((.routing.rules // []) | length == 0)' "$config" >/dev/null
  fi
  provider_set_route global-proxy
  if [[ "$core" == sing-box ]]; then
    jq -e '.route.final == "proxy-out"' "$config" >/dev/null
  else
    jq -e '.routing.rules[-1].outboundTag == "proxy-out"' "$config" >/dev/null
  fi
  provider_set_route direct
  provider_cfg_load_runtime_exports
  [[ "$ROUTE_MODE" == direct && "$OUTBOUND_PROXY_LINK" == "$reality" ]]
  printf '[OK] %s direct import, explicit proxy routing and direct switch retain the saved node\n' "$core"
done

# Route changes retain the complete link, then a failed replacement compensates.
provider_set_egress direct '' '' '' '' proxy "$hy2"
provider_set_route direct
provider_cfg_load_runtime_exports
[[ "$OUTBOUND_PROXY_LINK" == "$hy2" ]]
before="$(sha256sum "$SBD_CONFIG_DIR/runtime.env" "$SBD_CONFIG_DIR/xray-config.json")"
if (egress_restart_fail=true; provider_set_egress direct '' '' '' '' proxy "$reality"); then exit 1; fi
[[ "$before" == "$(sha256sum "$SBD_CONFIG_DIR/runtime.env" "$SBD_CONFIG_DIR/xray-config.json")" ]]
provider_set_egress socks 192.0.2.20 1080 '' '' proxy
provider_cfg_load_runtime_exports
[[ -z "$OUTBOUND_PROXY_LINK" && "$OUTBOUND_PROXY_MODE" == socks ]]
provider_set_egress direct '' '' '' '' proxy
if grep -q '^outbound_proxy_link=' "$SBD_CONFIG_DIR/runtime.env"; then exit 1; fi

# XHTTP direct share links follow the actual transport security and flow.
SBD_NODE_MODEL_FILE="$egress_root/nodes.json"
for XRAY_XHTTP_REALITY in false true; do
  node_model_init
  node_model_add_vless_xhttp "$uid" 192.0.2.10 443 none cert.example chrome BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB abcd1234 /xh auto cert.example
  node_model_render_uri_file "$egress_root/xhttp-link"
  [[ "$(cat "$egress_root/xhttp-link")" != *'flow=xtls-rprx-vision'* ]]
  if [[ "$XRAY_XHTTP_REALITY" == true ]]; then
    [[ "$(cat "$egress_root/xhttp-link")" == *'security=reality'* ]]
  else
    [[ "$(cat "$egress_root/xhttp-link")" == *'security=none'* && "$(cat "$egress_root/xhttp-link")" != *'pbk='* ]]
  fi
  sbd_egress_read_link_file "$egress_root/xhttp-link" >/dev/null
done

# Legacy xhpt enables Reality through the same resolver as config generation.
SBD_XHTTP_REALITY_ENC=true XRAY_XHTTP_REALITY=false
node_model_init
node_model_add_vless_xhttp "$uid" 192.0.2.10 443 none cert.example chrome BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB abcd1234 /xh auto cert.example
sbd_xhttp_use_reality
[[ "$(jq -r '.nodes[0].security' "$SBD_NODE_MODEL_FILE")" == reality ]]
unset SBD_XHTTP_REALITY_ENC

# The public xhpt alias normalizes to a persisted setting and survives reload.
(
  xhpt=24443
  XRAY_XHTTP_REALITY=false
  parse_install_args --dry-run
  [[ "$XRAY_XHTTP_REALITY" == true ]]
  SBD_CONFIG_DIR="$egress_root/legacy-config"
  mkdir -p "$SBD_CONFIG_DIR"
  persist_runtime_state vps full xray vless-xhttp
  unset xhpt XRAY_XHTTP_REALITY SBD_XHTTP_REALITY_ENC
  sbd_load_runtime_env
  sbd_xhttp_use_reality
  # Explicit modern flags still override legacy defaults.
  xhpt=24443
  parse_install_args --dry-run --xray-xhttp-reality false
  if sbd_xhttp_use_reality; then exit 1; fi
)

# An explicitly empty config value overrides an inherited link.
(
  detect_os() { :; }
  run_install() { [[ -z "$OUTBOUND_PROXY_LINK" ]]; }
  export OUTBOUND_PROXY_LINK="$hy2"
  printf 'outbound_proxy_link=""\n' > "$egress_root/clear-link.env"
  apply_config "$egress_root/clear-link.env"
)

# CLI import from a file and optional trailing newline; options remain exclusive.
printf '%s\n' "$reality" > "$egress_root/node.link"
parse_set_egress_args --link-file "$egress_root/node.link" --udp direct
[[ "$SET_EGRESS_LINK" == "$reality" && "$SET_EGRESS_UDP_MODE" == direct ]]
if (parse_set_egress_args --link "$reality" --host ignored); then exit 1; fi
if (parse_set_egress_args --link 'hy2://secret@host:0'); then exit 1; fi

# New binary snapshots restore the matching Naive library; v2 remains readable.
printf 'library-v1\n' > "$SBD_BIN_DIR/libcronet.so"
sbd_state_capture "$egress_root/snapshot-v3" true
sbd_state_inventory true 3 > "$egress_root/snapshot-v3/inventory"
rm "$egress_root/snapshot-v3/files/bin/geoip.dat.absent" "$egress_root/snapshot-v3/files/bin/geosite.dat.absent"
(cd "$egress_root/snapshot-v3"; find files -type f -exec sha256sum {} + > checksums.txt)
printf '3\n' > "$egress_root/snapshot-v3/schema"
printf 'library-v2\n' > "$SBD_BIN_DIR/libcronet.so"
sbd_state_restore "$egress_root/snapshot-v3"
[[ "$(cat "$SBD_BIN_DIR/libcronet.so")" == library-v1 ]]
sbd_state_capture "$egress_root/snapshot-v2" true
# Recreate the closed v2 binary inventory, which predates the Cronet sidecar.
sbd_state_inventory true 2 > "$egress_root/snapshot-v2/inventory"
rm "$egress_root/snapshot-v2/files/bin/libcronet.so" "$egress_root/snapshot-v2/files/bin/geoip.dat.absent" "$egress_root/snapshot-v2/files/bin/geosite.dat.absent"
(cd "$egress_root/snapshot-v2"; find files -type f -exec sha256sum {} + > checksums.txt)
printf '2\n' > "$egress_root/snapshot-v2/schema"
sbd_state_verify "$egress_root/snapshot-v2"
printf '[OK] protocol egress state, rollback, CLI and snapshot compatibility passed\n'
