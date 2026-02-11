#!/usr/bin/env bash
# shellcheck disable=SC2034

parse_install_args() {
  local protocols_default_seed="vless-reality"
  local protocols_explicit="false"
  PROVIDER="vps"
  PROFILE="lite"
  ENGINE="sing-box"
  PROTOCOLS="$protocols_default_seed"
  DRY_RUN="false"
  PORT_MODE="${PORT_MODE:-random}"
  MANUAL_PORT_MAP="${MANUAL_PORT_MAP:-}"
  INSTALL_MAIN_PORT="${INSTALL_MAIN_PORT:-}"
  RANDOM_MAIN_PORT="${RANDOM_MAIN_PORT:-false}"
  AUTO_YES="${AUTO_YES:-false}"
  ARGO_MODE="${ARGO_MODE:-off}"
  ARGO_DOMAIN="${ARGO_DOMAIN:-}"
  ARGO_TOKEN="${ARGO_TOKEN:-}"
  ARGO_CDN_ENDPOINTS="${ARGO_CDN_ENDPOINTS:-}"
  PSIPHON_ENABLE="${PSIPHON_ENABLE:-off}"
  PSIPHON_MODE="${PSIPHON_MODE:-off}"
  PSIPHON_REGION="${PSIPHON_REGION:-auto}"
  WARP_MODE="${WARP_MODE:-off}"
  ROUTE_MODE="${ROUTE_MODE:-direct}"
  IP_PREFERENCE="${IP_PREFERENCE:-auto}"
  CDN_TEMPLATE_HOST="${CDN_TEMPLATE_HOST:-}"
  TLS_MODE="${TLS_MODE:-self-signed}"
  ACME_CERT_PATH="${ACME_CERT_PATH:-}"
  ACME_KEY_PATH="${ACME_KEY_PATH:-}"
  REALITY_SERVER_NAME="${REALITY_SERVER_NAME:-}"
  REALITY_FINGERPRINT="${REALITY_FINGERPRINT:-}"
  REALITY_HANDSHAKE_PORT="${REALITY_HANDSHAKE_PORT:-443}"
  TLS_SERVER_NAME="${TLS_SERVER_NAME:-}"
  VMESS_WS_PATH="${VMESS_WS_PATH:-/vmess}"
  VLESS_WS_PATH="${VLESS_WS_PATH:-/vless}"
  VLESS_XHTTP_PATH="${VLESS_XHTTP_PATH:-}"
  VLESS_XHTTP_MODE="${VLESS_XHTTP_MODE:-auto}"
  XRAY_VLESS_ENC="${XRAY_VLESS_ENC:-false}"
  XRAY_XHTTP_REALITY="${XRAY_XHTTP_REALITY:-false}"
  CDN_HOST_VMESS="${CDN_HOST_VMESS:-}"
  CDN_HOST_VLESS_WS="${CDN_HOST_VLESS_WS:-}"
  CDN_HOST_VLESS_XHTTP="${CDN_HOST_VLESS_XHTTP:-}"
  PROXYIP_VMESS="${PROXYIP_VMESS:-}"
  PROXYIP_VLESS_WS="${PROXYIP_VLESS_WS:-}"
  PROXYIP_VLESS_XHTTP="${PROXYIP_VLESS_XHTTP:-}"
  DOMAIN_SPLIT_DIRECT="${DOMAIN_SPLIT_DIRECT:-}"
  DOMAIN_SPLIT_PROXY="${DOMAIN_SPLIT_PROXY:-}"
  DOMAIN_SPLIT_BLOCK="${DOMAIN_SPLIT_BLOCK:-}"
  PORT_EGRESS_MAP="${PORT_EGRESS_MAP:-}"
  OUTBOUND_PROXY_MODE="${OUTBOUND_PROXY_MODE:-direct}"
  OUTBOUND_PROXY_HOST="${OUTBOUND_PROXY_HOST:-}"
  OUTBOUND_PROXY_PORT="${OUTBOUND_PROXY_PORT:-}"
  OUTBOUND_PROXY_USER="${OUTBOUND_PROXY_USER:-}"
  OUTBOUND_PROXY_PASS="${OUTBOUND_PROXY_PASS:-}"
  DIRECT_SHARE_ENDPOINTS="${DIRECT_SHARE_ENDPOINTS:-}"
  PROXY_SHARE_ENDPOINTS="${PROXY_SHARE_ENDPOINTS:-}"
  WARP_SHARE_ENDPOINTS="${WARP_SHARE_ENDPOINTS:-}"

  if declare -F legacy_apply_install_defaults >/dev/null 2>&1; then
    legacy_apply_install_defaults
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN="true"; shift ;;
      --random-main-port) RANDOM_MAIN_PORT="true"; shift ;;
      --yes|-y) AUTO_YES="true"; shift ;;
      --provider|--profile|--engine|--protocols|--port-mode|--port-map|--main-port|--argo|--argo-domain|--argo-token|--cdn-endpoints|--psiphon-enable|--psiphon-mode|--psiphon-region|--warp-mode|--route-mode|--ip-preference|--cdn-host|--tls-mode|--acme-cert-path|--acme-key-path|--reality-sni|--reality-fp|--reality-port|--tls-sni|--vmess-ws-path|--vless-ws-path|--vless-xhttp-path|--vless-xhttp-mode|--xray-vless-enc|--xray-xhttp-reality|--cdn-host-vmess|--cdn-host-vless-ws|--cdn-host-vless-xhttp|--proxyip-vmess|--proxyip-vless-ws|--proxyip-vless-xhttp|--domain-direct|--domain-proxy|--domain-block|--port-egress-map|--outbound-proxy-mode|--outbound-proxy-host|--outbound-proxy-port|--outbound-proxy-user|--outbound-proxy-pass|--direct-share-endpoints|--proxy-share-endpoints|--warp-share-endpoints)
        require_option_value "$1" "$#"
        case "$1" in
          --provider) PROVIDER="$2" ;;
          --profile) PROFILE="$2" ;;
          --engine) ENGINE="$2" ;;
          --protocols) PROTOCOLS="$2"; protocols_explicit="true" ;;
          --port-mode) PORT_MODE="$2" ;;
          --port-map) MANUAL_PORT_MAP="$2" ;;
          --main-port) INSTALL_MAIN_PORT="$2" ;;
          --argo) ARGO_MODE="$2" ;;
          --argo-domain) ARGO_DOMAIN="$2" ;;
          --argo-token) ARGO_TOKEN="$2" ;;
          --cdn-endpoints) ARGO_CDN_ENDPOINTS="$2" ;;
          --psiphon-enable) PSIPHON_ENABLE="$2" ;;
          --psiphon-mode) PSIPHON_MODE="$2" ;;
          --psiphon-region) PSIPHON_REGION="$2" ;;
          --warp-mode) WARP_MODE="$2" ;;
          --route-mode) ROUTE_MODE="$2" ;;
          --ip-preference) IP_PREFERENCE="$2" ;;
          --cdn-host) CDN_TEMPLATE_HOST="$2" ;;
          --tls-mode) TLS_MODE="$2" ;;
          --acme-cert-path) ACME_CERT_PATH="$2" ;;
          --acme-key-path) ACME_KEY_PATH="$2" ;;
          --reality-sni) REALITY_SERVER_NAME="$2" ;;
          --reality-fp) REALITY_FINGERPRINT="$2" ;;
          --reality-port) REALITY_HANDSHAKE_PORT="$2" ;;
          --tls-sni) TLS_SERVER_NAME="$2" ;;
          --vmess-ws-path) VMESS_WS_PATH="$2" ;;
          --vless-ws-path) VLESS_WS_PATH="$2" ;;
          --vless-xhttp-path) VLESS_XHTTP_PATH="$2" ;;
          --vless-xhttp-mode) VLESS_XHTTP_MODE="$2" ;;
          --xray-vless-enc) XRAY_VLESS_ENC="$2" ;;
          --xray-xhttp-reality) XRAY_XHTTP_REALITY="$2" ;;
          --cdn-host-vmess) CDN_HOST_VMESS="$2" ;;
          --cdn-host-vless-ws) CDN_HOST_VLESS_WS="$2" ;;
          --cdn-host-vless-xhttp) CDN_HOST_VLESS_XHTTP="$2" ;;
          --proxyip-vmess) PROXYIP_VMESS="$2" ;;
          --proxyip-vless-ws) PROXYIP_VLESS_WS="$2" ;;
          --proxyip-vless-xhttp) PROXYIP_VLESS_XHTTP="$2" ;;
          --domain-direct) DOMAIN_SPLIT_DIRECT="$2" ;;
          --domain-proxy) DOMAIN_SPLIT_PROXY="$2" ;;
          --domain-block) DOMAIN_SPLIT_BLOCK="$2" ;;
          --port-egress-map) PORT_EGRESS_MAP="$2" ;;
          --outbound-proxy-mode) OUTBOUND_PROXY_MODE="$2" ;;
          --outbound-proxy-host) OUTBOUND_PROXY_HOST="$2" ;;
          --outbound-proxy-port) OUTBOUND_PROXY_PORT="$2" ;;
          --outbound-proxy-user) OUTBOUND_PROXY_USER="$2" ;;
          --outbound-proxy-pass) OUTBOUND_PROXY_PASS="$2" ;;
          --direct-share-endpoints) DIRECT_SHARE_ENDPOINTS="$2" ;;
          --proxy-share-endpoints) PROXY_SHARE_ENDPOINTS="$2" ;;
          --warp-share-endpoints) WARP_SHARE_ENDPOINTS="$2" ;;
        esac
        shift 2
        ;;
      *) die "Unknown install argument: $1" ;;
    esac
  done

  if [[ "$protocols_explicit" != "true" && "$PROTOCOLS" == "$protocols_default_seed" ]]; then
    if [[ "$ENGINE" == "sing-box" ]]; then
      PROTOCOLS="vless-reality,hysteria2"
    else
      PROTOCOLS="vless-reality,vmess-ws"
    fi
  fi

  [[ "$PORT_MODE" == "random" || "$PORT_MODE" == "manual" ]] || die "--port-mode must be random|manual"
  if [[ "$PORT_MODE" == "manual" ]]; then
    [[ -n "$MANUAL_PORT_MAP" || -n "$INSTALL_MAIN_PORT" ]] || die "--port-mode manual requires --port-map (or --main-port)"
  fi
  [[ "$RANDOM_MAIN_PORT" == "true" || "$RANDOM_MAIN_PORT" == "false" ]] || die "RANDOM_MAIN_PORT must be true/false"
  if [[ -n "$INSTALL_MAIN_PORT" ]]; then
    [[ "$INSTALL_MAIN_PORT" =~ ^[0-9]+$ ]] || die "--main-port must be numeric"
    (( INSTALL_MAIN_PORT >= 1 && INSTALL_MAIN_PORT <= 65535 )) || die "--main-port must be within 1..65535"
  fi
  if [[ "$RANDOM_MAIN_PORT" == "true" && -n "$INSTALL_MAIN_PORT" ]]; then
    die "Use either --main-port or --random-main-port, not both"
  fi
  if [[ "$RANDOM_MAIN_PORT" == "true" && "$PORT_MODE" == "manual" ]]; then
    die "--random-main-port conflicts with --port-mode manual"
  fi
  case "${PSIPHON_ENABLE,,}" in
    1|true|yes|on|enabled)
      [[ "${PSIPHON_MODE:-off}" == "off" ]] && PSIPHON_MODE="proxy"
      ;;
  esac
  return 0
}

source "${PROJECT_ROOT}/lib/cli_args_common.sh"
source "${PROJECT_ROOT}/lib/cli_args_update.sh"
source "${PROJECT_ROOT}/lib/cli_args_port_egress.sh"
