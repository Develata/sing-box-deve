#!/usr/bin/env bash

provider_protocol_matrix_show_enabled() {
  local runtime_engine="$1" runtime_protocols="$2" runtime_warp_mode="$3"
  local runtime_port_egress_map="$4" runtime_outbound_mode="$5" runtime_proxy_port="$6"
  local runtime_psiphon_enable="$7" runtime_psiphon_mode="$8"
  local warp_active="no"
  local protocols=() protocol caps tls reality multi warp share
  local base_port ports_csv jump_csv outbound_desc idx=0 p default_outbound_mode

  protocols_to_array "$runtime_protocols" protocols
  if [[ "${#protocols[@]}" -eq 0 ]]; then
    log_warn "$(msg "未检测到已启用协议" "No enabled protocols detected")"
    return 0
  fi

  if protocol_matrix_warp_active "$runtime_engine" "$runtime_warp_mode"; then
    warp_active="yes"
  fi

  runtime_port_egress_map="$(normalize_port_egress_map "$runtime_port_egress_map")"
  default_outbound_mode="$(protocol_matrix_default_outbound_mode \
    "$runtime_engine" "$runtime_protocols" "$runtime_warp_mode" "$runtime_outbound_mode" \
    "$runtime_psiphon_enable" "$runtime_psiphon_mode")"
  log_info "$(msg "运行态特性: WARP=${runtime_warp_mode} (active=${warp_active}), 端口出站映射=${runtime_port_egress_map:-none}" "Runtime feature state: WARP=${runtime_warp_mode} (active=${warp_active}), port-egress-map=${runtime_port_egress_map:-none}")"
  log_info "$(msg "已启用协议及端口能力矩阵（engine=${runtime_engine}）" "Enabled protocol+port capability matrix (engine=${runtime_engine})")"

  printf '%-4s %-16s %-8s %-8s %-14s %-14s %-4s %-8s %-6s %-8s %-8s\n' \
    "$(msg "序号" "No")" \
    "$(msg "协议" "Protocol")" \
    "$(msg "端口类型" "PortType")" \
    "$(msg "入站" "Inbound")" \
    "$(msg "出站" "Outbound")" \
    "$(msg "Jump附加端口" "Jump Extra")" \
    "TLS" \
    "Reality" \
    "$(msg "多端口" "Multi")" \
    "$(msg "WARP出站" "WARP")" \
    "$(msg "订阅" "Share")"

  for protocol in "${protocols[@]}"; do
    caps="$(protocol_capability "$protocol")"
    tls="$(protocol_matrix_cap_get "$caps" "tls")"
    reality="$(protocol_matrix_cap_get "$caps" "reality")"
    multi="$(protocol_matrix_cap_get "$caps" "multi-port")"
    warp="$(protocol_matrix_cap_get "$caps" "warp-egress")"
    share="$(protocol_matrix_cap_get "$caps" "share")"
    if [[ "$warp" == "yes" || "$warp" == "self" ]]; then
      warp="$warp_active"
    fi

    if ! protocol_needs_local_listener "$protocol"; then
      idx=$((idx + 1))
      printf '%-4s %-16s %-8s %-8s %-14s %-14s %-4s %-8s %-6s %-8s %-8s\n' \
        "${idx}" "$protocol" "-" "-" "-" "-" "$tls" "$reality" "$multi" "$warp" "$share"
      continue
    fi

    base_port="$(resolve_protocol_port_for_engine "$runtime_engine" "$protocol" 2>/dev/null || true)"
    ports_csv="$(protocol_matrix_enabled_ports_csv "$protocol" "$base_port")"
    if [[ -z "$ports_csv" ]]; then
      idx=$((idx + 1))
      printf '%-4s %-16s %-8s %-8s %-14s %-14s %-4s %-8s %-6s %-8s %-8s\n' \
        "${idx}" "$protocol" "-" "-" "-" "-" "$tls" "$reality" "$multi" "$warp" "$share"
      continue
    fi
    IFS=',' read -r -a _ports <<< "$ports_csv"
    local _first_port_in_proto=true
    for p in "${_ports[@]}"; do
      jump_csv="$(protocol_matrix_enabled_jump_csv "$protocol" "$p")"
      [[ -n "$jump_csv" ]] || jump_csv="-"
      outbound_desc="$(protocol_matrix_enabled_outbound_desc "$p" "$runtime_port_egress_map" "$default_outbound_mode" "$runtime_proxy_port" "$warp_active")"
      idx=$((idx + 1))
      if [[ "$_first_port_in_proto" == "true" ]]; then
        printf '%-4s %-16s %-8s %-8s %-14s %-14s %-4s %-8s %-6s %-8s %-8s\n' \
          "${idx}" "$protocol" "$([[ "$p" == "$base_port" ]] && echo main || echo mport)" "$p" "$outbound_desc" "$jump_csv" "$tls" "$reality" "$multi" "$warp" "$share"
        _first_port_in_proto=false
      else
        printf '%-4s %-16s %-8s %-8s %-14s %-14s %-4s %-8s %-6s %-8s %-8s\n' \
          "${idx}" "" "$([[ "$p" == "$base_port" ]] && echo main || echo mport)" "$p" "$outbound_desc" "$jump_csv" "" "" "" "" ""
      fi
    done
  done
}
