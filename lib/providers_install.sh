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
    provider_warp_account_load_optional || return 1
    if [[ -n "${WARP_PRIVATE_KEY:-}" ]]; then
      log_info "$(msg "已加载现有 WARP 账户参数" "Loaded existing WARP account settings")"
      export WARP_PRIVATE_KEY WARP_PEER_PUBLIC_KEY WARP_RESERVED WARP_LOCAL_V4 WARP_LOCAL_V6 WARP_CLIENT_ID
      return 0
    fi
  fi

  log_info "$(msg "未检测到 WARP 账户，正在自动注册" "WARP account not found, registering automatically")"
  # Installation builds its own candidate; do not rebuild the old live runtime.
  provider_warp_register_account || return 1
  provider_warp_load_account || return 1
  export WARP_PRIVATE_KEY WARP_PEER_PUBLIC_KEY WARP_RESERVED WARP_LOCAL_V4 WARP_LOCAL_V6 WARP_CLIENT_ID
}

provider_vps_install() {
  local profile="$1"
  local engine="$2"
  local protocols_csv="$3"

  log_info "$(msg "开始安装: provider=vps profile=${profile} engine=${engine}" "Installing for provider=vps profile=${profile} engine=${engine}")"
  validate_feature_modes || return 1
  sbd_web_front_preflight "$protocols_csv" || return 1
  install_apt_dependencies || return 1
  provider_prepare_domain_runtime_artifacts "$protocols_csv" || return 1
  provider_vps_prepare_warp_account || return 1
  assert_engine_protocol_compatibility "$engine" "$protocols_csv" || return 1

  local candidate_root
  candidate_root="${SBD_ACTIVE_TRANSACTION:?Install requires a transaction}/candidate"
  sbd_transaction_phase "$SBD_ACTIVE_TRANSACTION" staging || return 1
  mkdir -p "$candidate_root" || return 1
  provider_core_candidate_install "$engine" "$candidate_root" || return 1
  provider_core_candidate_build "$engine" "$protocols_csv" "$candidate_root" || return 1
  persist_script_installation || return 1
  sbd_transaction_phase "$SBD_ACTIVE_TRANSACTION" committing || return 1
  provider_core_candidate_binary_commit "$engine" "$candidate_root" || return 1
  provider_core_candidate_data_commit "$candidate_root" || return 1
  provider_core_candidate_commit "$engine" "$candidate_root" || return 1

  local protocols=()
  protocols_to_array "$protocols_csv" protocols || return 1
  local protocol mapping proto port
  for protocol in "${protocols[@]}"; do
    mapping="$(protocol_port_map "$protocol")"
    proto="${mapping%%:*}"
    port="$(get_protocol_port "$protocol")"
    fw_apply_rule "$proto" "$port" || return 1
  done

  validate_generated_config "$engine" "true" || return 1
  provider_commit_domain_web_front "$protocols_csv" || return 1
  write_systemd_service "$engine" || return 1
  configure_argo_tunnel "$protocols_csv" "$engine" || return 1
  write_nodes_output "$engine" "$protocols_csv" || return 1

  mkdir -p "${SBD_CONFIG_DIR}" || return 1
  
  persist_runtime_state "vps" "$profile" "$engine" "$protocols_csv" || return 1

  write_sb_launcher || return 1

  log_success "$(msg "VPS 场景部署完成" "VPS provider setup complete")"
}

persist_runtime_state() {
  local provider="$1"
  local profile="$2"
  local engine="$3"
  local protocols_csv="$4"
  local runtime_file="${SBD_CONFIG_DIR}/runtime.env" tmp_runtime hy2_obfs_password_state="${HY2_OBFS_PASSWORD:-}"
  if [[ "${HY2_OBFS_MODE:-off}" != "off" && -z "$hy2_obfs_password_state" && -s "${SBD_DATA_DIR}/hy2_obfs_password" ]]; then
    hy2_obfs_password_state="$(tr -d '\r\n' < "${SBD_DATA_DIR}/hy2_obfs_password")"
  fi
  mkdir -p "$(dirname "$runtime_file")" || return 1
  tmp_runtime="$(mktemp "${runtime_file}.tmp.XXXXXX")" || return 1
  (
    sbd_write_env_kv provider "$provider" || exit 1
    sbd_write_env_kv profile "$profile" || exit 1
    sbd_write_env_kv engine "$engine" || exit 1
    sbd_write_env_kv protocols "$protocols_csv" || exit 1
    sbd_write_env_kv argo_mode "${ARGO_MODE:-off}" || exit 1
    sbd_write_env_kv argo_domain "${ARGO_DOMAIN:-}" || exit 1
    sbd_write_env_kv argo_token "${ARGO_TOKEN:-}" || exit 1
    sbd_write_env_kv argo_cdn_endpoints "${ARGO_CDN_ENDPOINTS:-}" || exit 1
    sbd_write_env_kv warp_mode "${WARP_MODE:-off}" || exit 1
    sbd_write_env_kv route_mode "${ROUTE_MODE:-direct}" || exit 1
    sbd_write_env_kv ip_preference "${IP_PREFERENCE:-auto}" || exit 1
    sbd_write_env_kv cdn_template_host "${CDN_TEMPLATE_HOST:-}" || exit 1
    sbd_write_env_kv tls_mode "${TLS_MODE:-self-signed}" || exit 1
    sbd_write_env_kv acme_cert_path "${ACME_CERT_PATH:-}" || exit 1
    sbd_write_env_kv acme_key_path "${ACME_KEY_PATH:-}" || exit 1
    sbd_write_env_kv acme_domain "${ACME_DOMAIN:-}" || exit 1
    sbd_write_env_kv acme_email "${ACME_EMAIL:-}" || exit 1
    sbd_write_env_kv acme_dns_provider "${ACME_DNS_PROVIDER:-}" || exit 1
    sbd_write_env_kv web_front_mode "${WEB_FRONT_MODE:-auto}" || exit 1
    sbd_write_env_kv web_front_engine "${WEB_FRONT_ENGINE:-}" || exit 1
    sbd_write_env_kv web_front_conf "${WEB_FRONT_CONF:-}" || exit 1
    sbd_write_env_kv web_front_domain "${WEB_FRONT_DOMAIN:-}" || exit 1
    sbd_write_env_kv hy2_obfs_mode "${HY2_OBFS_MODE:-off}" || exit 1
    sbd_write_env_kv hy2_obfs_password "$hy2_obfs_password_state" || exit 1
    sbd_write_env_kv reality_server_name "${REALITY_SERVER_NAME:-${reality_server_name:-}}" || exit 1
    sbd_write_env_kv reality_fingerprint "${REALITY_FINGERPRINT:-${reality_fingerprint:-}}" || exit 1
    sbd_write_env_kv reality_handshake_port "${REALITY_HANDSHAKE_PORT:-${reality_handshake_port:-}}" || exit 1
    sbd_write_env_kv tls_server_name "${TLS_SERVER_NAME:-${tls_server_name:-}}" || exit 1
    sbd_write_env_kv archive_site_dir "${SBD_ARCHIVE_SITE_DIR:-${archive_site_dir:-}}" || exit 1
    sbd_write_env_kv vmess_ws_path "${VMESS_WS_PATH:-${vmess_ws_path:-}}" || exit 1
    sbd_write_env_kv vless_ws_path "${VLESS_WS_PATH:-${vless_ws_path:-}}" || exit 1
    sbd_write_env_kv vless_xhttp_path "${VLESS_XHTTP_PATH:-${vless_xhttp_path:-}}" || exit 1
    sbd_write_env_kv vless_xhttp_mode "${VLESS_XHTTP_MODE:-${vless_xhttp_mode:-}}" || exit 1
    sbd_write_env_kv xray_vless_enc "${XRAY_VLESS_ENC:-${xray_vless_enc:-false}}" || exit 1
    sbd_write_env_kv xray_xhttp_reality "${XRAY_XHTTP_REALITY:-${xray_xhttp_reality:-false}}" || exit 1
    sbd_write_env_kv cdn_host_vmess "${CDN_HOST_VMESS:-${cdn_host_vmess:-}}" || exit 1
    sbd_write_env_kv cdn_host_vless_ws "${CDN_HOST_VLESS_WS:-${cdn_host_vless_ws:-}}" || exit 1
    sbd_write_env_kv cdn_host_vless_xhttp "${CDN_HOST_VLESS_XHTTP:-${cdn_host_vless_xhttp:-}}" || exit 1
    sbd_write_env_kv proxyip_vmess "${PROXYIP_VMESS:-${proxyip_vmess:-}}" || exit 1
    sbd_write_env_kv proxyip_vless_ws "${PROXYIP_VLESS_WS:-${proxyip_vless_ws:-}}" || exit 1
    sbd_write_env_kv proxyip_vless_xhttp "${PROXYIP_VLESS_XHTTP:-${proxyip_vless_xhttp:-}}" || exit 1
    sbd_write_env_kv domain_split_direct "${DOMAIN_SPLIT_DIRECT:-}" || exit 1
    sbd_write_env_kv domain_split_proxy "${DOMAIN_SPLIT_PROXY:-}" || exit 1
    sbd_write_env_kv domain_split_block "${DOMAIN_SPLIT_BLOCK:-}" || exit 1
    if [[ -n "${OUTBOUND_PROXY_LINK:-}" ]]; then sbd_write_env_kv outbound_proxy_link "$OUTBOUND_PROXY_LINK" || exit 1; fi
    sbd_write_env_kv outbound_proxy_mode "${OUTBOUND_PROXY_MODE:-direct}" || exit 1
    sbd_write_env_kv outbound_proxy_udp_mode "${OUTBOUND_PROXY_UDP_MODE:-proxy}" || exit 1
    sbd_write_env_kv outbound_proxy_host "${OUTBOUND_PROXY_HOST:-}" || exit 1
    sbd_write_env_kv outbound_proxy_port "${OUTBOUND_PROXY_PORT:-}" || exit 1
    sbd_write_env_kv outbound_proxy_user "${OUTBOUND_PROXY_USER:-}" || exit 1
    sbd_write_env_kv outbound_proxy_pass "${OUTBOUND_PROXY_PASS:-}" || exit 1
    if [[ -L "$SBD_INSTALL_DIR/current" ]]; then
      sbd_write_env_kv script_root "$SBD_INSTALL_DIR/current" || exit 1
    else
      sbd_write_env_kv script_root "$PROJECT_ROOT" || exit 1
    fi
    sbd_write_env_kv installed_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" || exit 1
  ) > "$tmp_runtime" || { rm -f "$tmp_runtime"; return 1; }
  sbd_seal_runtime_file "$tmp_runtime" || { rm -f "$tmp_runtime"; return 1; }
  sbd_commit_file_with_backups "$runtime_file" "$tmp_runtime" 600
}
