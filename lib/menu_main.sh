#!/usr/bin/env bash

menu_main_descriptions() {
  printf '%s\n' "$(msg "功能说明：" "Feature guide:")"
  printf '%s\n' "$(msg " 1 安装/重装：首次部署或按新参数重建配置" " 1 Install/Reinstall: first deploy or rebuild with new parameters")"
  printf '%s\n' "$(msg " 2 状态与节点查看：查看运行状态、节点、协议能力矩阵" " 2 Status & Nodes: inspect runtime, node links, protocol matrix")"
  printf '%s\n' "$(msg " 3 端口管理：查看/修改各协议监听端口并自动放行防火墙" " 3 Port Management: view/change protocol ports with firewall open")"
  printf '%s\n' "$(msg " 4 出站策略管理：设置直连/上游代理/分流路由/分享出口" " 4 Egress: direct/upstream proxy/route/share endpoints")"
  printf '%s\n' "$(msg " 5 服务管理：重启核心与 Argo、刷新节点、看日志" " 5 Service: restart core/argo, regenerate nodes, view logs")"
  printf '%s\n' "$(msg " 6 更新管理：更新脚本或内核，支持主源/备源" " 6 Update: script/core updates with primary/backup source")"
  printf '%s\n' "$(msg " 7 防火墙管理：查看托管规则、回滚、重放持久化规则" " 7 Firewall: managed rules, rollback, replay")"
  printf '%s\n' "$(msg " 8 设置管理：语言与自动确认开关" " 8 Settings: language and auto-yes")"
  printf '%s\n' "$(msg " 9 日志查看：快速查看核心或 Argo 日志" " 9 Logs: quick core/argo logs")"
  printf '%s\n' "$(msg "10 卸载管理：保留设置或完全卸载" "10 Uninstall: keep settings or full cleanup")"
  printf '%s\n' "$(msg "11 订阅与分享：刷新订阅、展示二维码、推送目标配置" "11 Subscriptions: refresh, QR display, push target setup")"
  printf '%s\n' "$(msg "12 配置变更中心：预览/应用/回滚快照与协议增减" "12 Config Center: preview/apply/rollback snapshots and protocols")"
  printf '%s\n' "$(msg "13 内核与 WARP：内核切换、WARP、BBR、证书工具" "13 Kernel & WARP: engine switch, WARP, BBR, cert tools")"
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
    menu_main_descriptions
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
