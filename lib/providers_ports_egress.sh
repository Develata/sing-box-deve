#!/usr/bin/env bash

provider_set_egress() {
  ensure_root
  [[ -f /etc/sing-box-deve/runtime.env ]] || die "No runtime state found"
  local mode="$1" host="$2" port="$3" user="$4" pass="$5"
  case "$mode" in
    direct|socks|http|https) ;;
    *) die "Unsupported egress mode: $mode" ;;
  esac
  if [[ "$mode" != "direct" ]]; then
    [[ -n "$host" && -n "$port" ]] || die "host and port are required when mode != direct"
    [[ "$port" =~ ^[0-9]+$ ]] || die "egress port must be numeric"
  fi

  # shellcheck disable=SC1091
  source /etc/sing-box-deve/runtime.env
  local runtime_provider="${provider:-vps}" runtime_profile="${profile:-lite}"
  local runtime_engine="${engine:-sing-box}" runtime_protocols="${protocols:-vless-reality}"
  export OUTBOUND_PROXY_MODE="$mode"
  export OUTBOUND_PROXY_HOST="$host"
  export OUTBOUND_PROXY_PORT="$port"
  export OUTBOUND_PROXY_USER="$user"
  export OUTBOUND_PROXY_PASS="$pass"
  export DIRECT_SHARE_ENDPOINTS="${direct_share_endpoints:-}"
  export PROXY_SHARE_ENDPOINTS="${proxy_share_endpoints:-}"
  export WARP_SHARE_ENDPOINTS="${warp_share_endpoints:-}"
  export IP_PREFERENCE="${ip_preference:-auto}"
  export CDN_TEMPLATE_HOST="${cdn_template_host:-}"
  export TLS_MODE="${tls_mode:-self-signed}"
  export ACME_CERT_PATH="${acme_cert_path:-}"
  export ACME_KEY_PATH="${acme_key_path:-}"
  export DOMAIN_SPLIT_DIRECT="${domain_split_direct:-}"
  export DOMAIN_SPLIT_PROXY="${domain_split_proxy:-}"
  export DOMAIN_SPLIT_BLOCK="${domain_split_block:-}"
  export PORT_EGRESS_MAP="${port_egress_map:-}"
  export ARGO_MODE="${argo_mode:-off}"
  export PSIPHON_ENABLE="${psiphon_enable:-off}"
  export PSIPHON_MODE="${psiphon_mode:-off}"
  export PSIPHON_REGION="${psiphon_region:-auto}"
  export WARP_MODE="${warp_mode:-off}"
  export ROUTE_MODE="${route_mode:-direct}"
  export ARGO_DOMAIN="${argo_domain:-${ARGO_DOMAIN:-}}"
  export ARGO_TOKEN="${argo_token:-${ARGO_TOKEN:-}}"

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
  [[ -f /etc/sing-box-deve/runtime.env ]] || die "No runtime state found"
  local mode="$1"
  case "$mode" in
    direct|global-proxy|cn-direct|cn-proxy) ;;
    *) die "Unsupported route mode: $mode" ;;
  esac

  # shellcheck disable=SC1091
  source /etc/sing-box-deve/runtime.env
  local runtime_provider="${provider:-vps}" runtime_profile="${profile:-lite}"
  local runtime_engine="${engine:-sing-box}" runtime_protocols="${protocols:-vless-reality}"
  export ARGO_MODE="${argo_mode:-off}"
  export PSIPHON_ENABLE="${psiphon_enable:-off}"
  export PSIPHON_MODE="${psiphon_mode:-off}"
  export PSIPHON_REGION="${psiphon_region:-auto}"
  export WARP_MODE="${warp_mode:-off}"
  export ROUTE_MODE="$mode"
  export OUTBOUND_PROXY_MODE="${outbound_proxy_mode:-direct}"
  export OUTBOUND_PROXY_HOST="${outbound_proxy_host:-}"
  export OUTBOUND_PROXY_PORT="${outbound_proxy_port:-}"
  export OUTBOUND_PROXY_USER="${outbound_proxy_user:-}"
  export OUTBOUND_PROXY_PASS="${outbound_proxy_pass:-}"
  export DIRECT_SHARE_ENDPOINTS="${direct_share_endpoints:-}"
  export PROXY_SHARE_ENDPOINTS="${proxy_share_endpoints:-}"
  export WARP_SHARE_ENDPOINTS="${warp_share_endpoints:-}"
  export IP_PREFERENCE="${ip_preference:-auto}"
  export CDN_TEMPLATE_HOST="${cdn_template_host:-}"
  export TLS_MODE="${tls_mode:-self-signed}"
  export ACME_CERT_PATH="${acme_cert_path:-}"
  export ACME_KEY_PATH="${acme_key_path:-}"
  export DOMAIN_SPLIT_DIRECT="${domain_split_direct:-}"
  export DOMAIN_SPLIT_PROXY="${domain_split_proxy:-}"
  export DOMAIN_SPLIT_BLOCK="${domain_split_block:-}"
  export PORT_EGRESS_MAP="${port_egress_map:-}"

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
  [[ -f /etc/sing-box-deve/runtime.env ]] || die "No runtime state found"
  local kind="$1" endpoints="$2"
  [[ "$endpoints" == *:* ]] || die "Endpoints must be host:port[,host:port...]"

  # shellcheck disable=SC1091
  source /etc/sing-box-deve/runtime.env
  local runtime_provider="${provider:-vps}" runtime_profile="${profile:-lite}"
  local runtime_engine="${engine:-sing-box}" runtime_protocols="${protocols:-vless-reality}"

  export ARGO_MODE="${argo_mode:-off}"
  export PSIPHON_ENABLE="${psiphon_enable:-off}"
  export PSIPHON_MODE="${psiphon_mode:-off}"
  export PSIPHON_REGION="${psiphon_region:-auto}"
  export WARP_MODE="${warp_mode:-off}"
  export ROUTE_MODE="${route_mode:-direct}"
  export OUTBOUND_PROXY_MODE="${outbound_proxy_mode:-direct}"
  export OUTBOUND_PROXY_HOST="${outbound_proxy_host:-}"
  export OUTBOUND_PROXY_PORT="${outbound_proxy_port:-}"
  export OUTBOUND_PROXY_USER="${outbound_proxy_user:-}"
  export OUTBOUND_PROXY_PASS="${outbound_proxy_pass:-}"
  export DIRECT_SHARE_ENDPOINTS="${direct_share_endpoints:-}"
  export PROXY_SHARE_ENDPOINTS="${proxy_share_endpoints:-}"
  export WARP_SHARE_ENDPOINTS="${warp_share_endpoints:-}"
  export IP_PREFERENCE="${ip_preference:-auto}"
  export CDN_TEMPLATE_HOST="${cdn_template_host:-}"
  export TLS_MODE="${tls_mode:-self-signed}"
  export ACME_CERT_PATH="${acme_cert_path:-}"
  export ACME_KEY_PATH="${acme_key_path:-}"
  export DOMAIN_SPLIT_DIRECT="${domain_split_direct:-}"
  export DOMAIN_SPLIT_PROXY="${domain_split_proxy:-}"
  export DOMAIN_SPLIT_BLOCK="${domain_split_block:-}"
  export PORT_EGRESS_MAP="${port_egress_map:-}"

  case "$kind" in
    direct) DIRECT_SHARE_ENDPOINTS="$endpoints" ;;
    proxy) PROXY_SHARE_ENDPOINTS="$endpoints" ;;
    warp) WARP_SHARE_ENDPOINTS="$endpoints" ;;
    *) die "Unsupported share endpoint kind: $kind" ;;
  esac

  write_nodes_output "$runtime_engine" "$runtime_protocols"
  persist_runtime_state "$runtime_provider" "$runtime_profile" "$runtime_engine" "$runtime_protocols"
  log_success "$(msg "分享出口已更新(${kind}): ${endpoints}" "Share endpoints updated for ${kind}: ${endpoints}")"
}
