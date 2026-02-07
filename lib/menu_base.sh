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
  wizard
}
