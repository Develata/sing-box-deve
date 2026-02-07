#!/usr/bin/env bash

usage() {
  cat <<'EOF'
Usage:
  sing-box-deve.sh wizard
  sing-box-deve.sh menu
  sing-box-deve.sh install [--provider vps|serv00|sap|docker] [--profile lite|full] [--engine sing-box|xray] [--protocols p1,p2] [--argo off|temp|fixed] [--argo-domain DOMAIN] [--argo-token TOKEN] [--warp-mode off|global|s|s4|s6|x|x4|x6|...] [--route-mode direct|global-proxy|cn-direct|cn-proxy] [--outbound-proxy-mode direct|socks|http|https] [--outbound-proxy-host HOST] [--outbound-proxy-port PORT] [--outbound-proxy-user USER] [--outbound-proxy-pass PASS] [--direct-share-endpoints CSV] [--proxy-share-endpoints CSV] [--warp-share-endpoints CSV] [--yes]
  sing-box-deve.sh apply -f config.env
  sing-box-deve.sh apply --runtime
  sing-box-deve.sh list [--runtime|--nodes|--settings|--all]
  sing-box-deve.sh panel [--compact|--full]
  sing-box-deve.sh restart [--core|--argo|--all]
  sing-box-deve.sh logs [--core|--argo]
  sing-box-deve.sh set-port --list
  sing-box-deve.sh set-port --protocol <name> --port <1-65535>
  sing-box-deve.sh set-egress --mode direct|socks|http|https [--host HOST] [--port PORT] [--user USER] [--pass PASS]
  sing-box-deve.sh set-route <direct|global-proxy|cn-direct|cn-proxy>
  sing-box-deve.sh set-share <direct|proxy|warp> <host:port[,host:port...]>
  sing-box-deve.sh regen-nodes
  sing-box-deve.sh update [--script|--core|--all] [--yes]
  sing-box-deve.sh version
  sing-box-deve.sh settings show
  sing-box-deve.sh settings set <key> <value>
  sing-box-deve.sh settings set key1=value1 key2=value2 ...
  sing-box-deve.sh uninstall [--keep-settings]
  sing-box-deve.sh doctor
  sing-box-deve.sh fw status
  sing-box-deve.sh fw rollback

Examples:
  ./sing-box-deve.sh install --provider vps --profile lite --engine sing-box --protocols vless-reality
  ./sing-box-deve.sh apply -f ./config.env
EOF
}

main() {
  local cmd="${1:-help}"
  if [[ "$cmd" == "help" ]] && declare -F legacy_env_detected >/dev/null 2>&1 && legacy_env_detected; then
    parse_install_args
    run_install "$PROVIDER" "$PROFILE" "$ENGINE" "$PROTOCOLS" "$DRY_RUN"
    return 0
  fi
  case "$cmd" in
    wizard)
      shift
      wizard "$@"
      ;;
    menu)
      shift
      menu_main "$@"
      ;;
    install)
      shift
      parse_install_args "$@"
      run_install "$PROVIDER" "$PROFILE" "$ENGINE" "$PROTOCOLS" "$DRY_RUN"
      ;;
    apply)
      shift
      if [[ "${1:-}" == "--runtime" ]]; then
        apply_runtime
      elif [[ "${1:-}" == "-f" ]] && [[ -n "${2:-}" ]]; then
        apply_config "$2"
      else
        die "Usage: apply -f config.env | apply --runtime"
      fi
      ;;
    list)
      shift
      parse_list_args "$@"
      provider_list "$LIST_MODE"
      ;;
    panel|status)
      shift
      parse_panel_args "$@"
      provider_panel "$PANEL_MODE"
      ;;
    restart)
      shift
      parse_restart_args "$@"
      provider_restart "$RESTART_TARGET"
      ;;
    logs)
      shift
      parse_logs_args "$@"
      provider_logs "$LOG_TARGET"
      ;;
    set-port)
      shift
      parse_set_port_args "$@"
      if [[ -z "${SET_PORT_PROTOCOL}" ]]; then
        provider_set_port_info
      else
        provider_set_port "$SET_PORT_PROTOCOL" "$SET_PORT_VALUE"
      fi
      ;;
    set-egress)
      shift
      parse_set_egress_args "$@"
      provider_set_egress "$SET_EGRESS_MODE" "$SET_EGRESS_HOST" "$SET_EGRESS_PORT" "$SET_EGRESS_USER" "$SET_EGRESS_PASS"
      ;;
    set-route)
      shift
      parse_set_route_args "$@"
      provider_set_route "$SET_ROUTE_MODE"
      ;;
    set-share)
      shift
      parse_set_share_args "$@"
      provider_set_share_endpoints "$SET_SHARE_KIND" "$SET_SHARE_ENDPOINTS"
      ;;
    regen-nodes)
      shift
      provider_regen_nodes
      ;;
    update)
      shift
      update_command "$@"
      ;;
    version)
      shift
      show_version
      ;;
    settings)
      shift
      settings_command "$@"
      ;;
    uninstall)
      shift
      parse_uninstall_args "$@"
      provider_uninstall "$KEEP_SETTINGS"
      ;;
    doctor)
      shift
      doctor
      ;;
    fw)
      shift
      case "${1:-}" in
        status)
          fw_detect_backend
          fw_status
          ;;
        rollback)
          fw_detect_backend
          fw_rollback
          ;;
        *)
          die "Usage: fw [status|rollback]"
          ;;
      esac
      ;;
    help|-h|--help)
      usage
      ;;
    *)
      usage
      die "Unknown command: $cmd"
      ;;
  esac
}
