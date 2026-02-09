#!/usr/bin/env bash
# shellcheck disable=SC2034

parse_install_args() {
  PROVIDER="vps"
  PROFILE="lite"
  ENGINE="sing-box"
  PROTOCOLS="vless-reality"
  DRY_RUN="false"
  PORT_MODE="${PORT_MODE:-random}"
  MANUAL_PORT_MAP="${MANUAL_PORT_MAP:-}"
  INSTALL_MAIN_PORT="${INSTALL_MAIN_PORT:-}"
  RANDOM_MAIN_PORT="${RANDOM_MAIN_PORT:-false}"
  AUTO_YES="${AUTO_YES:-false}"
  ARGO_MODE="${ARGO_MODE:-off}"
  ARGO_DOMAIN="${ARGO_DOMAIN:-}"
  ARGO_TOKEN="${ARGO_TOKEN:-}"
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
      --provider) PROVIDER="$2"; shift 2 ;;
      --profile) PROFILE="$2"; shift 2 ;;
      --engine) ENGINE="$2"; shift 2 ;;
      --protocols) PROTOCOLS="$2"; shift 2 ;;
      --dry-run) DRY_RUN="true"; shift ;;
      --port-mode) PORT_MODE="$2"; shift 2 ;;
      --port-map) MANUAL_PORT_MAP="$2"; shift 2 ;;
      --main-port) INSTALL_MAIN_PORT="$2"; shift 2 ;;
      --random-main-port) RANDOM_MAIN_PORT="true"; shift ;;
      --yes|-y) AUTO_YES="true"; shift ;;
      --argo) ARGO_MODE="$2"; shift 2 ;;
      --argo-domain) ARGO_DOMAIN="$2"; shift 2 ;;
      --argo-token) ARGO_TOKEN="$2"; shift 2 ;;
      --warp-mode) WARP_MODE="$2"; shift 2 ;;
      --route-mode) ROUTE_MODE="$2"; shift 2 ;;
      --ip-preference) IP_PREFERENCE="$2"; shift 2 ;;
      --cdn-host) CDN_TEMPLATE_HOST="$2"; shift 2 ;;
      --tls-mode) TLS_MODE="$2"; shift 2 ;;
      --acme-cert-path) ACME_CERT_PATH="$2"; shift 2 ;;
      --acme-key-path) ACME_KEY_PATH="$2"; shift 2 ;;
      --reality-sni) REALITY_SERVER_NAME="$2"; shift 2 ;;
      --reality-fp) REALITY_FINGERPRINT="$2"; shift 2 ;;
      --reality-port) REALITY_HANDSHAKE_PORT="$2"; shift 2 ;;
      --tls-sni) TLS_SERVER_NAME="$2"; shift 2 ;;
      --vmess-ws-path) VMESS_WS_PATH="$2"; shift 2 ;;
      --vless-ws-path) VLESS_WS_PATH="$2"; shift 2 ;;
      --vless-xhttp-path) VLESS_XHTTP_PATH="$2"; shift 2 ;;
      --vless-xhttp-mode) VLESS_XHTTP_MODE="$2"; shift 2 ;;
      --xray-vless-enc) XRAY_VLESS_ENC="$2"; shift 2 ;;
      --xray-xhttp-reality) XRAY_XHTTP_REALITY="$2"; shift 2 ;;
      --cdn-host-vmess) CDN_HOST_VMESS="$2"; shift 2 ;;
      --cdn-host-vless-ws) CDN_HOST_VLESS_WS="$2"; shift 2 ;;
      --cdn-host-vless-xhttp) CDN_HOST_VLESS_XHTTP="$2"; shift 2 ;;
      --proxyip-vmess) PROXYIP_VMESS="$2"; shift 2 ;;
      --proxyip-vless-ws) PROXYIP_VLESS_WS="$2"; shift 2 ;;
      --proxyip-vless-xhttp) PROXYIP_VLESS_XHTTP="$2"; shift 2 ;;
      --domain-direct) DOMAIN_SPLIT_DIRECT="$2"; shift 2 ;;
      --domain-proxy) DOMAIN_SPLIT_PROXY="$2"; shift 2 ;;
      --domain-block) DOMAIN_SPLIT_BLOCK="$2"; shift 2 ;;
      --port-egress-map) PORT_EGRESS_MAP="$2"; shift 2 ;;
      --outbound-proxy-mode) OUTBOUND_PROXY_MODE="$2"; shift 2 ;;
      --outbound-proxy-host) OUTBOUND_PROXY_HOST="$2"; shift 2 ;;
      --outbound-proxy-port) OUTBOUND_PROXY_PORT="$2"; shift 2 ;;
      --outbound-proxy-user) OUTBOUND_PROXY_USER="$2"; shift 2 ;;
      --outbound-proxy-pass) OUTBOUND_PROXY_PASS="$2"; shift 2 ;;
      --direct-share-endpoints) DIRECT_SHARE_ENDPOINTS="$2"; shift 2 ;;
      --proxy-share-endpoints) PROXY_SHARE_ENDPOINTS="$2"; shift 2 ;;
      --warp-share-endpoints) WARP_SHARE_ENDPOINTS="$2"; shift 2 ;;
      *) die "Unknown install argument: $1" ;;
    esac
  done

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
  return 0
}

parse_set_route_args() {
  SET_ROUTE_MODE="${1:-}"
  [[ -n "$SET_ROUTE_MODE" ]] || die "Usage: set-route <direct|global-proxy|cn-direct|cn-proxy>"
}

parse_set_share_args() {
  SET_SHARE_KIND="${1:-}"
  SET_SHARE_ENDPOINTS="${2:-}"
  case "$SET_SHARE_KIND" in
    direct|proxy|warp) ;;
    *) die "Usage: set-share <direct|proxy|warp> <host:port[,host:port...]>" ;;
  esac
  [[ -n "$SET_SHARE_ENDPOINTS" ]] || die "Usage: set-share <direct|proxy|warp> <host:port[,host:port...]>"
}

parse_list_args() {
  LIST_MODE="all"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --runtime) LIST_MODE="runtime"; shift ;;
      --nodes) LIST_MODE="nodes"; shift ;;
      --settings) LIST_MODE="settings"; shift ;;
      --all) LIST_MODE="all"; shift ;;
      *) die "Unknown list argument: $1" ;;
    esac
  done
}

parse_panel_args() {
  PANEL_MODE="compact"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --compact) PANEL_MODE="compact"; shift ;;
      --full) PANEL_MODE="full"; shift ;;
      *) die "Unknown panel argument: $1" ;;
    esac
  done
}

parse_restart_args() {
  RESTART_TARGET="all"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --core) RESTART_TARGET="core"; shift ;;
      --argo) RESTART_TARGET="argo"; shift ;;
      --all) RESTART_TARGET="all"; shift ;;
      *) die "Unknown restart argument: $1" ;;
    esac
  done
}

parse_logs_args() {
  LOG_TARGET="core"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --core) LOG_TARGET="core"; shift ;;
      --argo) LOG_TARGET="argo"; shift ;;
      *) die "Unknown logs argument: $1" ;;
    esac
  done
}

parse_uninstall_args() {
  KEEP_SETTINGS="false"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --keep-settings) KEEP_SETTINGS="true"; shift ;;
      *) die "Unknown uninstall argument: $1" ;;
    esac
  done
}

parse_set_port_args() {
  if [[ $# -eq 0 ]] || [[ "${1:-}" == "--list" ]]; then
    SET_PORT_PROTOCOL=""
    SET_PORT_VALUE=""
    return 0
  fi

  SET_PORT_PROTOCOL=""
  SET_PORT_VALUE=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --protocol) SET_PORT_PROTOCOL="$2"; shift 2 ;;
      --port) SET_PORT_VALUE="$2"; shift 2 ;;
      *) die "Unknown set-port argument: $1" ;;
    esac
  done
  [[ -n "$SET_PORT_PROTOCOL" && -n "$SET_PORT_VALUE" ]] || die "Usage: set-port --list | set-port --protocol <name> --port <1-65535>"
}

parse_set_egress_args() {
  SET_EGRESS_MODE="direct"
  SET_EGRESS_HOST=""
  SET_EGRESS_PORT=""
  SET_EGRESS_USER=""
  SET_EGRESS_PASS=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode) SET_EGRESS_MODE="$2"; shift 2 ;;
      --host) SET_EGRESS_HOST="$2"; shift 2 ;;
      --port) SET_EGRESS_PORT="$2"; shift 2 ;;
      --user) SET_EGRESS_USER="$2"; shift 2 ;;
      --pass) SET_EGRESS_PASS="$2"; shift 2 ;;
      *) die "Unknown set-egress argument: $1" ;;
    esac
  done
}

source "${PROJECT_ROOT}/lib/cli_args_update.sh"
source "${PROJECT_ROOT}/lib/cli_args_port_egress.sh"
