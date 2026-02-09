#!/usr/bin/env bash

provider_cfg_runtime_file() {
  echo "/etc/sing-box-deve/runtime.env"
}

provider_cfg_load_runtime_exports() {
  local runtime_file
  runtime_file="$(provider_cfg_runtime_file)"
  [[ -f "$runtime_file" ]] || die "$(msg "未找到运行时状态" "No runtime state found")"
  # shellcheck disable=SC1090
  source "$runtime_file"
  export ARGO_MODE="${argo_mode:-off}"
  export ARGO_DOMAIN="${argo_domain:-}"
  export ARGO_TOKEN="${argo_token:-}"
  export ARGO_CDN_ENDPOINTS="${argo_cdn_endpoints:-}"
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
  export REALITY_SERVER_NAME="${reality_server_name:-}"
  export REALITY_FINGERPRINT="${reality_fingerprint:-}"
  export REALITY_HANDSHAKE_PORT="${reality_handshake_port:-}"
  export TLS_SERVER_NAME="${tls_server_name:-}"
  export VMESS_WS_PATH="${vmess_ws_path:-}"
  export VLESS_WS_PATH="${vless_ws_path:-}"
  export VLESS_XHTTP_PATH="${vless_xhttp_path:-}"
  export VLESS_XHTTP_MODE="${vless_xhttp_mode:-auto}"
  export XRAY_VLESS_ENC="${xray_vless_enc:-false}"
  export XRAY_XHTTP_REALITY="${xray_xhttp_reality:-false}"
  export CDN_HOST_VMESS="${cdn_host_vmess:-}"
  export CDN_HOST_VLESS_WS="${cdn_host_vless_ws:-}"
  export CDN_HOST_VLESS_XHTTP="${cdn_host_vless_xhttp:-}"
  export PROXYIP_VMESS="${proxyip_vmess:-}"
  export PROXYIP_VLESS_WS="${proxyip_vless_ws:-}"
  export PROXYIP_VLESS_XHTTP="${proxyip_vless_xhttp:-}"
  export DOMAIN_SPLIT_DIRECT="${domain_split_direct:-}"
  export DOMAIN_SPLIT_PROXY="${domain_split_proxy:-}"
  export DOMAIN_SPLIT_BLOCK="${domain_split_block:-}"
  export PORT_EGRESS_MAP="${port_egress_map:-}"
  CFG_RUNTIME_LOADED="true"
}

# shellcheck disable=SC2120
provider_cfg_rebuild_runtime() {
  ensure_root
  local target_protocols="${1:-}"
  if [[ "${CFG_RUNTIME_LOADED:-false}" != "true" ]]; then
    provider_cfg_load_runtime_exports
  fi
  [[ -n "$target_protocols" ]] && protocols="$target_protocols"
  validate_feature_modes
  case "${engine:-sing-box}" in
    sing-box) build_sing_box_config "${protocols:-vless-reality}" && validate_generated_config "sing-box" "true" ;;
    xray) build_xray_config "${protocols:-vless-reality}" && validate_generated_config "xray" "true" ;;
    *) die "$(msg "运行时内核不受支持: ${engine:-unknown}" "Unsupported engine in runtime: ${engine:-unknown}")" ;;
  esac
  write_nodes_output "${engine:-sing-box}" "${protocols:-vless-reality}"
  persist_runtime_state "${provider:-vps}" "${profile:-lite}" "${engine:-sing-box}" "${protocols:-vless-reality}"
  provider_restart core
}

provider_cfg_rotate_identity() {
  ensure_root
  provider_cfg_load_runtime_exports
  ensure_uuid > "${SBD_DATA_DIR}/uuid"
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 4 > "${SBD_DATA_DIR}/reality_short_id" 2>/dev/null || true
    openssl rand -hex 4 > "${SBD_DATA_DIR}/xray_short_id" 2>/dev/null || true
  else
    rand_hex_8 > "${SBD_DATA_DIR}/reality_short_id"
    rand_hex_8 > "${SBD_DATA_DIR}/xray_short_id"
  fi
  provider_cfg_rebuild_runtime
  log_success "$(msg "身份标识已轮换（UUID/short-id）" "Identity rotated (UUID/short-id)")"
}

provider_cfg_set_argo() {
  ensure_root
  local mode="$1" token="${2:-}" domain="${3:-}"
  case "$mode" in off|temp|fixed) ;;
    *) die "$(msg "用法: cfg argo <off|temp|fixed> [token] [domain]" "Usage: cfg argo <off|temp|fixed> [token] [domain]")" ;;
  esac
  provider_cfg_load_runtime_exports
  ARGO_MODE="$mode"; ARGO_TOKEN="$token"; ARGO_DOMAIN="$domain"
  if [[ "$mode" == "off" ]]; then
    systemctl disable --now sing-box-deve-argo.service >/dev/null 2>&1 || true
    rm -f "$SBD_ARGO_SERVICE_FILE"
    rm -f "${SBD_DATA_DIR}/argo_domain" "${SBD_DATA_DIR}/argo_mode"
    systemctl daemon-reload
  else
    configure_argo_tunnel "${protocols:-vless-reality}" "${engine:-sing-box}"
  fi
  write_nodes_output "${engine:-sing-box}" "${protocols:-vless-reality}"
  persist_runtime_state "${provider:-vps}" "${profile:-lite}" "${engine:-sing-box}" "${protocols:-vless-reality}"
  log_success "$(msg "Argo 模式已更新: ${mode}" "Argo mode updated: ${mode}")"
}

provider_cfg_set_ip_preference() {
  ensure_root
  local pref="$1"
  case "$pref" in auto|v4|v6) ;;
    *) die "$(msg "用法: cfg ip-pref <auto|v4|v6>" "Usage: cfg ip-pref <auto|v4|v6>")" ;;
  esac
  provider_cfg_load_runtime_exports
  IP_PREFERENCE="$pref"
  provider_cfg_rebuild_runtime
  log_success "$(msg "IP 优先级已更新: ${pref}" "IP preference updated: ${pref}")"
}

provider_cfg_set_cdn_host() {
  ensure_root
  local host="$1"
  [[ -n "$host" ]] || die "$(msg "用法: cfg cdn-host <domain>" "Usage: cfg cdn-host <domain>")"
  provider_cfg_load_runtime_exports
  CDN_TEMPLATE_HOST="$host"
  write_nodes_output "${engine:-sing-box}" "${protocols:-vless-reality}"
  persist_runtime_state "${provider:-vps}" "${profile:-lite}" "${engine:-sing-box}" "${protocols:-vless-reality}"
  log_success "$(msg "CDN 主机模板已更新: ${host}" "CDN host template updated: ${host}")"
}

provider_cfg_set_domain_split() {
  ensure_root
  local direct="$1" proxy="$2" block="$3"
  provider_cfg_load_runtime_exports
  DOMAIN_SPLIT_DIRECT="$direct"
  DOMAIN_SPLIT_PROXY="$proxy"
  DOMAIN_SPLIT_BLOCK="$block"
  provider_cfg_rebuild_runtime
  log_success "$(msg "域名分流规则已更新" "Domain split updated")"
}

provider_cfg_set_tls() {
  ensure_root
  local mode="$1" cert="${2:-}" key="${3:-}" dns_provider="${4:-${ACME_DNS_PROVIDER:-}}"
  case "$mode" in self-signed|acme|acme-auto) ;;
    *) die "$(msg "用法: cfg tls <self-signed|acme|acme-auto> [cert_path|domain] [key_path|email] [dns_provider]" "Usage: cfg tls <self-signed|acme|acme-auto> [cert_path|domain] [key_path|email] [dns_provider]")" ;;
  esac
  provider_cfg_load_runtime_exports
  if [[ "$mode" == "acme-auto" ]]; then
    local domain="$cert" email="$key"
    [[ -n "$domain" && -n "$email" ]] || die "$(msg "用法: cfg tls acme-auto <domain> <email> [dns_provider]" "Usage: cfg tls acme-auto <domain> <email> [dns_provider]")"
    provider_sys_acme_issue "$domain" "$email" "$dns_provider"
    cert="${SBD_LAST_ACME_CERT_PATH:-}"
    key="${SBD_LAST_ACME_KEY_PATH:-}"
    if [[ -z "$cert" || -z "$key" ]]; then
      acme_resolve_existing_cert "$domain" cert key || true
    fi
    [[ -f "$cert" && -f "$key" ]] || die "$(msg "ACME 自动签发完成但证书文件缺失" "ACME auto issue succeeded but cert files missing")"
    mode="acme"
  fi

  TLS_MODE="$mode"
  if [[ "$TLS_MODE" == "acme" ]]; then
    ACME_CERT_PATH="$cert"
    ACME_KEY_PATH="$key"
  else
    ACME_CERT_PATH=""
    ACME_KEY_PATH=""
  fi
  provider_cfg_rebuild_runtime
  log_success "$(msg "TLS 模式已更新: ${mode}" "TLS mode updated: ${mode}")"
}

provider_cfg_apply_dispatch() {
  local action="${1:-}"
  shift || true
  case "$action" in
    rotate-id) provider_cfg_rotate_identity ;;
    argo) provider_cfg_set_argo "$@" ;;
    ip-pref) provider_cfg_set_ip_preference "$@" ;;
    cdn-host) provider_cfg_set_cdn_host "$@" ;;
    domain-split) provider_cfg_set_domain_split "${1:-}" "${2:-}" "${3:-}" ;;
    tls) provider_cfg_set_tls "$@" ;;
    protocol-add) provider_cfg_protocol_add "${1:-}" "${2:-random}" "${3:-}" ;;
    protocol-remove) provider_cfg_protocol_remove "${1:-}" ;;
    rebuild) provider_cfg_rebuild_runtime ;;
    *) die "$(msg "用法: cfg apply <rotate-id|argo|ip-pref|cdn-host|domain-split|tls|protocol-add|protocol-remove|rebuild> ..." "Usage: cfg apply <rotate-id|argo|ip-pref|cdn-host|domain-split|tls|protocol-add|protocol-remove|rebuild> ...")" ;;
  esac
}
