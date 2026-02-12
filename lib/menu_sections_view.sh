#!/usr/bin/env bash

menu_view() {
  while true; do
    menu_status_header
    menu_title "$(msg "[状态与节点查看]" "[Status & Nodes]")"
    echo "1) $(msg "查看完整状态面板（panel --full）" "Full status panel (panel --full)")"
    echo "2) $(msg "查看全量运行信息（list --all）" "All runtime info (list --all)")"
    echo "3) $(msg "仅查看节点链接（list --nodes）" "Nodes only (list --nodes)")"
    echo "0) $(msg "返回上级" "Back")"
    read -r -p "$(msg "请选择" "Select"): " c
    case "${c:-0}" in
      1) provider_panel full; menu_pause ;;
      2) provider_list all; menu_pause ;;
      3) provider_list nodes; menu_pause ;;
      0) return 0 ;;
      *) menu_invalid; menu_pause ;;
    esac
  done
}

menu_protocol_runtime_summary() {
  local runtime_file runtime_engine runtime_profile runtime_protocols
  runtime_file="$(provider_cfg_runtime_file)"
  if [[ ! -f "$runtime_file" ]]; then
    log_warn "$(msg "未找到运行时状态，请先安装或初始化" "Runtime state not found, install/init first")"
    return 0
  fi

  runtime_engine="$(grep -E '^engine=' "$runtime_file" | head -n1 | cut -d= -f2-)"
  runtime_profile="$(grep -E '^profile=' "$runtime_file" | head -n1 | cut -d= -f2-)"
  runtime_protocols="$(grep -E '^protocols=' "$runtime_file" | head -n1 | cut -d= -f2-)"

  log_info "$(msg "当前运行时: engine=${runtime_engine:-n/a} profile=${runtime_profile:-n/a}" "Runtime: engine=${runtime_engine:-n/a} profile=${runtime_profile:-n/a}")"
  log_info "$(msg "已启用协议: ${runtime_protocols:-n/a}" "Enabled protocols: ${runtime_protocols:-n/a}")"
  echo
}

menu_protocol() {
  while true; do
    menu_status_header
    menu_title "$(msg "[协议管理]" "[Protocol Management]")"
    menu_protocol_runtime_summary
    echo "1) $(msg "查看协议能力矩阵（protocol matrix）" "Protocol capability matrix (protocol matrix)")"
    echo "2) $(msg "查看已启用协议及端口能力矩阵（protocol matrix --enabled）" "Enabled protocol+port capability matrix (protocol matrix --enabled)")"
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
        local add_args=()
        add_args=("protocol-add" "$ap" "$am")
        if [[ "$am" == "manual" ]]; then
          read -r -p "$(msg "手动端口映射(proto:port,proto:port...)" "manual port map(proto:port,proto:port...)"): " amap
          add_args+=("$amap")
        fi
        provider_cfg_command preview "${add_args[@]}"
        if prompt_yes_no "$(msg "确认应用该协议新增变更？" "Apply this protocol-add change?")" "Y"; then
          provider_cfg_command apply "${add_args[@]}"
        else
          log_warn "$(msg "已取消应用" "Apply cancelled")"
        fi
        menu_pause
        ;;
      4)
        read -r -p "$(msg "移除协议列表(csv)" "protocols to remove(csv)"): " rp
        provider_cfg_command preview protocol-remove "$rp"
        if prompt_yes_no "$(msg "确认应用该协议移除变更？" "Apply this protocol-remove change?")" "N"; then
          provider_cfg_command apply protocol-remove "$rp"
        else
          log_warn "$(msg "已取消应用" "Apply cancelled")"
        fi
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
    echo "3) $(msg "查看多真实端口（mport list）" "List multi real-ports (mport list)")"
    echo "4) $(msg "新增多真实端口（mport add）" "Add multi real-port (mport add)")"
    echo "5) $(msg "移除多真实端口（mport remove）" "Remove multi real-port (mport remove)")"
    echo "6) $(msg "清空多真实端口（mport clear）" "Clear multi real-ports (mport clear)")"
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
      3) provider_multi_ports_list; menu_pause ;;
      4)
        read -r -p "$(msg "输入协议名" "Protocol name"): " p
        read -r -p "$(msg "输入新增监听端口(1-65535)" "New listener port(1-65535)"): " port
        provider_multi_ports_add "$p" "$port"
        menu_pause
        ;;
      5)
        read -r -p "$(msg "输入协议名" "Protocol name"): " p
        read -r -p "$(msg "输入移除监听端口(1-65535)" "Remove listener port(1-65535)"): " port
        provider_multi_ports_remove "$p" "$port"
        menu_pause
        ;;
      6)
        if prompt_yes_no "$(msg "确认清空所有多真实端口？" "Clear all multi real-ports?")" "N"; then
          provider_multi_ports_clear
        fi
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
            read -r -p "$(msg "端口映射(port:direct|proxy|warp|psiphon,...) " "map(port:direct|proxy|warp|psiphon,...) "): " pm
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
