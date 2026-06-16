#!/usr/bin/env bash

provider_protocol_matrix_show_enabled() {
  local engine="$1" protocols_csv="$2" warp_mode="$3"
  local runtime_outbound_mode="$4" runtime_proxy_port="$5"
  local protocols=() protocol idx=0
  local base_port ports_csv p outbound_desc tls reality multi warp share cap
  protocols_to_array "$protocols_csv" protocols
  (( ${#protocols[@]} > 0 )) || { log_info "$(msg "无已启用协议" "No enabled protocols")"; return 0; }

  local warp_active="false" default_outbound_mode="direct"
  protocol_matrix_warp_active "$engine" "$warp_mode" && warp_active="true"
  [[ "$runtime_outbound_mode" != "direct" ]] && default_outbound_mode="proxy"
  [[ "$warp_active" == "true" && "$runtime_outbound_mode" == "direct" ]] && default_outbound_mode="warp"
  log_info "$(msg "运行态特性: WARP=${warp_mode} (active=${warp_active})" "Runtime feature state: WARP=${warp_mode} (active=${warp_active})")"
  printf '%-4s %-18s %-8s %-8s %-16s %-4s %-8s %-10s %-12s %-8s
'     "#" "$(msg "协议" "Protocol")" "$(msg "类型" "Type")" "$(msg "端口" "Port")" "Outbound" "TLS" "Reality" "MultiPort" "WARP" "Share"

  for protocol in "${protocols[@]}"; do
    engine_supports_protocol "$engine" "$protocol" || continue
    base_port="$(resolve_protocol_port_for_engine "$engine" "$protocol")"
    ports_csv="$base_port"
    if declare -F multi_ports_store_ports_for_protocol >/dev/null 2>&1; then
      while IFS= read -r p; do
        [[ -n "$p" ]] || continue
        [[ ",$ports_csv," == *",$p,"* ]] || ports_csv+=",$p"
      done < <(multi_ports_store_ports_for_protocol "$protocol")
    fi
    cap="$(protocol_capability "$protocol")"
    tls="$(echo "$cap" | awk -F';' '{print $1}' | cut -d= -f2)"
    reality="$(echo "$cap" | awk -F';' '{print $2}' | cut -d= -f2)"
    multi="$(echo "$cap" | awk -F';' '{print $3}' | cut -d= -f2)"
    warp="$(echo "$cap" | awk -F';' '{print $4}' | cut -d= -f2)"
    share="$(echo "$cap" | awk -F';' '{print $5}' | cut -d= -f2)"
    IFS=',' read -r -a _ports <<< "$ports_csv"
    for p in "${_ports[@]}"; do
      [[ -n "$p" ]] || continue
      idx=$((idx + 1))
      outbound_desc="$default_outbound_mode"
      [[ "$default_outbound_mode" == "proxy" && -n "$runtime_proxy_port" ]] && outbound_desc="proxy:${runtime_proxy_port}"
      if [[ "$p" == "$base_port" ]]; then
        printf '%-4s %-18s %-8s %-8s %-16s %-4s %-8s %-10s %-12s %-8s
'           "$idx" "$protocol" main "$p" "$outbound_desc" "$tls" "$reality" "$multi" "$warp" "$share"
      else
        printf '%-4s %-18s %-8s %-8s %-16s %-4s %-8s %-10s %-12s %-8s
'           "$idx" "$protocol" mport "$p" "$outbound_desc" "" "" "" "" ""
      fi
    done
  done
}
