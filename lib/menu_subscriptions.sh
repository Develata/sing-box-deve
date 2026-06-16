#!/usr/bin/env bash

menu_subscriptions() {
  while true; do
    menu_status_header
    menu_title "$(msg "[订阅与分享]" "[Subscriptions]")"
    echo "1) $(msg "刷新订阅与分享产物（sub refresh）" "Refresh subscription artifacts (sub refresh)")"
    echo "2) $(msg "查看链接与二维码（sub show）" "Show links and QR (sub show)")"
    echo "3) $(msg "重同步规则集（clash+服务端路由）（sub rules-update）" "Re-sync rulesets (clash+server route) (sub rules-update)")"
    echo "0) $(msg "返回上级" "Back")"
    read -r -p "$(msg "请选择" "Select"): " c
    case "${c:-0}" in
      1) provider_sub_command refresh; menu_pause ;;
      2) provider_sub_command show; menu_pause ;;
      3) provider_sub_command rules-update; menu_pause ;;
      0) return 0 ;;
      *) menu_invalid; menu_pause ;;
    esac
  done
}
