#!/usr/bin/env bash

provider_set_egress() {
  ensure_root
  local mode="$1" host="$2" port="$3" user="$4" pass="$5"
  case "$mode" in
    direct|socks|http|https) ;;
    *) die "Unsupported egress mode: $mode" ;;
  esac
  if [[ "$mode" != "direct" ]]; then
    [[ -n "$host" && -n "$port" ]] || die "host and port are required when mode != direct"
    [[ "$port" =~ ^[0-9]+$ ]] || die "egress port must be numeric"
  fi

  provider_cfg_load_runtime_exports
  local runtime_provider="${provider:-vps}" runtime_profile="${profile:-lite}"
  local runtime_engine="${engine:-sing-box}" runtime_protocols="${protocols:-vless-reality}"
  export OUTBOUND_PROXY_MODE="$mode"
  export OUTBOUND_PROXY_HOST="$host"
  export OUTBOUND_PROXY_PORT="$port"
  export OUTBOUND_PROXY_USER="$user"
  export OUTBOUND_PROXY_PASS="$pass"

  validate_feature_modes
  case "$runtime_engine" in
    sing-box) build_sing_box_config "$runtime_protocols" && validate_generated_config "sing-box" "true" ;;
    xray) build_xray_config "$runtime_protocols" && validate_generated_config "xray" "true" ;;
  esac
  persist_runtime_state "$runtime_provider" "$runtime_profile" "$runtime_engine" "$runtime_protocols"
  provider_restart core
  log_success "$(msg "出站模式已更新: ${mode}" "Egress mode updated: ${mode}")"
}

provider_set_route() {
  ensure_root
  local mode="$1"
  case "$mode" in
    direct|global-proxy|cn-direct|cn-proxy) ;;
    *) die "Unsupported route mode: $mode" ;;
  esac

  provider_cfg_load_runtime_exports
  local runtime_provider="${provider:-vps}" runtime_profile="${profile:-lite}"
  local runtime_engine="${engine:-sing-box}" runtime_protocols="${protocols:-vless-reality}"
  export ROUTE_MODE="$mode"

  validate_feature_modes
  case "$runtime_engine" in
    sing-box) build_sing_box_config "$runtime_protocols" && validate_generated_config "sing-box" "true" ;;
    xray) build_xray_config "$runtime_protocols" && validate_generated_config "xray" "true" ;;
  esac
  persist_runtime_state "$runtime_provider" "$runtime_profile" "$runtime_engine" "$runtime_protocols"
  provider_restart core
  log_success "$(msg "分流路由模式已更新: ${mode}" "Route mode updated: ${mode}")"
}

provider_set_share_endpoints() {
  ensure_root
  local kind="$1" endpoints="$2"
  [[ "$endpoints" == *:* ]] || die "Endpoints must be host:port[,host:port...]"

  provider_cfg_load_runtime_exports
  local runtime_provider="${provider:-vps}" runtime_profile="${profile:-lite}"
  local runtime_engine="${engine:-sing-box}" runtime_protocols="${protocols:-vless-reality}"

  case "$kind" in
    direct) export DIRECT_SHARE_ENDPOINTS="$endpoints" ;;
    proxy) export PROXY_SHARE_ENDPOINTS="$endpoints" ;;
    warp) export WARP_SHARE_ENDPOINTS="$endpoints" ;;
    *) die "Unsupported share endpoint kind: $kind" ;;
  esac

  write_nodes_output "$runtime_engine" "$runtime_protocols"
  persist_runtime_state "$runtime_provider" "$runtime_profile" "$runtime_engine" "$runtime_protocols"
  log_success "$(msg "分享出口已更新(${kind}): ${endpoints}" "Share endpoints updated for ${kind}: ${endpoints}")"
}
