#!/usr/bin/env bash

menu_view() {
  while true; do
    menu_status_header
    menu_title "$(msg "[状态与节点查看]" "[Status & Nodes]")"
    echo "1) panel --full"
    echo "2) list --all"
    echo "3) list --nodes"
    echo "0) $(msg "返回上级" "Back")"
    read -r -p "$(msg "请选择" "Select"): " c
    case "${c:-0}" in
      1) provider_panel full; menu_pause ;;
      2) provider_list all; menu_pause ;;
      3) provider_list nodes; menu_pause ;;
      0) return 0 ;;
      *) menu_invalid; menu_pause ;;
    esac
  done
}

menu_port() {
  while true; do
    menu_status_header
    menu_title "$(msg "[端口管理]" "[Port Management]")"
    echo "1) set-port --list"
    echo "2) set-port --protocol ... --port ..."
    echo "0) $(msg "返回上级" "Back")"
    read -r -p "$(msg "请选择" "Select"): " c
    case "${c:-0}" in
      1) provider_set_port_info; menu_pause ;;
      2)
        read -r -p "$(msg "输入协议名" "Protocol name"): " p
        read -r -p "$(msg "输入新端口(1-65535)" "New port(1-65535)"): " port
        provider_set_port "$p" "$port"
        menu_pause
        ;;
      0) return 0 ;;
      *) menu_invalid; menu_pause ;;
    esac
  done
}

menu_egress() {
  while true; do
    menu_status_header
    menu_title "$(msg "[出站策略管理]" "[Egress Management]")"
    echo "1) set-egress direct"
    echo "2) set-egress socks/http/https"
    echo "3) set-route direct/global-proxy/cn-direct/cn-proxy"
    echo "4) set-share direct/proxy/warp endpoints"
    echo "0) $(msg "返回上级" "Back")"
    read -r -p "$(msg "请选择" "Select"): " c
    case "${c:-0}" in
      1)
        provider_set_egress direct "" "" "" ""
        menu_pause
        ;;
      2)
        read -r -p "mode[socks/http/https]: " m
        read -r -p "host: " h
        read -r -p "port: " p
        read -r -p "user(optional): " u
        read -r -p "pass(optional): " pw
        provider_set_egress "$m" "$h" "$p" "$u" "$pw"
        menu_pause
        ;;
      3)
        read -r -p "route mode[direct/global-proxy/cn-direct/cn-proxy]: " rm
        provider_set_route "$rm"
        menu_pause
        ;;
      4)
        read -r -p "share kind[direct/proxy/warp]: " sk
        read -r -p "endpoints(host:port,host:port...): " se
        provider_set_share_endpoints "$sk" "$se"
        menu_pause
        ;;
      0) return 0 ;;
      *) menu_invalid; menu_pause ;;
    esac
  done
}

menu_service() {
  while true; do
    menu_status_header
    menu_title "$(msg "[服务管理]" "[Service Management]")"
    echo "1) restart --all"
    echo "2) restart --core"
    echo "3) restart --argo"
    echo "4) regen-nodes"
    echo "5) logs --core"
    echo "6) logs --argo"
    echo "0) $(msg "返回上级" "Back")"
    read -r -p "$(msg "请选择" "Select"): " c
    case "${c:-0}" in
      1) provider_restart all; menu_pause ;;
      2) provider_restart core; menu_pause ;;
      3) provider_restart argo; menu_pause ;;
      4) provider_regen_nodes; menu_pause ;;
      5) provider_logs core; menu_pause ;;
      6) provider_logs argo; menu_pause ;;
      0) return 0 ;;
      *) menu_invalid; menu_pause ;;
    esac
  done
}

menu_update() {
  while true; do
    menu_status_header
    menu_title "$(msg "[更新管理]" "[Update Management]")"
    echo "1) update --core"
    echo "2) update --script"
    echo "3) update --all"
    echo "0) $(msg "返回上级" "Back")"
    read -r -p "$(msg "请选择" "Select"): " c
    case "${c:-0}" in
      1) update_command --core --yes; menu_pause ;;
      2) update_command --script --yes; menu_pause ;;
      3) update_command --all --yes; menu_pause ;;
      0) return 0 ;;
      *) menu_invalid; menu_pause ;;
    esac
  done
}

menu_firewall() {
  while true; do
    menu_status_header
    menu_title "$(msg "[防火墙管理]" "[Firewall Management]")"
    echo "1) fw status"
    echo "2) fw rollback"
    echo "0) $(msg "返回上级" "Back")"
    read -r -p "$(msg "请选择" "Select"): " c
    case "${c:-0}" in
      1) fw_detect_backend; fw_status; menu_pause ;;
      2) fw_detect_backend; fw_rollback; menu_pause ;;
      0) return 0 ;;
      *) menu_invalid; menu_pause ;;
    esac
  done
}

menu_settings() {
  while true; do
    menu_status_header
    menu_title "$(msg "[设置管理]" "[Settings]")"
    echo "1) settings show"
    echo "2) settings set lang"
    echo "3) settings set auto_yes"
    echo "0) $(msg "返回上级" "Back")"
    read -r -p "$(msg "请选择" "Select"): " c
    case "${c:-0}" in
      1) show_settings; menu_pause ;;
      2)
        read -r -p "lang[zh/en]: " l
        set_setting lang "$l"
        show_settings
        menu_pause
        ;;
      3)
        read -r -p "auto_yes[true/false]: " ay
        set_setting auto_yes "$ay"
        show_settings
        menu_pause
        ;;
      0) return 0 ;;
      *) menu_invalid; menu_pause ;;
    esac
  done
}

menu_logs() {
  while true; do
    menu_status_header
    menu_title "$(msg "[日志查看]" "[Logs]")"
    echo "1) logs --core"
    echo "2) logs --argo"
    echo "0) $(msg "返回上级" "Back")"
    read -r -p "$(msg "请选择" "Select"): " c
    case "${c:-0}" in
      1) provider_logs core; menu_pause ;;
      2) provider_logs argo; menu_pause ;;
      0) return 0 ;;
      *) menu_invalid; menu_pause ;;
    esac
  done
}

menu_uninstall() {
  menu_status_header
  menu_title "$(msg "[卸载管理]" "[Uninstall]")"
  echo "1) uninstall --keep-settings"
  echo "2) uninstall"
  echo "0) $(msg "返回上级" "Back")"
  read -r -p "$(msg "请选择" "Select"): " c
  case "${c:-0}" in
    1)
      if prompt_yes_no "$(msg "确认卸载并保留 settings?" "Confirm uninstall and keep settings?")" "N"; then
        provider_uninstall true
      fi
      ;;
    2)
      if prompt_yes_no "$(msg "确认完全卸载?" "Confirm full uninstall?")" "N"; then
        provider_uninstall false
      fi
      ;;
    0) return 0 ;;
    *) menu_invalid ;;
  esac
  menu_pause
}
