#!/usr/bin/env bash

# Persist script files to a fixed location for reliable sb command access
# This is critical when running via bash <(curl ...) from a temporary directory
persist_script_installation() {
  local persist_dir="/opt/sing-box-deve/script"
  local source_dir="${PROJECT_ROOT}"
  
  # Skip if already running from persist_dir
  if [[ "$source_dir" == "$persist_dir" ]]; then
    log_info "$(msg "脚本已在持久化目录中运行" "Script already running from persistent directory")"
    return 0
  fi
  
  # Check if source directory has the required files
  if [[ ! -f "$source_dir/sing-box-deve.sh" ]]; then
    log_warn "$(msg "无法找到脚本源文件，跳过持久化" "Cannot find script source files, skipping persistence")"
    return 0
  fi
  
  log_info "$(msg "正在将脚本安装到 ${persist_dir}" "Installing script to ${persist_dir}")"
  
  # Create target directory
  mkdir -p "$persist_dir"
  
  # Copy main script and version
  cp -f "$source_dir/sing-box-deve.sh" "$persist_dir/"
  [[ -f "$source_dir/version" ]] && cp -f "$source_dir/version" "$persist_dir/"
  [[ -f "$source_dir/checksums.txt" ]] && cp -f "$source_dir/checksums.txt" "$persist_dir/"
  
  # Copy lib directory
  if [[ -d "$source_dir/lib" ]]; then
    mkdir -p "$persist_dir/lib"
    cp -rf "$source_dir/lib/"* "$persist_dir/lib/"
  fi
  
  # Copy providers directory
  if [[ -d "$source_dir/providers" ]]; then
    mkdir -p "$persist_dir/providers"
    cp -rf "$source_dir/providers/"* "$persist_dir/providers/"
  fi
  
  # Copy scripts directory
  if [[ -d "$source_dir/scripts" ]]; then
    mkdir -p "$persist_dir/scripts"
    cp -rf "$source_dir/scripts/"* "$persist_dir/scripts/"
  fi
  
  # Copy docs and examples for reference
  [[ -d "$source_dir/docs" ]] && { mkdir -p "$persist_dir/docs"; cp -rf "$source_dir/docs/"* "$persist_dir/docs/"; }
  [[ -d "$source_dir/examples" ]] && { mkdir -p "$persist_dir/examples"; cp -rf "$source_dir/examples/"* "$persist_dir/examples/"; }
  [[ -d "$source_dir/rulesets" ]] && { mkdir -p "$persist_dir/rulesets"; cp -rf "$source_dir/rulesets/"* "$persist_dir/rulesets/"; }
  
  # Set executable permissions
  chmod +x "$persist_dir/sing-box-deve.sh"
  chmod +x "$persist_dir/lib/"*.sh 2>/dev/null || true
  chmod +x "$persist_dir/providers/"*.sh 2>/dev/null || true
  chmod +x "$persist_dir/scripts/"*.sh 2>/dev/null || true
  
  # Update PROJECT_ROOT for runtime.env
  PROJECT_ROOT="$persist_dir"
  
  log_success "$(msg "脚本已安装到 ${persist_dir}" "Script installed to ${persist_dir}")"
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

provider_vps_install() {
  local profile="$1"
  local engine="$2"
  local protocols_csv="$3"

  log_info "$(msg "开始安装: provider=vps profile=${profile} engine=${engine}" "Installing for provider=vps profile=${profile} engine=${engine}")"
  install_apt_dependencies
  validate_feature_modes
  assert_engine_protocol_compatibility "$engine" "$protocols_csv"

  local protocols=()
  protocols_to_array "$protocols_csv" protocols
  local protocol mapping proto port
  for protocol in "${protocols[@]}"; do
    if [[ "$protocol" == "argo" || "$protocol" == "warp" ]]; then
      continue
    fi
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

  mkdir -p /etc/sing-box-deve
  
  # Persist script to fixed location before saving runtime state
  # This ensures sb command works even after temp directory is cleaned
  persist_script_installation
  
  persist_runtime_state "vps" "$profile" "$engine" "$protocols_csv"

  cat > /usr/local/bin/sb <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

script_root=""
if [[ -f /etc/sing-box-deve/runtime.env ]]; then
  # shellcheck disable=SC1091
  source /etc/sing-box-deve/runtime.env
  script_root="${script_root:-}"
fi

if [[ -n "$script_root" && -x "$script_root/sing-box-deve.sh" ]]; then
  :
else
  script_root=""
  for candidate in "/opt/sing-box-deve/script" "/opt/sing-box-deve" "/usr/local/share/sing-box-deve" "$PWD/sing-box-deve"; do
    if [[ -x "$candidate/sing-box-deve.sh" ]]; then
      script_root="$candidate"
      break
    fi
  done
fi

if [[ -z "$script_root" || ! -x "$script_root/sing-box-deve.sh" ]]; then
  echo "[ERROR] Unable to locate sing-box-deve.sh. Reinstall with: sudo bash ./sing-box-deve.sh install ..." >&2
  exit 1
fi

if [[ $# -eq 0 ]]; then
  exec "$script_root/sing-box-deve.sh" menu
fi

exec "$script_root/sing-box-deve.sh" "$@"
EOF
  chmod +x /usr/local/bin/sb

  log_success "$(msg "VPS 场景部署完成" "VPS provider setup complete")"
}

persist_runtime_state() {
  local provider="$1"
  local profile="$2"
  local engine="$3"
  local protocols_csv="$4"
  cat > /etc/sing-box-deve/runtime.env <<EOF
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
port_egress_map=${PORT_EGRESS_MAP:-${port_egress_map:-}}
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
}
