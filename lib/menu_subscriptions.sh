#!/usr/bin/env bash

menu_subscriptions() {
  while true; do
    menu_status_header
    menu_title "$(msg "[订阅与分享]" "[Subscriptions]")"
    echo "1) $(msg "刷新订阅与分享产物（sub refresh）" "Refresh subscription artifacts (sub refresh)")"
    echo "2) $(msg "查看链接与二维码（sub show）" "Show links and QR (sub show)")"
    echo "3) $(msg "配置 GitLab 推送目标（sub gitlab-set）" "Configure GitLab target (sub gitlab-set)")"
    echo "4) $(msg "推送订阅到 GitLab（sub gitlab-push）" "Push subs to GitLab (sub gitlab-push)")"
    echo "5) $(msg "配置 Telegram 推送（sub tg-set）" "Configure Telegram target (sub tg-set)")"
    echo "6) $(msg "推送订阅到 Telegram（sub tg-push）" "Push subs to Telegram (sub tg-push)")"
    echo "0) $(msg "返回上级" "Back")"
    read -r -p "$(msg "请选择" "Select"): " c
    case "${c:-0}" in
      1) provider_sub_command refresh; menu_pause ;;
      2) provider_sub_command show; menu_pause ;;
      3)
        read -r -p "$(msg "GitLab token" "GitLab token"): " t
        read -r -p "$(msg "GitLab 项目(group/project)" "GitLab project(group/project)"): " p
        read -r -p "$(msg "分支(默认 main)" "branch(default main)"): " b
        read -r -p "$(msg "路径(默认 subs)" "path(default subs)"): " sp
        provider_sub_command gitlab-set "$t" "$p" "${b:-main}" "${sp:-subs}"
        menu_pause
        ;;
      4) provider_sub_command gitlab-push; menu_pause ;;
      5)
        read -r -p "$(msg "Telegram bot token" "Telegram bot token"): " bt
        read -r -p "$(msg "Telegram chat id" "Telegram chat id"): " cid
        provider_sub_command tg-set "$bt" "$cid"
        menu_pause
        ;;
      6) provider_sub_command tg-push; menu_pause ;;
      0) return 0 ;;
      *) menu_invalid; menu_pause ;;
    esac
  done
}
