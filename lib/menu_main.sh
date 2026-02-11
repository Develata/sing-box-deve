#!/usr/bin/env bash

menu_main_descriptions() {
  printf '%s\n' "$(msg "功能说明：" "Feature guide:")"
  printf '%s\n' "$(msg " 1 安装/重装：首次部署或按新参数重建配置" " 1 Install/Reinstall: first deploy or rebuild with new parameters")"
  printf '%s\n' "$(msg " 2 状态与节点查看：查看运行状态、节点信息与运行摘要" " 2 Status & Nodes: inspect runtime, node links and summary")"
  printf '%s\n' "$(msg " 3 协议管理：协议增删与协议能力矩阵" " 3 Protocol Management: protocol add/remove and capability matrix")"
  printf '%s\n' "$(msg " 4 端口管理：查看/修改各协议监听端口并自动放行防火墙" " 4 Port Management: view/change protocol ports with firewall open")"
  printf '%s\n' "$(msg " 5 出站策略管理：设置直连/上游代理/分流路由/按端口策略/分享出口" " 5 Egress: direct/upstream proxy/route/port-policy/share endpoints")"
  printf '%s\n' "$(msg " 6 服务管理：重启核心与 Argo、刷新节点、看日志" " 6 Service: restart core/argo, regenerate nodes, view logs")"
  printf '%s\n' "$(msg " 7 更新管理：更新脚本或内核，支持主源/备源" " 7 Update: script/core updates with primary/backup source")"
  printf '%s\n' "$(msg " 8 防火墙管理：查看托管规则、回滚、重放持久化规则" " 8 Firewall: managed rules, rollback, replay")"
  printf '%s\n' "$(msg " 9 设置管理：语言与自动确认开关" " 9 Settings: language and auto-yes")"
  printf '%s\n' "$(msg "10 日志查看：快速查看核心或 Argo 日志" "10 Logs: quick core/argo logs")"
  printf '%s\n' "$(msg "11 卸载管理：保留设置或完全卸载" "11 Uninstall: keep settings or full cleanup")"
  printf '%s\n' "$(msg "12 订阅与分享：刷新订阅、展示二维码、推送目标配置" "12 Subscriptions: refresh, QR display, push target setup")"
  printf '%s\n' "$(msg "13 配置变更中心：预览/应用/回滚快照与高级变更" "13 Config Center: preview/apply/rollback snapshots and advanced changes")"
  printf '%s\n' "$(msg "14 内核与 WARP：内核切换、WARP、BBR、证书工具" "14 Kernel & WARP: engine switch, WARP, BBR, cert tools")"
}

menu_main() {
  ensure_root
  detect_os
  init_runtime_layout

  while true; do
    menu_status_header
    menu_title "$(msg "[主菜单] 输入数字并回车" "[Main Menu] Enter number and press Enter")"
    echo "1) $(msg "安装/重装" "Install/Reinstall")"
    echo "2) $(msg "状态与节点查看" "Status & Nodes")"
    echo "3) $(msg "协议管理" "Protocol Management")"
    echo "4) $(msg "端口管理" "Port Management")"
    echo "5) $(msg "出站策略管理" "Egress Management")"
    echo "6) $(msg "服务管理" "Service Management")"
    echo "7) $(msg "更新管理" "Update Management")"
    echo "8) $(msg "防火墙管理" "Firewall Management")"
    echo "9) $(msg "设置管理" "Settings")"
    echo "10) $(msg "日志查看" "Logs")"
    echo "11) $(msg "卸载管理" "Uninstall")"
    echo "12) $(msg "订阅与分享" "Subscriptions")"
    echo "13) $(msg "配置变更中心" "Config Center")"
    echo "14) $(msg "内核与WARP" "Kernel & WARP")"
    echo "0) $(msg "退出" "Exit")"
    echo
    menu_main_descriptions
    echo
    printf '%s\n' "$(msg "快捷提示: 直接输入 sb panel --full / sb list --nodes 也可执行命令模式" "Tip: You can also run command mode like sb panel --full / sb list --nodes")"
    read -r -p "$(msg "请选择" "Select"): " choice
    case "${choice:-0}" in
      1) menu_install ;;
      2) menu_view ;;
      3) menu_protocol ;;
      4) menu_port ;;
      5) menu_egress ;;
      6) menu_service ;;
      7) menu_update ;;
      8) menu_firewall ;;
      9) menu_settings ;;
      10) menu_logs ;;
      11) menu_uninstall ;;
      12) menu_subscriptions ;;
      13) menu_config_center ;;
      14) menu_ops ;;
      0) break ;;
      *) menu_invalid; menu_pause ;;
    esac
  done
}
