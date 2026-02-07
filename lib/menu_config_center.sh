#!/usr/bin/env bash

menu_config_center() {
  while true; do
    menu_status_header
    menu_title "$(msg "[配置变更中心]" "[Config Center]")"
    echo "1) cfg rotate-id"
    echo "2) cfg argo off/temp/fixed"
    echo "3) cfg ip-pref auto/v4/v6"
    echo "4) cfg cdn-host <domain>"
    echo "5) cfg domain-split direct/proxy/block"
    echo "6) cfg tls self-signed/acme"
    echo "7) cfg rebuild"
    echo "0) $(msg "返回上级" "Back")"
    read -r -p "$(msg "请选择" "Select"): " c
    case "${c:-0}" in
      1) provider_cfg_command rotate-id; menu_pause ;;
      2)
        read -r -p "argo mode[off/temp/fixed]: " m
        read -r -p "token(optional): " t
        read -r -p "domain(optional): " d
        provider_cfg_command argo "$m" "$t" "$d"
        menu_pause
        ;;
      3)
        read -r -p "ip preference[auto/v4/v6]: " p
        provider_cfg_command ip-pref "$p"
        menu_pause
        ;;
      4)
        read -r -p "cdn host: " h
        provider_cfg_command cdn-host "$h"
        menu_pause
        ;;
      5)
        read -r -p "direct domains(csv): " dd
        read -r -p "proxy domains(csv): " pd
        read -r -p "block domains(csv): " bd
        provider_cfg_command domain-split "$dd" "$pd" "$bd"
        menu_pause
        ;;
      6)
        read -r -p "tls mode[self-signed/acme]: " tm
        if [[ "$tm" == "acme" ]]; then
          read -r -p "acme cert path: " cp
          read -r -p "acme key path: " kp
          provider_cfg_command tls "$tm" "$cp" "$kp"
        else
          provider_cfg_command tls "$tm"
        fi
        menu_pause
        ;;
      7) provider_cfg_command rebuild; menu_pause ;;
      0) return 0 ;;
      *) menu_invalid; menu_pause ;;
    esac
  done
}
