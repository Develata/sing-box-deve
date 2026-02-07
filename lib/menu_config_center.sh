#!/usr/bin/env bash

menu_cfg_collect_change() {
  MENU_CFG_ACTION=""
  MENU_CFG_ARG1=""
  MENU_CFG_ARG2=""
  MENU_CFG_ARG3=""

  echo "1) rotate-id"
  echo "2) argo off/temp/fixed"
  echo "3) ip-pref auto/v4/v6"
  echo "4) cdn-host <domain>"
  echo "5) domain-split direct/proxy/block"
  echo "6) tls self-signed/acme"
  echo "7) rebuild"
  read -r -p "cfg action: " a
  case "${a:-0}" in
    1)
      MENU_CFG_ACTION="rotate-id"
      ;;
    2)
      MENU_CFG_ACTION="argo"
      read -r -p "argo mode[off/temp/fixed]: " MENU_CFG_ARG1
      read -r -p "token(optional): " MENU_CFG_ARG2
      read -r -p "domain(optional): " MENU_CFG_ARG3
      ;;
    3)
      MENU_CFG_ACTION="ip-pref"
      read -r -p "ip preference[auto/v4/v6]: " MENU_CFG_ARG1
      ;;
    4)
      MENU_CFG_ACTION="cdn-host"
      read -r -p "cdn host: " MENU_CFG_ARG1
      ;;
    5)
      MENU_CFG_ACTION="domain-split"
      read -r -p "direct domains(csv): " MENU_CFG_ARG1
      read -r -p "proxy domains(csv): " MENU_CFG_ARG2
      read -r -p "block domains(csv): " MENU_CFG_ARG3
      ;;
    6)
      MENU_CFG_ACTION="tls"
      read -r -p "tls mode[self-signed/acme]: " MENU_CFG_ARG1
      if [[ "$MENU_CFG_ARG1" == "acme" ]]; then
        read -r -p "acme cert path: " MENU_CFG_ARG2
        read -r -p "acme key path: " MENU_CFG_ARG3
      fi
      ;;
    7)
      MENU_CFG_ACTION="rebuild"
      ;;
    *)
      return 1
      ;;
  esac
  return 0
}

menu_config_center() {
  while true; do
    menu_status_header
    menu_title "$(msg "[配置变更中心]" "[Config Center]")"
    echo "1) cfg preview <action>"
    echo "2) cfg apply <action>"
    echo "3) cfg rollback [latest|snapshot-id]"
    echo "4) cfg snapshots list"
    echo "5) cfg snapshots prune [keep]"
    echo "6) split3 show"
    echo "7) split3 set"
    echo "8) jump set/clear/replay"
    echo "0) $(msg "返回上级" "Back")"
    read -r -p "$(msg "请选择" "Select"): " c
    case "${c:-0}" in
      2)
        if menu_cfg_collect_change; then
          provider_cfg_command apply "$MENU_CFG_ACTION" "$MENU_CFG_ARG1" "$MENU_CFG_ARG2" "$MENU_CFG_ARG3"
        else
          menu_invalid
        fi
        menu_pause
        ;;
      1)
        if menu_cfg_collect_change; then
          provider_cfg_command preview "$MENU_CFG_ACTION" "$MENU_CFG_ARG1" "$MENU_CFG_ARG2" "$MENU_CFG_ARG3"
        else
          menu_invalid
        fi
        menu_pause
        ;;
      3)
        read -r -p "snapshot id(default latest): " sid
        provider_cfg_command rollback "${sid:-latest}"
        menu_pause
        ;;
      4) provider_cfg_command snapshots list; menu_pause ;;
      5)
        read -r -p "keep count(default 10): " keep
        provider_cfg_command snapshots prune "${keep:-10}"
        menu_pause
        ;;
      6) provider_split3_show; menu_pause ;;
      7)
        read -r -p "split3 direct(csv): " sd
        read -r -p "split3 proxy(csv): " sp
        read -r -p "split3 block(csv): " sb
        provider_split3_set "$sd" "$sp" "$sb"
        menu_pause
        ;;
      8)
        read -r -p "jump action[set/clear/replay]: " ja
        if [[ "$ja" == "set" ]]; then
          read -r -p "protocol: " jp
          read -r -p "main port: " jm
          read -r -p "extra ports(csv): " je
          provider_jump_set "$jp" "$jm" "$je"
        elif [[ "$ja" == "replay" ]]; then
          provider_jump_replay
        else
          provider_jump_clear
        fi
        menu_pause
        ;;
      0) return 0 ;;
      *) menu_invalid; menu_pause ;;
    esac
  done
}
