#!/usr/bin/env bash

provider_port_egress_inbound_ports_csv() {
  local engine="$1" cfg query
  case "$engine" in
    sing-box)
      cfg="${SBD_CONFIG_DIR}/config.json"
      query='.inbounds[] | (.listen_port // .port // empty)'
      ;;
    xray)
      cfg="${SBD_CONFIG_DIR}/xray-config.json"
      query='.inbounds[] | (.port // empty)'
      ;;
    *)
      echo ""
      return 0
      ;;
  esac
  [[ -f "$cfg" ]] || {
    echo ""
    return 0
  }
  jq -r "$query" "$cfg" 2>/dev/null | awk '/^[0-9]+$/{print $1}' | sort -n | uniq | paste -sd, -
}

provider_port_egress_outbounds_csv() {
  local engine="$1" cfg
  case "$engine" in
    sing-box) cfg="${SBD_CONFIG_DIR}/config.json" ;;
    xray) cfg="${SBD_CONFIG_DIR}/xray-config.json" ;;
    *)
      echo ""
      return 0
      ;;
  esac
  [[ -f "$cfg" ]] || {
    echo ""
    return 0
  }
  jq -r '.outbounds[] | .tag // empty' "$cfg" 2>/dev/null | awk 'NF{print $1}' | sort -u | paste -sd, -
}

provider_port_egress_validate_map() {
  local normalized="$1" engine="$2"
  [[ -n "$normalized" ]] || return 0

  local ports_csv outbounds_csv item port mode target
  ports_csv="$(provider_port_egress_inbound_ports_csv "$engine")"
  outbounds_csv="$(provider_port_egress_outbounds_csv "$engine")"
  [[ -n "$ports_csv" ]] || die "No inbound ports detected for engine=${engine}"

  IFS=',' read -r -a _items <<< "$normalized"
  for item in "${_items[@]}"; do
    port="${item%%:*}"
    mode="${item#*:}"
    if ! csv_has_token "$ports_csv" "$port"; then
      die "PORT_EGRESS_MAP port not found in current inbounds: ${port} (current=${ports_csv})"
    fi
    target="$(port_egress_mode_to_outbound "$mode")" || die "Invalid egress mode in map: ${mode}"
    if ! csv_has_token "$outbounds_csv" "$target"; then
      die "PORT_EGRESS_MAP requires outbound '${target}', but current outbounds are: ${outbounds_csv:-none}"
    fi
  done
}

provider_set_port_egress_info() {
  ensure_root
  [[ -f /etc/sing-box-deve/runtime.env ]] || die "No runtime state found"
  sbd_load_runtime_env /etc/sing-box-deve/runtime.env

  local runtime_engine="${engine:-sing-box}" normalized ports_csv outbounds_csv
  normalized="$(normalize_port_egress_map "${port_egress_map:-}")"
  ports_csv="$(provider_port_egress_inbound_ports_csv "$runtime_engine")"
  outbounds_csv="$(provider_port_egress_outbounds_csv "$runtime_engine")"

  log_info "$(msg "端口出站策略(当前): ${normalized:-<未设置>}" "Port egress map(current): ${normalized:-<empty>}")"
  log_info "$(msg "当前入站端口: ${ports_csv:-<无>}" "Current inbound ports: ${ports_csv:-<none>}")"
  log_info "$(msg "当前可用出站: ${outbounds_csv:-<无>}" "Current available outbounds: ${outbounds_csv:-<none>}")"
  log_info "$(msg "用法: set-port-egress --map <port:direct|proxy|warp|psiphon,...> | --clear" "Usage: set-port-egress --map <port:direct|proxy|warp|psiphon,...> | --clear")"
}

provider_set_port_egress_map() {
  ensure_root
  [[ -f /etc/sing-box-deve/runtime.env ]] || die "No runtime state found"

  local raw_map="$1" normalized
  normalized="$(normalize_port_egress_map "$raw_map")"

  provider_cfg_load_runtime_exports
  provider_port_egress_validate_map "$normalized" "${engine:-sing-box}"

  PORT_EGRESS_MAP="$normalized"
  provider_cfg_rebuild_runtime
  log_success "$(msg "端口出站策略已更新: ${PORT_EGRESS_MAP}" "Port egress map updated: ${PORT_EGRESS_MAP}")"
}

provider_set_port_egress_clear() {
  ensure_root
  [[ -f /etc/sing-box-deve/runtime.env ]] || die "No runtime state found"
  provider_cfg_load_runtime_exports
  PORT_EGRESS_MAP=""
  provider_cfg_rebuild_runtime
  log_success "$(msg "端口出站策略已清空" "Port egress map cleared")"
}
