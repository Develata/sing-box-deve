#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="$root_dir"
[[ -x "${SBD_TEST_SINGBOX_BIN:-}" ]] || { echo "SBD_TEST_SINGBOX_BIN is required" >&2; exit 2; }
[[ -x "${SBD_TEST_XRAY_BIN:-}" ]] || { echo "SBD_TEST_XRAY_BIN is required" >&2; exit 2; }

source "${PROJECT_ROOT}/lib/common.sh"
source "${PROJECT_ROOT}/lib/protocols.sh"
source "${PROJECT_ROOT}/lib/security.sh"
source "${PROJECT_ROOT}/lib/providers.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT INT TERM HUP
SBD_STATE_DIR="${tmp_dir}/state"
SBD_CONFIG_DIR="${tmp_dir}/config"
SBD_INSTALL_DIR="${tmp_dir}/install"
SBD_BIN_DIR="${SBD_INSTALL_DIR}/bin"
SBD_DATA_DIR="${SBD_INSTALL_DIR}/data"
SBD_CACHE_DIR="${SBD_INSTALL_DIR}/cache"
SBD_NODES_FILE="${SBD_DATA_DIR}/nodes.txt"
SBD_NODES_BASE_FILE="${SBD_DATA_DIR}/nodes-base.txt"
SBD_SUB_FILE="${SBD_DATA_DIR}/nodes-sub.txt"
SBD_NODE_MODEL_FILE="${SBD_DATA_DIR}/nodes-model.json"
SBD_SHARE_RAW_FILE="${SBD_DATA_DIR}/jhdy.txt"
SBD_SHARE_BASE64_FILE="${SBD_DATA_DIR}/jh_sub.txt"
SBD_SHARE_GROUP_DIR="${SBD_DATA_DIR}/share-groups"
export SBD_NODES_FILE SBD_NODES_BASE_FILE SBD_SUB_FILE SBD_NODE_MODEL_FILE
export SBD_SHARE_RAW_FILE SBD_SHARE_BASE64_FILE SBD_SHARE_GROUP_DIR
mkdir -p "$SBD_STATE_DIR" "$SBD_CONFIG_DIR" "$SBD_BIN_DIR" "$SBD_DATA_DIR" "$SBD_CACHE_DIR"
install -m 0755 "$SBD_TEST_SINGBOX_BIN" "${SBD_BIN_DIR}/sing-box"
# Exercise the installer against the same verified release ZIP used by this suite.
# Empty bin/cache paths prove CN routing does not depend on host Xray assets.
unset XRAY_LOCATION_ASSET
(
  download_file() { cp "$(dirname "$SBD_TEST_XRAY_BIN")/${1##*/}" "$2"; }
  install_xray_binary v-fixture
)
printf '11111111-1111-4111-8111-111111111111\n' > "${SBD_DATA_DIR}/uuid"

export ARGO_MODE=off WARP_MODE=off ROUTE_MODE=direct IP_PREFERENCE=auto
export OUTBOUND_PROXY_MODE=direct OUTBOUND_PROXY_UDP_MODE=proxy
export OUTBOUND_PROXY_HOST='' OUTBOUND_PROXY_PORT='' OUTBOUND_PROXY_USER='' OUTBOUND_PROXY_PASS=''
export DOMAIN_SPLIT_DIRECT='' DOMAIN_SPLIT_PROXY='' DOMAIN_SPLIT_BLOCK=''
export TLS_MODE=self-signed TLS_SERVER_NAME=www.bing.com REALITY_SERVER_NAME=www.bing.com
export REALITY_HANDSHAKE_PORT=443 HY2_OBFS_MODE=off XRAY_VLESS_ENC=false XRAY_XHTTP_REALITY=false

sing_matrix=(
  vless-reality
  vless-ws
  shadowsocks-2022
  naive
  hysteria2
  "vless-reality,vless-ws,shadowsocks-2022,naive,hysteria2"
)
for protocols_csv in "${sing_matrix[@]}"; do
  build_sing_box_config "$protocols_csv"
  validate_generated_config sing-box false
done

ROUTE_MODE=cn-direct
DOMAIN_SPLIT_DIRECT=direct.example
DOMAIN_SPLIT_BLOCK=block.example
OUTBOUND_PROXY_MODE=socks
OUTBOUND_PROXY_UDP_MODE=direct
OUTBOUND_PROXY_HOST=192.0.2.10
OUTBOUND_PROXY_PORT=1080
build_sing_box_config vless-reality
validate_generated_config sing-box false

ROUTE_MODE=direct
DOMAIN_SPLIT_DIRECT=''
DOMAIN_SPLIT_BLOCK=''
OUTBOUND_PROXY_MODE=direct
OUTBOUND_PROXY_UDP_MODE=proxy
OUTBOUND_PROXY_HOST=''
OUTBOUND_PROXY_PORT=''
WARP_MODE=s4
WARP_PRIVATE_KEY=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
WARP_PEER_PUBLIC_KEY=bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=
WARP_RESERVED='[0,0,0]'
export WARP_PRIVATE_KEY WARP_PEER_PUBLIC_KEY WARP_RESERVED
build_sing_box_config vless-reality
validate_generated_config sing-box false

WARP_MODE=off
xray_matrix=(vless-reality vless-ws vless-xhttp "vless-reality,vless-ws,vless-xhttp")
for protocols_csv in "${xray_matrix[@]}"; do
  build_xray_config "$protocols_csv"
  validate_generated_config xray false
done

WARP_MODE=x4
build_xray_config vless-reality
validate_generated_config xray false

WARP_MODE=off
write_nodes_output sing-box vless-reality,vless-ws,shadowsocks-2022
ensure_sing_route_rulesets_local
ensure_clash_rulesets_local
generate_client_artifacts
(cd "$SBD_DATA_DIR" && "${SBD_BIN_DIR}/sing-box" check -c sing_box_client.json)
jq -e 'any(.outbounds[]; .tag | startswith("sbd-"))' "${SBD_DATA_DIR}/sing_box_client.json" >/dev/null
proxy_json="$(sed -n 's/^proxies: //p' "${SBD_DATA_DIR}/clash_meta_client.yaml" | head -n1)"
jq -e 'length > 0' <<< "$proxy_json" >/dev/null
jq -e '.app == "SFA" and (.subscription_base64 | length > 0)' "${SBD_DATA_DIR}/sfa_client.json" >/dev/null
jq -e '.app == "SFI" and (.subscription_base64 | length > 0)' "${SBD_DATA_DIR}/sfi_client.json" >/dev/null

printf '[OK] current stable core configuration matrix passed\n'

for ROUTE_MODE in cn-direct cn-proxy; do
  OUTBOUND_PROXY_MODE=socks OUTBOUND_PROXY_HOST=192.0.2.10 OUTBOUND_PROXY_PORT=1080
  build_xray_config vless-reality
  validate_generated_config xray false
done
