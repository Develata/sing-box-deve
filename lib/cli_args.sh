#!/usr/bin/env bash
# shellcheck disable=SC2034

parse_install_args() {
  PROVIDER="vps"
  PROFILE="lite"
  ENGINE="sing-box"
  PROTOCOLS="vless-reality"
  DRY_RUN="false"
  AUTO_YES="${AUTO_YES:-false}"
  ARGO_MODE="${ARGO_MODE:-off}"
  ARGO_DOMAIN="${ARGO_DOMAIN:-}"
  ARGO_TOKEN="${ARGO_TOKEN:-}"
  WARP_MODE="${WARP_MODE:-off}"
  OUTBOUND_PROXY_MODE="${OUTBOUND_PROXY_MODE:-direct}"
  OUTBOUND_PROXY_HOST="${OUTBOUND_PROXY_HOST:-}"
  OUTBOUND_PROXY_PORT="${OUTBOUND_PROXY_PORT:-}"
  OUTBOUND_PROXY_USER="${OUTBOUND_PROXY_USER:-}"
  OUTBOUND_PROXY_PASS="${OUTBOUND_PROXY_PASS:-}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --provider) PROVIDER="$2"; shift 2 ;;
      --profile) PROFILE="$2"; shift 2 ;;
      --engine) ENGINE="$2"; shift 2 ;;
      --protocols) PROTOCOLS="$2"; shift 2 ;;
      --dry-run) DRY_RUN="true"; shift ;;
      --yes|-y) AUTO_YES="true"; shift ;;
      --argo) ARGO_MODE="$2"; shift 2 ;;
      --argo-domain) ARGO_DOMAIN="$2"; shift 2 ;;
      --argo-token) ARGO_TOKEN="$2"; shift 2 ;;
      --warp-mode) WARP_MODE="$2"; shift 2 ;;
      --outbound-proxy-mode) OUTBOUND_PROXY_MODE="$2"; shift 2 ;;
      --outbound-proxy-host) OUTBOUND_PROXY_HOST="$2"; shift 2 ;;
      --outbound-proxy-port) OUTBOUND_PROXY_PORT="$2"; shift 2 ;;
      --outbound-proxy-user) OUTBOUND_PROXY_USER="$2"; shift 2 ;;
      --outbound-proxy-pass) OUTBOUND_PROXY_PASS="$2"; shift 2 ;;
      *) die "Unknown install argument: $1" ;;
    esac
  done
}

parse_update_args() {
  UPDATE_SCRIPT="false"
  UPDATE_CORE="false"
  AUTO_YES="${AUTO_YES:-false}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --script) UPDATE_SCRIPT="true"; shift ;;
      --core) UPDATE_CORE="true"; shift ;;
      --all) UPDATE_SCRIPT="true"; UPDATE_CORE="true"; shift ;;
      --yes|-y) AUTO_YES="true"; shift ;;
      *) die "Unknown update argument: $1" ;;
    esac
  done

  if [[ "$UPDATE_SCRIPT" == "false" && "$UPDATE_CORE" == "false" ]]; then
    UPDATE_SCRIPT="true"
    UPDATE_CORE="true"
  fi
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
