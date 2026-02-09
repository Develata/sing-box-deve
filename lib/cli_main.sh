#!/usr/bin/env bash
usage() {
  cat <<'EOF'
Usage:
  sing-box-deve.sh wizard
  sing-box-deve.sh menu
  sing-box-deve.sh install [--provider vps|serv00|sap|docker] [--profile lite|full] [--engine sing-box|xray] [--protocols p1,p2] [--port-mode random|manual] [--port-map proto:port[,proto:port...]] [--main-port PORT|--random-main-port] [--argo off|temp|fixed] [--argo-domain DOMAIN] [--argo-token TOKEN] [--warp-mode off|global|s|s4|s6|x|x4|x6|...] [--route-mode direct|global-proxy|cn-direct|cn-proxy] [--port-egress-map <port:direct|proxy|warp,...>] [--outbound-proxy-mode direct|socks|http|https] [--outbound-proxy-host HOST] [--outbound-proxy-port PORT] [--outbound-proxy-user USER] [--outbound-proxy-pass PASS] [--reality-sni SNI] [--reality-fp FP] [--tls-sni SNI] [--vmess-ws-path PATH] [--vless-ws-path PATH] [--vless-xhttp-path PATH] [--vless-xhttp-mode MODE] [--xray-vless-enc true|false] [--xray-xhttp-reality true|false] [--cdn-host-vmess HOST] [--cdn-host-vless-ws HOST] [--cdn-host-vless-xhttp HOST] [--proxyip-vmess IP] [--proxyip-vless-ws IP] [--proxyip-vless-xhttp IP] [--direct-share-endpoints CSV] [--proxy-share-endpoints CSV] [--warp-share-endpoints CSV] [--yes]
  sing-box-deve.sh apply -f config.env
  sing-box-deve.sh apply --runtime
  sing-box-deve.sh list [--runtime|--nodes|--settings|--all]
  sing-box-deve.sh panel [--compact|--full]
  sing-box-deve.sh restart [--core|--argo|--all]
  sing-box-deve.sh logs [--core|--argo]
  sing-box-deve.sh set-port --list
  sing-box-deve.sh set-port --protocol <name> --port <1-65535>
  sing-box-deve.sh set-port-egress --list|--clear|--map <port:direct|proxy|warp,...>
  sing-box-deve.sh set-egress --mode direct|socks|http|https [--host HOST] [--port PORT] [--user USER] [--pass PASS]
  sing-box-deve.sh set-route <direct|global-proxy|cn-direct|cn-proxy>
  sing-box-deve.sh set-share <direct|proxy|warp> <host:port[,host:port...]>
  sing-box-deve.sh split3 show
  sing-box-deve.sh split3 set <direct_csv> <proxy_csv> <block_csv>
  sing-box-deve.sh jump show|clear|replay|set <protocol> <main_port> <extra_csv>
  sing-box-deve.sh sub refresh|show|rules-update
  sing-box-deve.sh sub gitlab-set <token> <group/project> [branch] [path]
  sing-box-deve.sh sub gitlab-push
  sing-box-deve.sh sub tg-set <bot_token> <chat_id>
  sing-box-deve.sh sub tg-push
  sing-box-deve.sh cfg preview <rotate-id|argo|ip-pref|cdn-host|domain-split|tls|rebuild> ...
  sing-box-deve.sh cfg apply <rotate-id|argo|ip-pref|cdn-host|domain-split|tls|rebuild> ...
  sing-box-deve.sh cfg rollback [snapshot_id|latest]
  sing-box-deve.sh cfg snapshots list
  sing-box-deve.sh cfg snapshots prune [keep_count]
  sing-box-deve.sh cfg rotate-id
  sing-box-deve.sh cfg argo <off|temp|fixed> [token] [domain]
  sing-box-deve.sh cfg ip-pref <auto|v4|v6>
  sing-box-deve.sh cfg cdn-host <domain>
  sing-box-deve.sh cfg domain-split <direct_csv> <proxy_csv> <block_csv>
  sing-box-deve.sh cfg tls <self-signed|acme|acme-auto> [cert_path|domain] [key_path|email] [dns_provider]
  sing-box-deve.sh cfg rebuild
  sing-box-deve.sh kernel show
  sing-box-deve.sh kernel set <sing-box|xray> [tag|latest]
  sing-box-deve.sh warp status|register|unlock|socks5-start [port]|socks5-stop|socks5-status
  sing-box-deve.sh sys bbr-status
  sing-box-deve.sh sys bbr-enable
  sing-box-deve.sh sys acme-install
  sing-box-deve.sh sys acme-issue <domain> <email> [dns_provider]
  sing-box-deve.sh sys acme-apply <cert_path> <key_path>
  sing-box-deve.sh regen-nodes
  sing-box-deve.sh update [--script|--core|--all] [--source auto|primary|backup] [--yes]
  sing-box-deve.sh version
  sing-box-deve.sh protocol matrix [--enabled]
  sing-box-deve.sh settings show
  sing-box-deve.sh settings set <key> <value>
  sing-box-deve.sh settings set key1=value1 key2=value2 ...
  sing-box-deve.sh uninstall [--keep-settings]
  sing-box-deve.sh doctor
  sing-box-deve.sh fw status
  sing-box-deve.sh fw rollback
  sing-box-deve.sh fw replay
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
    set-port-egress)
      shift
      parse_set_port_egress_args "$@"
      case "${SET_PORT_EGRESS_ACTION}" in
        list) provider_set_port_egress_info ;;
        clear) provider_set_port_egress_clear ;;
        map) provider_set_port_egress_map "$SET_PORT_EGRESS_MAP" ;;
        *) die "Usage: set-port-egress --list | --clear | --map <port:direct|proxy|warp,...>" ;;
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
        clear) provider_jump_clear ;;
        replay) provider_jump_replay ;;
        *) die "Usage: jump [show|set <protocol> <main_port> <extra_csv>|clear|replay]" ;;
      esac
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
        show)
          provider_kernel_show
          ;;
        set)
          provider_kernel_set "${2:-}" "${3:-latest}"
          ;;
        *)
          die "Usage: kernel [show|set <sing-box|xray> [tag|latest]]"
          ;;
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
