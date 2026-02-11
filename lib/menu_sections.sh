#!/usr/bin/env bash

menu_view() {
  while true; do
    menu_status_header
    menu_title "$(msg "[状态与节点查看]" "[Status & Nodes]")"
    echo "1) $(msg "查看完整状态面板（panel --full）" "Full status panel (panel --full)")"
    echo "2) $(msg "查看全量运行信息（list --all）" "All runtime info (list --all)")"
    echo "3) $(msg "仅查看节点链接（list --nodes）" "Nodes only (list --nodes)")"
    echo "4) $(msg "查看协议能力矩阵（protocol matrix）" "Protocol capability matrix (protocol matrix)")"
    echo "5) $(msg "仅查看已启用协议能力（protocol matrix --enabled）" "Enabled protocol capability matrix (protocol matrix --enabled)")"
    echo "0) $(msg "返回上级" "Back")"
    read -r -p "$(msg "请选择" "Select"): " c
    case "${c:-0}" in
      1) provider_panel full; menu_pause ;;
      2) provider_list all; menu_pause ;;
      3) provider_list nodes; menu_pause ;;
      4) provider_protocol_matrix_show all; menu_pause ;;
      5) provider_protocol_matrix_show enabled; menu_pause ;;
      0) return 0 ;;
      *) menu_invalid; menu_pause ;;
    esac
  done
}

menu_protocol() {
  while true; do
    menu_status_header
    menu_title "$(msg "[协议管理]" "[Protocol Management]")"
    echo "1) $(msg "查看协议能力矩阵（protocol matrix）" "Protocol capability matrix (protocol matrix)")"
    echo "2) $(msg "查看已启用协议能力（protocol matrix --enabled）" "Enabled protocol capability matrix (protocol matrix --enabled)")"
    echo "3) $(msg "新增协议（cfg protocol-add）" "Add protocol (cfg protocol-add)")"
    echo "4) $(msg "移除协议（cfg protocol-remove）" "Remove protocol (cfg protocol-remove)")"
    echo "0) $(msg "返回上级" "Back")"
    read -r -p "$(msg "请选择" "Select"): " c
    case "${c:-0}" in
      1) provider_protocol_matrix_show all; menu_pause ;;
      2) provider_protocol_matrix_show enabled; menu_pause ;;
      3)
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
      4)
        read -r -p "$(msg "移除协议列表(csv)" "protocols to remove(csv)"): " rp
        provider_cfg_command protocol-remove "$rp"
        menu_pause
        ;;
      0) return 0 ;;
      *) menu_invalid; menu_pause ;;
    esac
  done
}

menu_port() {
  while true; do
    menu_status_header
    menu_title "$(msg "[端口管理]" "[Port Management]")"
    echo "1) $(msg "查看协议端口映射（set-port --list）" "List protocol ports (set-port --list)")"
    echo "2) $(msg "修改指定协议端口（set-port --protocol --port）" "Set protocol port (set-port --protocol --port)")"
    echo "0) $(msg "返回上级" "Back")"
    read -r -p "$(msg "请选择" "Select"): " c
    case "${c:-0}" in
      1) provider_set_port_info; menu_pause ;;
      2)
        read -r -p "$(msg "输入协议名" "Protocol name"): " p
        read -r -p "$(msg "输入新端口(1-65535)" "New port(1-65535)"): " port
        provider_set_port "$p" "$port"
        menu_pause
        ;;
      0) return 0 ;;
      *) menu_invalid; menu_pause ;;
    esac
  done
}

menu_egress() {
  while true; do
    menu_status_header
    menu_title "$(msg "[出站策略管理]" "[Egress Management]")"
    echo "1) $(msg "切换为直连出站（set-egress direct）" "Set direct egress (set-egress direct)")"
    echo "2) $(msg "配置上游代理出站（set-egress socks/http/https）" "Set upstream proxy egress (set-egress socks/http/https)")"
    echo "3) $(msg "设置分流路由模式（set-route ...）" "Set route mode (set-route ...)")"
    echo "4) $(msg "设置分享出口端点（set-share ...）" "Set share endpoints (set-share ...)")"
    echo "5) $(msg "设置按端口出站策略（set-port-egress）" "Set port-based egress policy (set-port-egress)")"
    echo "0) $(msg "返回上级" "Back")"
    read -r -p "$(msg "请选择" "Select"): " c
    case "${c:-0}" in
      1)
        provider_set_egress direct "" "" "" ""
        menu_pause
        ;;
      2)
        read -r -p "$(msg "模式[socks/http/https]" "mode[socks/http/https]"): " m
        read -r -p "$(msg "主机" "host"): " h
        read -r -p "$(msg "端口" "port"): " p
        read -r -p "$(msg "用户(可选)" "user(optional)"): " u
        read -r -p "$(msg "密码(可选)" "pass(optional)"): " pw
        provider_set_egress "$m" "$h" "$p" "$u" "$pw"
        menu_pause
        ;;
      3)
        read -r -p "$(msg "路由模式[direct/global-proxy/cn-direct/cn-proxy]" "route mode[direct/global-proxy/cn-direct/cn-proxy]"): " rm
        provider_set_route "$rm"
        menu_pause
        ;;
      4)
        read -r -p "$(msg "分享类别[direct/proxy/warp]" "share kind[direct/proxy/warp]"): " sk
        read -r -p "$(msg "出口列表(host:port,host:port...)" "endpoints(host:port,host:port...)"): " se
        provider_set_share_endpoints "$sk" "$se"
        menu_pause
        ;;
      5)
        read -r -p "$(msg "动作[list/set/clear]" "action[list/set/clear]"): " pa
        case "${pa:-list}" in
          list)
            provider_set_port_egress_info
            ;;
          set)
            read -r -p "$(msg "端口映射(port:direct|proxy|warp,...) " "map(port:direct|proxy|warp,...) "): " pm
            provider_set_port_egress_map "$pm"
            ;;
          clear)
            provider_set_port_egress_clear
            ;;
          *)
            menu_invalid
            ;;
        esac
        menu_pause
        ;;
      0) return 0 ;;
      *) menu_invalid; menu_pause ;;
    esac
  done
}

menu_service() {
  while true; do
    menu_status_header
    menu_title "$(msg "[服务管理]" "[Service Management]")"
    echo "1) $(msg "重启全部服务（restart --all）" "Restart all services (restart --all)")"
    echo "2) $(msg "仅重启核心服务（restart --core）" "Restart core only (restart --core)")"
    echo "3) $(msg "仅重启 Argo 边车（restart --argo）" "Restart Argo sidecar (restart --argo)")"
    echo "4) $(msg "重建节点文件（regen-nodes）" "Regenerate nodes (regen-nodes)")"
    echo "5) $(msg "查看核心日志（logs --core）" "Show core logs (logs --core)")"
    echo "6) $(msg "查看 Argo 日志（logs --argo）" "Show Argo logs (logs --argo)")"
    echo "0) $(msg "返回上级" "Back")"
    read -r -p "$(msg "请选择" "Select"): " c
    case "${c:-0}" in
      1) provider_restart all; menu_pause ;;
      2) provider_restart core; menu_pause ;;
      3) provider_restart argo; menu_pause ;;
      4) provider_regen_nodes; menu_pause ;;
      5) provider_logs core; menu_pause ;;
      6) provider_logs argo; menu_pause ;;
      0) return 0 ;;
      *) menu_invalid; menu_pause ;;
    esac
  done
}

menu_update() {
  while true; do
    menu_status_header
    menu_title "$(msg "[更新管理]" "[Update Management]")"
    echo "1) $(msg "更新核心内核（update --core）" "Update core engine (update --core)")"
    echo "2) $(msg "更新脚本与模块（update --script）" "Update script/modules (update --script)")"
    echo "3) $(msg "同时更新内核与脚本（update --all）" "Update both core+script (update --all)")"
    echo "4) $(msg "仅主源更新脚本（update --script --source primary）" "Script update by primary source")"
    echo "5) $(msg "仅备源更新脚本（update --script --source backup）" "Script update by backup source")"
    echo "0) $(msg "返回上级" "Back")"
    read -r -p "$(msg "请选择" "Select"): " c
    case "${c:-0}" in
      1) update_command --core --yes; menu_pause ;;
      2) update_command --script --yes; menu_pause ;;
      3) update_command --all --yes; menu_pause ;;
      4) update_command --script --source primary --yes; menu_pause ;;
      5) update_command --script --source backup --yes; menu_pause ;;
      0) return 0 ;;
      *) menu_invalid; menu_pause ;;
    esac
  done
}

menu_firewall() {
  while true; do
    menu_status_header
    menu_title "$(msg "[防火墙管理]" "[Firewall Management]")"
    echo "1) $(msg "查看防火墙托管状态（fw status）" "Show firewall status (fw status)")"
    echo "2) $(msg "回滚到上次防火墙快照（fw rollback）" "Rollback firewall snapshot (fw rollback)")"
    echo "3) $(msg "重放托管防火墙规则（fw replay）" "Replay managed firewall rules (fw replay)")"
    echo "0) $(msg "返回上级" "Back")"
    read -r -p "$(msg "请选择" "Select"): " c
    case "${c:-0}" in
      1) fw_detect_backend; fw_status; menu_pause ;;
      2) fw_detect_backend; fw_rollback; menu_pause ;;
      3) fw_detect_backend; fw_replay; menu_pause ;;
      0) return 0 ;;
      *) menu_invalid; menu_pause ;;
    esac
  done
}

menu_settings() {
  while true; do
    menu_status_header
    menu_title "$(msg "[设置管理]" "[Settings]")"
    echo "1) $(msg "查看当前设置（settings show）" "Show settings (settings show)")"
    echo "2) $(msg "设置界面语言（settings set lang）" "Set language (settings set lang)")"
    echo "3) $(msg "设置自动确认（settings set auto_yes）" "Set auto-yes (settings set auto_yes)")"
    echo "0) $(msg "返回上级" "Back")"
    read -r -p "$(msg "请选择" "Select"): " c
    case "${c:-0}" in
      1) show_settings; menu_pause ;;
      2)
        read -r -p "$(msg "语言[zh/en]" "lang[zh/en]"): " l
        set_setting lang "$l"
        show_settings
        menu_pause
        ;;
      3)
        read -r -p "$(msg "自动确认[true/false]" "auto_yes[true/false]"): " ay
        set_setting auto_yes "$ay"
        show_settings
        menu_pause
        ;;
      0) return 0 ;;
      *) menu_invalid; menu_pause ;;
    esac
  done
}

menu_logs() {
  while true; do
    menu_status_header
    menu_title "$(msg "[日志查看]" "[Logs]")"
    echo "1) $(msg "查看核心服务日志（logs --core）" "Show core logs (logs --core)")"
    echo "2) $(msg "查看 Argo 边车日志（logs --argo）" "Show Argo logs (logs --argo)")"
    echo "0) $(msg "返回上级" "Back")"
    read -r -p "$(msg "请选择" "Select"): " c
    case "${c:-0}" in
      1) provider_logs core; menu_pause ;;
      2) provider_logs argo; menu_pause ;;
      0) return 0 ;;
      *) menu_invalid; menu_pause ;;
    esac
  done
}

menu_uninstall() {
  menu_status_header
  menu_title "$(msg "[卸载管理]" "[Uninstall]")"
  echo "1) $(msg "卸载并保留设置（uninstall --keep-settings）" "Uninstall and keep settings (uninstall --keep-settings)")"
  echo "2) $(msg "完全卸载（uninstall）" "Full uninstall (uninstall)")"
  echo "0) $(msg "返回上级" "Back")"
  read -r -p "$(msg "请选择" "Select"): " c
  case "${c:-0}" in
    1)
      if prompt_yes_no "$(msg "确认卸载并保留 settings?" "Confirm uninstall and keep settings?")" "N"; then
        provider_uninstall true
      fi
      ;;
    2)
      if prompt_yes_no "$(msg "确认完全卸载?" "Confirm full uninstall?")" "N"; then
        provider_uninstall false
      fi
      ;;
    0) return 0 ;;
    *) menu_invalid ;;
  esac
  menu_pause
}
