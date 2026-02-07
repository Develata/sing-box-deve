#!/usr/bin/env bash

menu_main() {
  ensure_root
  detect_os
  init_runtime_layout

  while true; do
    menu_status_header
    menu_title "$(msg "[主菜单] 输入数字并回车" "[Main Menu] Enter number and press Enter")"
    echo "1) $(msg "安装/重装" "Install/Reinstall")"
    echo "2) $(msg "状态与节点查看" "Status & Nodes")"
    echo "3) $(msg "端口管理" "Port Management")"
    echo "4) $(msg "出站策略管理" "Egress Management")"
    echo "5) $(msg "服务管理" "Service Management")"
    echo "6) $(msg "更新管理" "Update Management")"
    echo "7) $(msg "防火墙管理" "Firewall Management")"
    echo "8) $(msg "设置管理" "Settings")"
    echo "9) $(msg "日志查看" "Logs")"
    echo "10) $(msg "卸载管理" "Uninstall")"
    echo "11) $(msg "订阅与分享" "Subscriptions")"
    echo "12) $(msg "配置变更中心" "Config Center")"
    echo "13) $(msg "内核与WARP" "Kernel & WARP")"
    echo "0) $(msg "退出" "Exit")"
    echo
    printf '%s\n' "$(msg "快捷提示: 直接输入 sb panel --full / sb list --nodes 也可执行命令模式" "Tip: You can also run command mode like sb panel --full / sb list --nodes")"
    read -r -p "$(msg "请选择" "Select"): " choice
    case "${choice:-0}" in
      1) menu_install ;;
      2) menu_view ;;
      3) menu_port ;;
      4) menu_egress ;;
      5) menu_service ;;
      6) menu_update ;;
      7) menu_firewall ;;
      8) menu_settings ;;
      9) menu_logs ;;
      10) menu_uninstall ;;
      11) menu_subscriptions ;;
      12) menu_config_center ;;
      13) menu_ops ;;
      0) break ;;
      *) menu_invalid; menu_pause ;;
    esac
  done
}
