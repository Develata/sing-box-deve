#!/usr/bin/env bash

menu_pause() {
  read -r -p "$(msg "按回车继续..." "Press Enter to continue...")" _
}

menu_title() {
  local title="$1"
  echo "------------------------------------------"
  echo "$title"
  echo "------------------------------------------"
}

menu_invalid() {
  log_warn "$(msg "无效选项，请重新输入。" "Invalid option, please try again.")"
}

menu_status_header() {
  clear || true
  log_info "========== sing-box-deve 控制台 =========="
  provider_status_header
  log_info "=========================================="
  echo
}

menu_install() {
  while true; do
    menu_status_header
    menu_title "$(msg "[安装/重装]" "[Install/Reinstall]")"
    echo "1) $(msg "交互安装（wizard）" "Interactive install (wizard)")"
    echo "2) $(msg "按运行态重装（apply --runtime）" "Reinstall from runtime (apply --runtime)")"
    echo "3) $(msg "按配置文件安装（apply -f）" "Install from config file (apply -f)")"
    echo "0) $(msg "返回上级" "Back")"
    read -r -p "$(msg "请选择" "Select"): " c
    case "${c:-0}" in
      1) wizard; menu_pause ;;
      2) apply_runtime; menu_pause ;;
      3)
        read -r -p "$(msg "配置文件路径" "config file path"): " cf
        if [[ -n "$cf" ]]; then
          apply_config "$cf"
        else
          log_warn "$(msg "未输入文件路径" "No file path entered")"
        fi
        menu_pause
        ;;
      0) return 0 ;;
      *) menu_invalid; menu_pause ;;
    esac
  done
}
