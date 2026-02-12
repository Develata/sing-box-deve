#!/usr/bin/env bash

source "${PROJECT_ROOT}/lib/cli_usage.sh"

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
    set-port-egress)
      shift
      parse_set_port_egress_args "$@"
      case "${SET_PORT_EGRESS_ACTION}" in
        list) provider_set_port_egress_info ;;
        clear) provider_set_port_egress_clear ;;
        map) provider_set_port_egress_map "$SET_PORT_EGRESS_MAP" ;;
        *) die "Usage: set-port-egress --list | --clear | --map <port:direct|proxy|warp|psiphon,...>" ;;
      esac
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
    split3)
      shift
      case "${1:-show}" in
        show) provider_split3_show ;;
        set) provider_split3_set "${2:-}" "${3:-}" "${4:-}" ;;
        *) die "Usage: split3 [show|set <direct_csv> <proxy_csv> <block_csv>]" ;;
      esac
      ;;
    jump)
      shift
      case "${1:-show}" in
        show) provider_jump_show ;;
        set) provider_jump_set "${2:-}" "${3:-}" "${4:-}" ;;
        clear) provider_jump_clear "${2:-}" "${3:-}" ;;
        replay) provider_jump_replay ;;
        *) die "Usage: jump [show|set <protocol> <main_port> <extra_csv>|clear [protocol] [main_port]|replay]" ;;
      esac
      ;;
    mport)
      shift
      provider_multi_ports_command "$@"
      ;;
    sub)
      shift
      provider_sub_command "$@"
      ;;
    cfg)
      shift
      provider_cfg_command "$@"
      ;;
    kernel)
      shift
      case "${1:-show}" in
        show) provider_kernel_show ;;
        set) provider_kernel_set "${2:-}" "${3:-latest}" ;;
        *) die "Usage: kernel [show|set <sing-box|xray> [tag|latest]]" ;;
      esac
      ;;
    warp)
      shift
      case "${1:-status}" in
        status) provider_warp_status ;;
        register) provider_warp_register ;;
        unlock) provider_warp_unlock_check ;;
        socks5-start) provider_warp_socks5_start "${2:-}" ;;
        socks5-stop) provider_warp_socks5_stop ;;
        socks5-status) provider_warp_socks5_status ;;
        *) die "Usage: warp [status|register|unlock|socks5-start [port]|socks5-stop|socks5-status]" ;;
      esac
      ;;
    psiphon)
      shift
      provider_psiphon_command "$@"
      ;;
    sys)
      shift
      provider_sys_command "$@"
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
    protocol)
      shift
      cli_handle_protocol_command "$@"
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
      cli_handle_fw_command "$@"
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
