#!/usr/bin/env bash

# Persist script files to a fixed location for reliable sb command access
# This is critical when running via bash <(curl ...) from a temporary directory
persist_script_installation() {
  sbd_persist_script_root_if_needed "$PROJECT_ROOT"
}

provider_install() {
  local provider="$1"
  local profile="$2"
  local engine="$3"
  local protocols_csv="$4"

  case "$provider" in
    vps)
      provider_vps_install "$profile" "$engine" "$protocols_csv"
      ;;
    serv00)
      provider_serv00_install "$profile" "$engine" "$protocols_csv"
      ;;
    sap)
      provider_sap_install "$profile" "$engine" "$protocols_csv"
      ;;
    docker)
      provider_docker_install "$profile" "$engine" "$protocols_csv"
      ;;
    *)
      die "Unsupported provider: $provider"
      ;;
  esac
}

reject_tls_auto_for_provider() {
  local provider="$1"
  [[ "${TLS_MODE:-self-signed}" != "acme-auto" ]] || \
    die "TLS_MODE=acme-auto is not supported for provider=${provider}; use provider=vps or cfg tls acme-auto on an installed VPS"
}

provider_vps_prepare_warp_account() {
  [[ "${WARP_MODE:-off}" != "off" ]] || return 0
  [[ -z "${WARP_PRIVATE_KEY:-}" ]] || return 0

  if declare -F provider_warp_account_load_optional >/dev/null 2>&1; then
    provider_warp_account_load_optional
    if [[ -n "${WARP_PRIVATE_KEY:-}" ]]; then
      log_info "$(msg "已加载现有 WARP 账户参数" "Loaded existing WARP account settings")"
      export WARP_PRIVATE_KEY WARP_PEER_PUBLIC_KEY WARP_RESERVED WARP_LOCAL_V4 WARP_LOCAL_V6 WARP_CLIENT_ID
      return 0
    fi
  fi

  log_info "$(msg "未检测到 WARP 账户，正在自动注册" "WARP account not found, registering automatically")"
  provider_warp_register
  provider_warp_load_account
  export WARP_PRIVATE_KEY WARP_PEER_PUBLIC_KEY WARP_RESERVED WARP_LOCAL_V4 WARP_LOCAL_V6 WARP_CLIENT_ID
}

resolve_tls_auto_for_install() {
  [[ "${TLS_MODE:-self-signed}" == "acme-auto" ]] || return 0

  local domain="${ACME_DOMAIN:-${TLS_SERVER_NAME:-}}"
  local tls_name
  local email="${ACME_EMAIL:-}"
  [[ -n "$domain" ]] || die "TLS_MODE=acme-auto requires --acme-domain or --tls-sni"
  [[ -n "$email" ]] || die "TLS_MODE=acme-auto requires --acme-email"

  provider_sys_acme_issue "$domain" "$email" "${ACME_DNS_PROVIDER:-}"
  [[ -n "${SBD_LAST_ACME_CERT_PATH:-}" && -n "${SBD_LAST_ACME_KEY_PATH:-}" ]] || die "ACME auto issue did not return cert/key paths"

  TLS_MODE="acme"
  tls_name="${TLS_SERVER_NAME:-$domain}"
  [[ "$tls_name" == "*."* ]] && tls_name="${tls_name#*.}"
  ACME_DOMAIN="$domain"
  ACME_CERT_PATH="$SBD_LAST_ACME_CERT_PATH"
  ACME_KEY_PATH="$SBD_LAST_ACME_KEY_PATH"
  TLS_SERVER_NAME="$tls_name"
}

provider_vps_install() {
  local profile="$1"
  local engine="$2"
  local protocols_csv="$3"

  log_info "$(msg "开始安装: provider=vps profile=${profile} engine=${engine}" "Installing for provider=vps profile=${profile} engine=${engine}")"
  install_apt_dependencies
  resolve_tls_auto_for_install
  validate_feature_modes
  provider_vps_prepare_warp_account
  assert_engine_protocol_compatibility "$engine" "$protocols_csv"

  local protocols=()
  protocols_to_array "$protocols_csv" protocols
  local protocol mapping proto port
  for protocol in "${protocols[@]}"; do
    mapping="$(protocol_port_map "$protocol")"
    proto="${mapping%%:*}"
    port="$(get_protocol_port "$protocol")"
    fw_apply_rule "$proto" "$port"
  done

  install_engine_binary "$engine"

  case "$engine" in
    sing-box) build_sing_box_config "$protocols_csv" ;;
    xray) build_xray_config "$protocols_csv" ;;
  esac

  validate_generated_config "$engine" "true"
  write_systemd_service "$engine"
  configure_argo_tunnel "$protocols_csv" "$engine"
  provider_psiphon_sync_service
  write_nodes_output "$engine" "$protocols_csv"

  mkdir -p "${SBD_CONFIG_DIR}"
  
  # Persist script to fixed location before saving runtime state
  # This ensures sb command works even after temp directory is cleaned
  persist_script_installation
  
  persist_runtime_state "vps" "$profile" "$engine" "$protocols_csv"

  write_sb_launcher

  log_success "$(msg "VPS 场景部署完成" "VPS provider setup complete")"
}

persist_runtime_state() {
  local provider="$1"
  local profile="$2"
  local engine="$3"
  local protocols_csv="$4"
  local runtime_file="${SBD_CONFIG_DIR}/runtime.env" tmp_runtime
  mkdir -p "$(dirname "$runtime_file")"
  tmp_runtime="$(mktemp "${runtime_file}.tmp.XXXXXX")"
  cat > "$tmp_runtime" <<EOF
provider=${provider}
profile=${profile}
engine=${engine}
protocols=${protocols_csv}
argo_mode=${ARGO_MODE:-off}
argo_domain=${ARGO_DOMAIN:-}
argo_token=${ARGO_TOKEN:-}
argo_cdn_endpoints=${ARGO_CDN_ENDPOINTS:-}
psiphon_enable=${PSIPHON_ENABLE:-off}
psiphon_mode=${PSIPHON_MODE:-off}
psiphon_region=${PSIPHON_REGION:-auto}
warp_mode=${WARP_MODE:-off}
route_mode=${ROUTE_MODE:-direct}
ip_preference=${IP_PREFERENCE:-auto}
cdn_template_host=${CDN_TEMPLATE_HOST:-}
tls_mode=${TLS_MODE:-self-signed}
acme_cert_path=${ACME_CERT_PATH:-}
acme_key_path=${ACME_KEY_PATH:-}
acme_domain=${ACME_DOMAIN:-}
acme_email=${ACME_EMAIL:-}
acme_dns_provider=${ACME_DNS_PROVIDER:-}
reality_server_name=${REALITY_SERVER_NAME:-${reality_server_name:-}}
reality_fingerprint=${REALITY_FINGERPRINT:-${reality_fingerprint:-}}
reality_handshake_port=${REALITY_HANDSHAKE_PORT:-${reality_handshake_port:-}}
tls_server_name=${TLS_SERVER_NAME:-${tls_server_name:-}}
vmess_ws_path=${VMESS_WS_PATH:-${vmess_ws_path:-}}
vless_ws_path=${VLESS_WS_PATH:-${vless_ws_path:-}}
vless_xhttp_path=${VLESS_XHTTP_PATH:-${vless_xhttp_path:-}}
vless_xhttp_mode=${VLESS_XHTTP_MODE:-${vless_xhttp_mode:-}}
xray_vless_enc=${XRAY_VLESS_ENC:-${xray_vless_enc:-false}}
xray_xhttp_reality=${XRAY_XHTTP_REALITY:-${xray_xhttp_reality:-false}}
cdn_host_vmess=${CDN_HOST_VMESS:-${cdn_host_vmess:-}}
cdn_host_vless_ws=${CDN_HOST_VLESS_WS:-${cdn_host_vless_ws:-}}
cdn_host_vless_xhttp=${CDN_HOST_VLESS_XHTTP:-${cdn_host_vless_xhttp:-}}
proxyip_vmess=${PROXYIP_VMESS:-${proxyip_vmess:-}}
proxyip_vless_ws=${PROXYIP_VLESS_WS:-${proxyip_vless_ws:-}}
proxyip_vless_xhttp=${PROXYIP_VLESS_XHTTP:-${proxyip_vless_xhttp:-}}
domain_split_direct=${DOMAIN_SPLIT_DIRECT:-}
domain_split_proxy=${DOMAIN_SPLIT_PROXY:-}
domain_split_block=${DOMAIN_SPLIT_BLOCK:-}
port_egress_map=${PORT_EGRESS_MAP-${port_egress_map:-}}
outbound_proxy_mode=${OUTBOUND_PROXY_MODE:-direct}
outbound_proxy_host=${OUTBOUND_PROXY_HOST:-}
outbound_proxy_port=${OUTBOUND_PROXY_PORT:-}
outbound_proxy_user=${OUTBOUND_PROXY_USER:-}
outbound_proxy_pass=${OUTBOUND_PROXY_PASS:-}
direct_share_endpoints=${DIRECT_SHARE_ENDPOINTS:-}
proxy_share_endpoints=${PROXY_SHARE_ENDPOINTS:-}
warp_share_endpoints=${WARP_SHARE_ENDPOINTS:-}
script_root=${PROJECT_ROOT}
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
  sbd_commit_file_with_backups "$runtime_file" "$tmp_runtime" 600
}
