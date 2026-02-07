#!/usr/bin/env bash

menu_subscriptions() {
  while true; do
    menu_status_header
    menu_title "$(msg "[订阅与分享]" "[Subscriptions]")"
    echo "1) sub refresh"
    echo "2) sub show"
    echo "3) sub gitlab-set"
    echo "4) sub gitlab-push"
    echo "5) sub tg-set"
    echo "6) sub tg-push"
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
