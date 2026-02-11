#!/usr/bin/env bash
# shellcheck disable=SC2034

require_option_value() {
  local opt="$1"
  local argc="$2"
  (( argc >= 2 )) || die "Option ${opt} requires a value"
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
      --protocol)
        require_option_value "$1" "$#"
        SET_PORT_PROTOCOL="$2"
        shift 2
        ;;
      --port)
        require_option_value "$1" "$#"
        SET_PORT_VALUE="$2"
        shift 2
        ;;
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
      --mode)
        require_option_value "$1" "$#"
        SET_EGRESS_MODE="$2"
        shift 2
        ;;
      --host)
        require_option_value "$1" "$#"
        SET_EGRESS_HOST="$2"
        shift 2
        ;;
      --port)
        require_option_value "$1" "$#"
        SET_EGRESS_PORT="$2"
        shift 2
        ;;
      --user)
        require_option_value "$1" "$#"
        SET_EGRESS_USER="$2"
        shift 2
        ;;
      --pass)
        require_option_value "$1" "$#"
        SET_EGRESS_PASS="$2"
        shift 2
        ;;
      *) die "Unknown set-egress argument: $1" ;;
    esac
  done
}
