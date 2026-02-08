#!/usr/bin/env bash

show_version() {
  local local_ver remote_ver
  local_ver="$(current_script_version)"
  remote_ver="$(fetch_remote_script_version "auto" 2>/dev/null || true)"

  log_info "$(msg "当前脚本版本" "Current script version"): ${local_ver}"
  if [[ -n "$remote_ver" ]]; then
    log_info "$(msg "远程最新版本" "Remote latest version"): ${remote_ver}"
    [[ -n "${SBD_ACTIVE_UPDATE_BASE_URL:-}" ]] && log_info "$(msg "更新源" "Update source"): ${SBD_ACTIVE_UPDATE_BASE_URL}"
  else
    log_warn "$(msg "无法获取远程版本（可设置 SBD_UPDATE_BASE_URL）" "Unable to fetch remote version (set SBD_UPDATE_BASE_URL if needed)")"
  fi
}

update_command() {
  parse_update_args "$@"

  if [[ "$UPDATE_SCRIPT" == "true" ]]; then
    local local_ver remote_ver
    local_ver="$(current_script_version)"
    remote_ver="$(fetch_remote_script_version "${UPDATE_SOURCE:-auto}" 2>/dev/null || true)"

    if [[ -n "$remote_ver" && "$remote_ver" == "$local_ver" ]]; then
      log_info "$(msg "脚本已是最新版本" "Script is already up to date") (${local_ver})"
    else
      if prompt_yes_no "$(msg "更新脚本本体与模块文件吗？" "Update script and module files?")" "Y"; then
        [[ -n "${SBD_ACTIVE_UPDATE_BASE_URL:-}" ]] && log_info "$(msg "更新源" "Update source"): ${SBD_ACTIVE_UPDATE_BASE_URL}"
        perform_script_self_update
        log_success "$(msg "脚本更新完成，请重新执行命令" "Script update completed, please rerun command")"
      else
        log_warn "$(msg "已跳过脚本更新" "Skipped script update")"
      fi
    fi
  fi

  if [[ "$UPDATE_CORE" == "true" ]]; then
    if prompt_yes_no "$(msg "更新已安装的核心（sing-box/xray）吗？" "Update installed core engine (sing-box/xray)?")" "Y"; then
      provider_update
    else
      log_warn "$(msg "已跳过核心更新" "Skipped core engine update")"
    fi
  fi
}

settings_command() {
  local sub="${1:-show}"
  case "$sub" in
    show)
      show_settings
      ;;
    set)
      ensure_root
      shift
      [[ $# -ge 1 ]] || die "Usage: settings set <key> <value> OR settings set key=value ..."
      if [[ $# -eq 2 ]] && [[ "$1" != *"="* ]]; then
        set_setting "$1" "$2"
      else
        local kv key value
        for kv in "$@"; do
          if [[ "$kv" != *"="* ]]; then
            die "Invalid setting format: $kv (expected key=value)"
          fi
          key="${kv%%=*}"
          value="${kv#*=}"
          [[ -n "$key" ]] || die "Invalid setting key in: $kv"
          set_setting "$key" "$value"
        done
      fi
      log_success "$(msg "设置已保存" "Setting saved")"
      show_settings
      ;;
    *)
      die "Usage: settings [show|set <key> <value>|set key=value ...]"
      ;;
  esac
}

run_install() {
  local provider="$1"
  local profile="$2"
  local engine="$3"
  local protocols_csv="$4"
  local dry_run="$5"

  ensure_root
  detect_os
  init_runtime_layout

  validate_provider "$provider"
  validate_engine "$engine"
  validate_profile_protocols "$profile" "$protocols_csv"
  prepare_initial_install_ports "$protocols_csv"

  export ARGO_MODE ARGO_DOMAIN ARGO_TOKEN WARP_MODE ROUTE_MODE IP_PREFERENCE CDN_TEMPLATE_HOST TLS_MODE ACME_CERT_PATH ACME_KEY_PATH REALITY_SERVER_NAME REALITY_FINGERPRINT REALITY_HANDSHAKE_PORT TLS_SERVER_NAME VMESS_WS_PATH VLESS_WS_PATH VLESS_XHTTP_PATH VLESS_XHTTP_MODE XRAY_VLESS_ENC XRAY_XHTTP_REALITY CDN_HOST_VMESS CDN_HOST_VLESS_WS CDN_HOST_VLESS_XHTTP PROXYIP_VMESS PROXYIP_VLESS_WS PROXYIP_VLESS_XHTTP DOMAIN_SPLIT_DIRECT DOMAIN_SPLIT_PROXY DOMAIN_SPLIT_BLOCK OUTBOUND_PROXY_MODE OUTBOUND_PROXY_HOST OUTBOUND_PROXY_PORT OUTBOUND_PROXY_USER OUTBOUND_PROXY_PASS DIRECT_SHARE_ENDPOINTS PROXY_SHARE_ENDPOINTS WARP_SHARE_ENDPOINTS

  create_install_context "$provider" "$profile" "$engine" "$protocols_csv"
  auto_generate_config_snapshot "$CONFIG_SNAPSHOT_FILE"

  fw_detect_backend
  fw_snapshot_create

  if [[ "$dry_run" == "true" ]]; then
    log_info "Dry-run enabled; no system changes applied"
    print_plan_summary "$provider" "$profile" "$engine" "$protocols_csv"
    return 0
  fi

  if [[ "${AUTO_YES:-false}" != "true" ]]; then
    print_plan_summary "$provider" "$profile" "$engine" "$protocols_csv"
    if ! prompt_yes_no "$(msg "确认执行该安装计划吗？" "Apply this plan?")" "Y"; then
      log_warn "Installation aborted by user"
      exit 0
    fi
  fi

  if ! provider_install "$provider" "$profile" "$engine" "$protocols_csv"; then
    log_error "Install failed; rolling back firewall changes"
    fw_rollback
    exit 1
  fi

  log_success "Installation flow completed"
  print_post_install_info "$provider" "$profile" "$engine" "$protocols_csv"
}

apply_config() {
  local config_file="$1"
  ensure_root
  detect_os
  init_runtime_layout

  [[ -f "$config_file" ]] || die "Config file not found: $config_file"

  # shellcheck disable=SC1090
  source "$config_file"

  local provider="${provider:-vps}"
  local profile="${profile:-lite}"
  local engine="${engine:-sing-box}"
  local protocols="${protocols:-vless-reality}"
  export ARGO_MODE="${argo_mode:-${ARGO_MODE:-off}}"
  export ARGO_DOMAIN="${argo_domain:-${ARGO_DOMAIN:-}}"
  export ARGO_TOKEN="${argo_token:-${ARGO_TOKEN:-}}"
  export WARP_MODE="${warp_mode:-${WARP_MODE:-off}}"
  export ROUTE_MODE="${route_mode:-${ROUTE_MODE:-direct}}"
  export IP_PREFERENCE="${ip_preference:-${IP_PREFERENCE:-auto}}"
  export CDN_TEMPLATE_HOST="${cdn_template_host:-${CDN_TEMPLATE_HOST:-}}"
  export TLS_MODE="${tls_mode:-${TLS_MODE:-self-signed}}"
  export ACME_CERT_PATH="${acme_cert_path:-${ACME_CERT_PATH:-}}"
  export ACME_KEY_PATH="${acme_key_path:-${ACME_KEY_PATH:-}}"
  export REALITY_SERVER_NAME="${reality_server_name:-${REALITY_SERVER_NAME:-}}"
  export REALITY_FINGERPRINT="${reality_fingerprint:-${REALITY_FINGERPRINT:-}}"
  export REALITY_HANDSHAKE_PORT="${reality_handshake_port:-${REALITY_HANDSHAKE_PORT:-443}}"
  export TLS_SERVER_NAME="${tls_server_name:-${TLS_SERVER_NAME:-}}"
  export VMESS_WS_PATH="${vmess_ws_path:-${VMESS_WS_PATH:-/vmess}}"
  export VLESS_WS_PATH="${vless_ws_path:-${VLESS_WS_PATH:-/vless}}"
  export VLESS_XHTTP_PATH="${vless_xhttp_path:-${VLESS_XHTTP_PATH:-}}"
  export VLESS_XHTTP_MODE="${vless_xhttp_mode:-${VLESS_XHTTP_MODE:-auto}}"
  export XRAY_VLESS_ENC="${xray_vless_enc:-${XRAY_VLESS_ENC:-false}}"
  export XRAY_XHTTP_REALITY="${xray_xhttp_reality:-${XRAY_XHTTP_REALITY:-false}}"
  export CDN_HOST_VMESS="${cdn_host_vmess:-${CDN_HOST_VMESS:-}}"
  export CDN_HOST_VLESS_WS="${cdn_host_vless_ws:-${CDN_HOST_VLESS_WS:-}}"
  export CDN_HOST_VLESS_XHTTP="${cdn_host_vless_xhttp:-${CDN_HOST_VLESS_XHTTP:-}}"
  export PROXYIP_VMESS="${proxyip_vmess:-${PROXYIP_VMESS:-}}"
  export PROXYIP_VLESS_WS="${proxyip_vless_ws:-${PROXYIP_VLESS_WS:-}}"
  export PROXYIP_VLESS_XHTTP="${proxyip_vless_xhttp:-${PROXYIP_VLESS_XHTTP:-}}"
  export DOMAIN_SPLIT_DIRECT="${domain_split_direct:-${DOMAIN_SPLIT_DIRECT:-}}"
  export DOMAIN_SPLIT_PROXY="${domain_split_proxy:-${DOMAIN_SPLIT_PROXY:-}}"
  export DOMAIN_SPLIT_BLOCK="${domain_split_block:-${DOMAIN_SPLIT_BLOCK:-}}"
  export OUTBOUND_PROXY_MODE="${outbound_proxy_mode:-${OUTBOUND_PROXY_MODE:-direct}}"
  export OUTBOUND_PROXY_HOST="${outbound_proxy_host:-${OUTBOUND_PROXY_HOST:-}}"
  export OUTBOUND_PROXY_PORT="${outbound_proxy_port:-${OUTBOUND_PROXY_PORT:-}}"
  export OUTBOUND_PROXY_USER="${outbound_proxy_user:-${OUTBOUND_PROXY_USER:-}}"
  export OUTBOUND_PROXY_PASS="${outbound_proxy_pass:-${OUTBOUND_PROXY_PASS:-}}"
  export DIRECT_SHARE_ENDPOINTS="${direct_share_endpoints:-${DIRECT_SHARE_ENDPOINTS:-}}"
  export PROXY_SHARE_ENDPOINTS="${proxy_share_endpoints:-${PROXY_SHARE_ENDPOINTS:-}}"
  export WARP_SHARE_ENDPOINTS="${warp_share_endpoints:-${WARP_SHARE_ENDPOINTS:-}}"

  run_install "$provider" "$profile" "$engine" "$protocols" "false"
}

apply_runtime() {
  ensure_root
  [[ -f /etc/sing-box-deve/runtime.env ]] || die "No runtime state found at /etc/sing-box-deve/runtime.env"

  # shellcheck disable=SC1091
  source /etc/sing-box-deve/runtime.env
  export ARGO_MODE="${argo_mode:-off}"
  export WARP_MODE="${warp_mode:-off}"
  export ROUTE_MODE="${route_mode:-direct}"
  export IP_PREFERENCE="${ip_preference:-auto}"
  export CDN_TEMPLATE_HOST="${cdn_template_host:-}"
  export TLS_MODE="${tls_mode:-self-signed}"
  export ACME_CERT_PATH="${acme_cert_path:-}"
  export ACME_KEY_PATH="${acme_key_path:-}"
  export REALITY_SERVER_NAME="${reality_server_name:-}"
  export REALITY_FINGERPRINT="${reality_fingerprint:-}"
  export REALITY_HANDSHAKE_PORT="${reality_handshake_port:-443}"
  export TLS_SERVER_NAME="${tls_server_name:-}"
  export VMESS_WS_PATH="${vmess_ws_path:-/vmess}"
  export VLESS_WS_PATH="${vless_ws_path:-/vless}"
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
  export OUTBOUND_PROXY_MODE="${outbound_proxy_mode:-direct}"
  export OUTBOUND_PROXY_HOST="${outbound_proxy_host:-}"
  export OUTBOUND_PROXY_PORT="${outbound_proxy_port:-}"
  export OUTBOUND_PROXY_USER="${outbound_proxy_user:-}"
  export OUTBOUND_PROXY_PASS="${outbound_proxy_pass:-}"
  export DIRECT_SHARE_ENDPOINTS="${direct_share_endpoints:-}"
  export PROXY_SHARE_ENDPOINTS="${proxy_share_endpoints:-}"
  export WARP_SHARE_ENDPOINTS="${warp_share_endpoints:-}"

  run_install "${provider:-vps}" "${profile:-lite}" "${engine:-sing-box}" "${protocols:-vless-reality}" "false"
}

doctor() {
  ensure_root
  detect_os
  init_runtime_layout
  log_info "Running diagnostics"
  doctor_system
  fw_detect_backend
  fw_status
  provider_doctor
}
