#!/usr/bin/env bash

menu_cfg_collect_change() {
  MENU_CFG_ACTION=""
  MENU_CFG_ARG1=""
  MENU_CFG_ARG2=""
  MENU_CFG_ARG3=""
  MENU_CFG_ARG4=""

  echo "1) $(msg "轮换身份标识（UUID 与 short-id）" "Rotate identity (UUID + short-id)")"
  echo "2) $(msg "切换 Argo 模式（off/temp/fixed）" "Switch Argo mode (off/temp/fixed)")"
  echo "3) $(msg "设置 IP 优先级（auto/v4/v6）" "Set IP preference (auto/v4/v6)")"
  echo "4) $(msg "设置 CDN 主机模板（domain）" "Set CDN host template (domain)")"
  echo "5) $(msg "设置三通道域名分流（直连/代理/屏蔽）" "Set domain split (direct/proxy/block)")"
  echo "6) $(msg "切换 TLS 证书策略（自签/ACME/自动签发）" "Switch TLS cert strategy (self-signed/ACME/auto)")"
  echo "7) $(msg "按当前状态重建配置与节点" "Rebuild config and nodes from runtime state")"
  read -r -p "$(msg "请选择配置动作编号" "Select cfg action id"): " a
  case "${a:-0}" in
    1)
      MENU_CFG_ACTION="rotate-id"
      ;;
    2)
      MENU_CFG_ACTION="argo"
      read -r -p "$(msg "Argo 模式[off/temp/fixed]" "argo mode[off/temp/fixed]"): " MENU_CFG_ARG1
      read -r -p "$(msg "token(可选)" "token(optional)"): " MENU_CFG_ARG2
      read -r -p "$(msg "domain(可选)" "domain(optional)"): " MENU_CFG_ARG3
      ;;
    3)
      MENU_CFG_ACTION="ip-pref"
      read -r -p "$(msg "IP 优先级[auto/v4/v6]" "ip preference[auto/v4/v6]"): " MENU_CFG_ARG1
      ;;
    4)
      MENU_CFG_ACTION="cdn-host"
      read -r -p "$(msg "CDN 主机名" "cdn host"): " MENU_CFG_ARG1
      ;;
    5)
      MENU_CFG_ACTION="domain-split"
      read -r -p "$(msg "直连域名(csv)" "direct domains(csv)"): " MENU_CFG_ARG1
      read -r -p "$(msg "代理域名(csv)" "proxy domains(csv)"): " MENU_CFG_ARG2
      read -r -p "$(msg "屏蔽域名(csv)" "block domains(csv)"): " MENU_CFG_ARG3
      ;;
    6)
      MENU_CFG_ACTION="tls"
      read -r -p "$(msg "TLS 模式[self-signed/acme/acme-auto]" "tls mode[self-signed/acme/acme-auto]"): " MENU_CFG_ARG1
      if [[ "$MENU_CFG_ARG1" == "acme" ]]; then
        read -r -p "$(msg "acme 证书路径" "acme cert path"): " MENU_CFG_ARG2
        read -r -p "$(msg "acme 私钥路径" "acme key path"): " MENU_CFG_ARG3
      elif [[ "$MENU_CFG_ARG1" == "acme-auto" ]]; then
        read -r -p "$(msg "签发域名" "domain for cert"): " MENU_CFG_ARG2
        read -r -p "$(msg "签发邮箱" "email for cert"): " MENU_CFG_ARG3
        read -r -p "$(msg "DNS Provider(泛域名可选，如 dns_cf)" "DNS provider(optional for wildcard, e.g. dns_cf)"): " MENU_CFG_ARG4
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
    echo "1) $(msg "预览配置变更（cfg preview <action>）" "Preview config change (cfg preview <action>)")"
    echo "2) $(msg "应用配置变更并自动快照（cfg apply <action>）" "Apply change with snapshot (cfg apply <action>)")"
    echo "3) $(msg "按快照回滚配置（cfg rollback ...）" "Rollback by snapshot (cfg rollback ...)")"
    echo "4) $(msg "查看配置快照列表（cfg snapshots list）" "List config snapshots (cfg snapshots list)")"
    echo "5) $(msg "清理旧快照（cfg snapshots prune）" "Prune old snapshots (cfg snapshots prune)")"
    echo "6) $(msg "查看三通道分流规则（split3 show）" "Show split3 rules (split3 show)")"
    echo "7) $(msg "设置三通道分流规则（split3 set）" "Set split3 rules (split3 set)")"
    echo "8) $(msg "多端口跳跃复用管理（支持多个主端口）" "Jump-port management (multi target)")"
    printf '%s\n' "$(msg "提示：协议增删请使用主菜单 3) 协议管理" "Tip: Use main menu 3) Protocol Management for protocol add/remove")"
    echo "0) $(msg "返回上级" "Back")"
    read -r -p "$(msg "请选择" "Select"): " c
    case "${c:-0}" in
      2)
        if menu_cfg_collect_change; then
          provider_cfg_command apply "$MENU_CFG_ACTION" "$MENU_CFG_ARG1" "$MENU_CFG_ARG2" "$MENU_CFG_ARG3" "$MENU_CFG_ARG4"
        else
          menu_invalid
        fi
        menu_pause
        ;;
      1)
        if menu_cfg_collect_change; then
          provider_cfg_command preview "$MENU_CFG_ACTION" "$MENU_CFG_ARG1" "$MENU_CFG_ARG2" "$MENU_CFG_ARG3" "$MENU_CFG_ARG4"
        else
          menu_invalid
        fi
        menu_pause
        ;;
      3)
        read -r -p "$(msg "快照 ID(默认 latest)" "snapshot id(default latest)"): " sid
        provider_cfg_command rollback "${sid:-latest}"
        menu_pause
        ;;
      4) provider_cfg_command snapshots list; menu_pause ;;
      5)
        read -r -p "$(msg "保留数量(默认 10)" "keep count(default 10)"): " keep
        provider_cfg_command snapshots prune "${keep:-10}"
        menu_pause
        ;;
      6) provider_split3_show; menu_pause ;;
      7)
        read -r -p "$(msg "split3 直连(csv)" "split3 direct(csv)"): " sd
        read -r -p "$(msg "split3 代理(csv)" "split3 proxy(csv)"): " sp
        read -r -p "$(msg "split3 屏蔽(csv)" "split3 block(csv)"): " sb
        provider_split3_set "$sd" "$sp" "$sb"
        menu_pause
        ;;
      8)
        read -r -p "$(msg "jump 动作[set/clear/replay]" "jump action[set/clear/replay]"): " ja
        if [[ "$ja" == "set" ]]; then
          read -r -p "$(msg "协议" "protocol"): " jp
          read -r -p "$(msg "主端口" "main port"): " jm
          read -r -p "$(msg "附加端口(csv)" "extra ports(csv)"): " je
          provider_jump_set "$jp" "$jm" "$je"
        elif [[ "$ja" == "replay" ]]; then
          provider_jump_replay
        else
          read -r -p "$(msg "仅清理某主端口? 输入 protocol main_port，留空则全清" "Clear one target? input protocol main_port, empty=clear all"): " jp jm
          provider_jump_clear "${jp:-}" "${jm:-}"
        fi
        menu_pause
        ;;
      0) return 0 ;;
      *) menu_invalid; menu_pause ;;
    esac
  done
}
