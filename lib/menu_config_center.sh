#!/usr/bin/env bash

menu_cfg_collect_change() {
  MENU_CFG_ACTION=""
  MENU_CFG_ARG1=""
  MENU_CFG_ARG2=""
  MENU_CFG_ARG3=""
  MENU_CFG_ARG4=""

  echo "1) rotate-id"
  echo "2) argo off/temp/fixed"
  echo "3) ip-pref auto/v4/v6"
  echo "4) cdn-host <domain>"
  echo "5) domain-split direct/proxy/block"
  echo "6) tls self-signed/acme/acme-auto"
  echo "7) protocol-add <proto_csv> [random|manual]"
  echo "8) protocol-remove <proto_csv>"
  echo "9) rebuild"
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
      MENU_CFG_ACTION="protocol-add"
      read -r -p "$(msg "新增协议列表(csv)" "protocols to add(csv)"): " MENU_CFG_ARG1
      read -r -p "$(msg "端口模式[random/manual] (默认 random)" "port mode[random/manual] (default random)"): " MENU_CFG_ARG2
      MENU_CFG_ARG2="${MENU_CFG_ARG2:-random}"
      if [[ "$MENU_CFG_ARG2" == "manual" ]]; then
        read -r -p "$(msg "手动端口映射(proto:port,proto:port...)" "manual port map(proto:port,proto:port...)"): " MENU_CFG_ARG3
      fi
      ;;
    8)
      MENU_CFG_ACTION="protocol-remove"
      read -r -p "$(msg "移除协议列表(csv)" "protocols to remove(csv)"): " MENU_CFG_ARG1
      ;;
    9)
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
    echo "8) $(msg "新增协议（cfg protocol-add ...）" "Add protocol (cfg protocol-add ...)")"
    echo "9) $(msg "移除协议（cfg protocol-remove ...）" "Remove protocol (cfg protocol-remove ...)")"
    echo "10) $(msg "多端口跳跃复用管理（jump set/clear/replay）" "Jump-port management (jump set/clear/replay)")"
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
        read -r -p "$(msg "新增协议列表(csv)" "protocols to add(csv)"): " ap
        read -r -p "$(msg "端口模式[random/manual] (默认 random)" "port mode[random/manual] (default random)"): " am
        am="${am:-random}"
        if [[ "$am" == "manual" ]]; then
          read -r -p "$(msg "手动端口映射(proto:port,proto:port...)" "manual port map(proto:port,proto:port...)"): " amap
          provider_cfg_command protocol-add "$ap" "$am" "$amap"
        else
          provider_cfg_command protocol-add "$ap" "$am"
        fi
        menu_pause
        ;;
      9)
        read -r -p "$(msg "移除协议列表(csv)" "protocols to remove(csv)"): " rp
        provider_cfg_command protocol-remove "$rp"
        menu_pause
        ;;
      10)
        read -r -p "$(msg "jump 动作[set/clear/replay]" "jump action[set/clear/replay]"): " ja
        if [[ "$ja" == "set" ]]; then
          read -r -p "$(msg "协议" "protocol"): " jp
          read -r -p "$(msg "主端口" "main port"): " jm
          read -r -p "$(msg "附加端口(csv)" "extra ports(csv)"): " je
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
