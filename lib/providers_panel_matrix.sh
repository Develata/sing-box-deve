#!/usr/bin/env bash

protocol_matrix_warp_active() {
  local engine="$1" mode="$2"
  if [[ "$engine" == "sing-box" ]]; then
    warp_mode_targets_singbox "$mode"
  else
    warp_mode_targets_xray "$mode"
  fi
}

provider_protocol_matrix_show() {
  local mode="${1:-all}" runtime_engine="sing-box" runtime_protocols="" runtime_warp_mode="off"
  local runtime_outbound_mode="direct" runtime_proxy_port=""

  if [[ -f "${SBD_CONFIG_DIR}/runtime.env" ]]; then
    sbd_load_runtime_env "${SBD_CONFIG_DIR}/runtime.env"
    runtime_engine="${engine:-sing-box}"
    runtime_protocols="${protocols:-}"
    runtime_warp_mode="${warp_mode:-off}"
    runtime_outbound_mode="${outbound_proxy_mode:-direct}"
    runtime_proxy_port="${outbound_proxy_port:-}"
  fi

  if [[ "$mode" == "enabled" ]]; then
    provider_protocol_matrix_show_enabled       "$runtime_engine"       "$runtime_protocols"       "$runtime_warp_mode"       "$runtime_outbound_mode"       "$runtime_proxy_port"
    return 0
  fi

  log_info "$(msg "协议能力矩阵（engine=${runtime_engine}）" "Protocol capability matrix (engine=${runtime_engine})")"
  printf '%-18s %-10s %-4s %-8s %-10s %-12s %-8s
'     "$(msg "协议" "Protocol")"     "$(msg "内核支持" "Supported")"     "TLS"     "Reality"     "$(msg "多端口" "MultiPort")"     "$(msg "WARP出站" "WARP Egress")"     "$(msg "订阅" "Share")"

  local row protocol support caps tls reality multi warp share
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    protocol="${row%%|*}"
    support="${row#*|}"; support="${support%%|*}"
    caps="${row##*|}"
    tls="$(echo "$caps" | awk -F';' '{print $1}' | cut -d= -f2)"
    reality="$(echo "$caps" | awk -F';' '{print $2}' | cut -d= -f2)"
    multi="$(echo "$caps" | awk -F';' '{print $3}' | cut -d= -f2)"
    warp="$(echo "$caps" | awk -F';' '{print $4}' | cut -d= -f2)"
    share="$(echo "$caps" | awk -F';' '{print $5}' | cut -d= -f2)"

    printf '%-18s %-10s %-4s %-8s %-10s %-12s %-8s
'       "$protocol" "$support" "$tls" "$reality" "$multi" "$warp" "$share"
  done < <(protocol_matrix_rows "$runtime_engine" true)
}
