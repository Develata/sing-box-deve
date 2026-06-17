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
  INSTALL_PRESET="${INSTALL_PRESET:-}"
  MANUAL_PORT_MAP="${MANUAL_PORT_MAP:-}"
  INSTALL_MAIN_PORT="${INSTALL_MAIN_PORT:-}"
  RANDOM_MAIN_PORT="${RANDOM_MAIN_PORT:-false}"
  AUTO_YES="${AUTO_YES:-false}"
  ARGO_MODE="${ARGO_MODE:-off}"
  ARGO_DOMAIN="${ARGO_DOMAIN:-}"
  ARGO_TOKEN="${ARGO_TOKEN:-}"
  ARGO_CDN_ENDPOINTS="${ARGO_CDN_ENDPOINTS:-}"
  WARP_MODE="${WARP_MODE:-off}"
  ROUTE_MODE="${ROUTE_MODE:-direct}"
  IP_PREFERENCE="${IP_PREFERENCE:-auto}"
  CDN_TEMPLATE_HOST="${CDN_TEMPLATE_HOST:-}"
  TLS_MODE="${TLS_MODE:-self-signed}"
  ACME_CERT_PATH="${ACME_CERT_PATH:-}"
  ACME_KEY_PATH="${ACME_KEY_PATH:-}"
  ACME_DOMAIN="${ACME_DOMAIN:-}"
  ACME_EMAIL="${ACME_EMAIL:-}"
  ACME_DNS_PROVIDER="${ACME_DNS_PROVIDER:-}"
  WEB_FRONT_MODE="${WEB_FRONT_MODE:-auto}"
  HY2_OBFS_MODE="${HY2_OBFS_MODE:-off}"
  HY2_OBFS_PASSWORD="${HY2_OBFS_PASSWORD:-}"
  REALITY_SERVER_NAME="${REALITY_SERVER_NAME:-}"
  REALITY_FINGERPRINT="${REALITY_FINGERPRINT:-}"
  REALITY_HANDSHAKE_PORT="${REALITY_HANDSHAKE_PORT:-443}"
  TLS_SERVER_NAME="${TLS_SERVER_NAME:-}"
  VLESS_WS_PATH="${VLESS_WS_PATH:-/vless}"
  VLESS_XHTTP_PATH="${VLESS_XHTTP_PATH:-}"
  VLESS_XHTTP_MODE="${VLESS_XHTTP_MODE:-auto}"
  XRAY_VLESS_ENC="${XRAY_VLESS_ENC:-false}"
  XRAY_XHTTP_REALITY="${XRAY_XHTTP_REALITY:-false}"
  CDN_HOST_VLESS_WS="${CDN_HOST_VLESS_WS:-}"
  CDN_HOST_VLESS_XHTTP="${CDN_HOST_VLESS_XHTTP:-}"
  PROXYIP_VLESS_WS="${PROXYIP_VLESS_WS:-}"
  PROXYIP_VLESS_XHTTP="${PROXYIP_VLESS_XHTTP:-}"
  DOMAIN_SPLIT_DIRECT="${DOMAIN_SPLIT_DIRECT:-}"
  DOMAIN_SPLIT_PROXY="${DOMAIN_SPLIT_PROXY:-}"
  DOMAIN_SPLIT_BLOCK="${DOMAIN_SPLIT_BLOCK:-}"
  OUTBOUND_PROXY_MODE="${OUTBOUND_PROXY_MODE:-direct}"
  OUTBOUND_PROXY_HOST="${OUTBOUND_PROXY_HOST:-}"
  OUTBOUND_PROXY_PORT="${OUTBOUND_PROXY_PORT:-}"
  OUTBOUND_PROXY_USER="${OUTBOUND_PROXY_USER:-}"
  OUTBOUND_PROXY_PASS="${OUTBOUND_PROXY_PASS:-}"
  SBD_UUID="${SBD_UUID:-${UUID:-}}"

  if declare -F legacy_apply_install_defaults >/dev/null 2>&1; then
    legacy_apply_install_defaults
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN="true"; shift ;;
      --random-main-port) RANDOM_MAIN_PORT="true"; shift ;;
      --yes|-y) AUTO_YES="true"; shift ;;
      --provider|--profile|--engine|--protocols|--preset|--uuid|--port-mode|--port-map|--main-port|--argo|--argo-domain|--argo-token|--cdn-endpoints|--warp-mode|--route-mode|--ip-preference|--cdn-host|--tls-mode|--acme-cert-path|--acme-key-path|--acme-domain|--acme-email|--web-front|--hy2-obfs|--hy2-obfs-password|--reality-sni|--reality-fp|--reality-port|--tls-sni|--vless-ws-path|--vless-xhttp-path|--vless-xhttp-mode|--xray-vless-enc|--xray-xhttp-reality|--cdn-host-vless-ws|--cdn-host-vless-xhttp|--proxyip-vless-ws|--proxyip-vless-xhttp|--domain-direct|--domain-proxy|--domain-block|--outbound-proxy-mode|--outbound-proxy-host|--outbound-proxy-port|--outbound-proxy-user|--outbound-proxy-pass)
        require_option_value "$1" "$#" "${2-}"
        case "$1" in
          --provider) PROVIDER="$2" ;;
          --profile) PROFILE="$2" ;;
          --engine) ENGINE="$2" ;;
          --protocols) PROTOCOLS="$2"; protocols_explicit="true" ;;
          --preset) INSTALL_PRESET="$2" ;;
          --uuid) SBD_UUID="$2" ;;
          --port-mode) PORT_MODE="$2" ;;
          --port-map) MANUAL_PORT_MAP="$2" ;;
          --main-port) INSTALL_MAIN_PORT="$2" ;;
          --argo) ARGO_MODE="$2" ;;
          --argo-domain) ARGO_DOMAIN="$2" ;;
          --argo-token) ARGO_TOKEN="$2" ;;
          --cdn-endpoints) ARGO_CDN_ENDPOINTS="$2" ;;
          --warp-mode) WARP_MODE="$2" ;;
          --route-mode) ROUTE_MODE="$2" ;;
          --ip-preference) IP_PREFERENCE="$2" ;;
          --cdn-host) CDN_TEMPLATE_HOST="$2" ;;
          --tls-mode) TLS_MODE="$2" ;;
          --acme-cert-path) ACME_CERT_PATH="$2" ;;
          --acme-key-path) ACME_KEY_PATH="$2" ;;
          --acme-domain) ACME_DOMAIN="$2" ;;
          --acme-email) ACME_EMAIL="$2" ;;
          --web-front) WEB_FRONT_MODE="$2" ;;
          --hy2-obfs) HY2_OBFS_MODE="$2" ;;
          --hy2-obfs-password) HY2_OBFS_PASSWORD="$2" ;;

          --reality-sni) REALITY_SERVER_NAME="$2" ;;
          --reality-fp) REALITY_FINGERPRINT="$2" ;;
          --reality-port) REALITY_HANDSHAKE_PORT="$2" ;;
          --tls-sni) TLS_SERVER_NAME="$2" ;;
          --vless-ws-path) VLESS_WS_PATH="$2" ;;
          --vless-xhttp-path) VLESS_XHTTP_PATH="$2" ;;
          --vless-xhttp-mode) VLESS_XHTTP_MODE="$2" ;;
          --xray-vless-enc) XRAY_VLESS_ENC="$2" ;;
          --xray-xhttp-reality) XRAY_XHTTP_REALITY="$2" ;;
          --cdn-host-vless-ws) CDN_HOST_VLESS_WS="$2" ;;
          --cdn-host-vless-xhttp) CDN_HOST_VLESS_XHTTP="$2" ;;
          --proxyip-vless-ws) PROXYIP_VLESS_WS="$2" ;;
          --proxyip-vless-xhttp) PROXYIP_VLESS_XHTTP="$2" ;;
          --domain-direct) DOMAIN_SPLIT_DIRECT="$2" ;;
          --domain-proxy) DOMAIN_SPLIT_PROXY="$2" ;;
          --domain-block) DOMAIN_SPLIT_BLOCK="$2" ;;
          --outbound-proxy-mode) OUTBOUND_PROXY_MODE="$2" ;;
          --outbound-proxy-host) OUTBOUND_PROXY_HOST="$2" ;;
          --outbound-proxy-port) OUTBOUND_PROXY_PORT="$2" ;;
          --outbound-proxy-user) OUTBOUND_PROXY_USER="$2" ;;
          --outbound-proxy-pass) OUTBOUND_PROXY_PASS="$2" ;;
        esac
        shift 2
        ;;
      *) die "Unknown install argument: $1" ;;
    esac
  done

  case "${INSTALL_PRESET:-}" in
    "") ;;
    reality-only)
      ENGINE="sing-box"
      PROFILE="lite"
      PROTOCOLS="vless-reality"
      protocols_explicit="true"
      ;;
    reality-plus-domain|reality-plus)
      ENGINE="sing-box"
      PROFILE="full"
      PROTOCOLS="vless-reality,hysteria2,tuic,naive"
      protocols_explicit="true"
      ;;
    full)
      ENGINE="sing-box"
      PROFILE="full"
      PROTOCOLS="vless-reality,vless-ws,shadowsocks-2022,naive,hysteria2,tuic"
      protocols_explicit="true"
      ;;
    *) die "--preset must be reality-only|reality-plus-domain|full" ;;
  esac

  if [[ "$protocols_explicit" != "true" && "$PROTOCOLS" == "$protocols_default_seed" ]]; then
    if [[ "$ENGINE" == "sing-box" ]]; then
      PROTOCOLS="vless-reality"
    else
      PROTOCOLS="vless-reality,vless-ws"
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
  if [[ -n "${SBD_UUID:-}" ]]; then
    [[ "$SBD_UUID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ ]] || die "--uuid must be a valid UUID"
  fi
  return 0
}

source "${PROJECT_ROOT}/lib/cli_args_common.sh"
source "${PROJECT_ROOT}/lib/cli_args_update.sh"
