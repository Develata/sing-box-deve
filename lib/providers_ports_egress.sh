#!/usr/bin/env bash

provider_set_egress() {
  sbd_with_mutation_lock provider_set_egress_unlocked "$@"
}

provider_set_egress_unlocked() {
  ensure_root
  local mode="$1" host="$2" port="$3" user="$4" pass="$5" udp_mode="${6:-proxy}" link="${7:-}"
  case "$mode" in
    direct|socks|http|https) ;;
    *) die "Unsupported egress mode: $mode" ;;
  esac
  case "$udp_mode" in
    proxy|direct|block) ;;
    *) die "Invalid OUTBOUND_PROXY_UDP_MODE: ${udp_mode}" ;;
  esac
  if [[ "$mode" != "direct" && -z "$link" ]]; then
    [[ -n "$host" && -n "$port" ]] || die "host and port are required when mode != direct"
    [[ "$port" =~ ^[0-9]+$ ]] || die "egress port must be numeric"
  fi

  provider_cfg_load_runtime_exports || return 1
  local runtime_provider="${provider:-vps}" runtime_profile="${profile:-lite}"
  local runtime_engine="${engine:-sing-box}" runtime_protocols="${protocols:-vless-reality}"
  export OUTBOUND_PROXY_MODE="$mode"
  export OUTBOUND_PROXY_UDP_MODE="$udp_mode"
  export OUTBOUND_PROXY_HOST="$host"
  export OUTBOUND_PROXY_PORT="$port"
  export OUTBOUND_PROXY_USER="$user"
  export OUTBOUND_PROXY_PASS="$pass"
  export OUTBOUND_PROXY_LINK="$link"

  validate_feature_modes || return 1
  sbd_egress_validate_engine "$runtime_engine" || return 1
  # Invalid links/core combinations are rejected before a service transaction.
  sbd_transaction_run config-change provider_apply_egress "$runtime_provider" "$runtime_profile" "$runtime_engine" "$runtime_protocols"
}

provider_apply_egress() {
  local runtime_provider="$1" runtime_profile="$2" runtime_engine="$3" runtime_protocols="$4"
  provider_prepare_domain_runtime_artifacts "$runtime_protocols" || return 1
  case "$runtime_engine" in
    sing-box) build_sing_box_config "$runtime_protocols" && validate_generated_config "sing-box" "true" || return 1 ;;
    xray) build_xray_config "$runtime_protocols" && validate_generated_config "xray" "true" || return 1 ;;
  esac
  provider_commit_domain_web_front "$runtime_protocols" || return 1
  persist_runtime_state "$runtime_provider" "$runtime_profile" "$runtime_engine" "$runtime_protocols" || return 1
  provider_restart core || return 1
  log_success "$(msg "出站模式已更新: ${OUTBOUND_PROXY_MODE}，UDP=${OUTBOUND_PROXY_UDP_MODE}" "Egress mode updated: ${OUTBOUND_PROXY_MODE}, UDP=${OUTBOUND_PROXY_UDP_MODE}")"
}

provider_set_route() {
  sbd_with_mutation_lock sbd_transaction_run config-change provider_set_route_unlocked "$@"
}

provider_set_route_unlocked() {
  ensure_root
  local mode="$1"
  case "$mode" in
    direct|global-proxy|cn-direct|cn-proxy) ;;
    *) die "Unsupported route mode: $mode" ;;
  esac

  provider_cfg_load_runtime_exports || return 1
  local runtime_provider="${provider:-vps}" runtime_profile="${profile:-lite}"
  local runtime_engine="${engine:-sing-box}" runtime_protocols="${protocols:-vless-reality}"
  export ROUTE_MODE="$mode"

  validate_feature_modes || return 1
  provider_prepare_domain_runtime_artifacts "$runtime_protocols" || return 1
  case "$runtime_engine" in
    sing-box) build_sing_box_config "$runtime_protocols" && validate_generated_config "sing-box" "true" || return 1 ;;
    xray) build_xray_config "$runtime_protocols" && validate_generated_config "xray" "true" || return 1 ;;
  esac
  provider_commit_domain_web_front "$runtime_protocols" || return 1
  persist_runtime_state "$runtime_provider" "$runtime_profile" "$runtime_engine" "$runtime_protocols" || return 1
  provider_restart core || return 1
  log_success "$(msg "分流路由模式已更新: ${mode}" "Route mode updated: ${mode}")"
}
