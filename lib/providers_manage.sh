#!/usr/bin/env bash

provider_list() {
  local mode="${1:-all}"

  if [[ "$mode" == "runtime" || "$mode" == "all" ]]; then
    if [[ -f "${SBD_CONFIG_DIR}/runtime.env" ]]; then
      log_info "$(msg "当前运行时状态:" "Current runtime state:")"
      sbd_print_env_file_redacted "${SBD_CONFIG_DIR}/runtime.env"
    else
      log_warn "$(msg "未找到运行时状态" "No runtime state found")"
    fi
  fi

  if [[ "$mode" == "settings" || "$mode" == "all" ]]; then
    echo
    log_info "$(msg "持久化设置:" "Persistent settings:")"
    show_settings
  fi

  if [[ "$mode" == "nodes" || "$mode" == "all" ]]; then
    print_nodes_with_qr
  fi
}

provider_restart() {
  local target="${1:-all}"

  if [[ "$target" == "core" || "$target" == "all" ]]; then
    if [[ -f "$SBD_SERVICE_FILE" ]]; then
      safe_service_restart
      log_success "$(msg "sing-box-deve 服务已重启" "sing-box-deve service restarted")"
    else
      log_warn "$(msg "服务未安装" "Service not installed")"
    fi
  fi

  if [[ "$target" == "argo" || "$target" == "all" ]]; then
    if [[ -f "$SBD_ARGO_SERVICE_FILE" ]]; then
      sbd_service_restart "sing-box-deve-argo"
      log_success "$(msg "sing-box-deve argo 服务已重启" "sing-box-deve argo service restarted")"
    else
      log_warn "$(msg "未找到 Argo 服务文件" "Argo service file not found")"
    fi
  fi

  if [[ "$target" == "all" ]]; then
    if [[ -f "$SBD_PSIPHON_SERVICE_FILE" ]]; then
      sbd_service_restart "sing-box-deve-psiphon"
      log_success "$(msg "sing-box-deve psiphon 服务已重启" "sing-box-deve psiphon service restarted")"
    fi
  fi
}

provider_logs() {
  ensure_root
  local target="${1:-core}"
  case "$target" in
    core)
      if [[ ! -f "$SBD_SERVICE_FILE" ]]; then
        die "$(msg "核心服务未安装" "Core service is not installed")"
      fi
      sbd_service_logs "sing-box-deve" 120
      ;;
    argo)
      if [[ ! -f "$SBD_ARGO_SERVICE_FILE" ]]; then
        die "$(msg "Argo 服务未安装" "Argo service is not installed")"
      fi
      sbd_service_logs "sing-box-deve-argo" 120
      ;;
    *)
      die "$(msg "不支持的日志目标: $target" "Unsupported logs target: $target")"
      ;;
  esac
}

provider_regen_nodes() {
  ensure_root
  [[ -f "${SBD_CONFIG_DIR}/runtime.env" ]] || die "No runtime state found"
  sbd_load_runtime_env "${SBD_CONFIG_DIR}/runtime.env"
  local runtime_engine="${engine:-sing-box}"
  local runtime_protocols="${protocols:-vless-reality}"
  write_nodes_output "$runtime_engine" "$runtime_protocols"
  log_success "$(msg "节点已重生成: $SBD_NODES_FILE" "Nodes regenerated: $SBD_NODES_FILE")"
}

provider_update() {
  ensure_root
  if [[ ! -f "${SBD_CONFIG_DIR}/runtime.env" ]]; then
    die "$(msg "未检测到已安装运行时" "No installed runtime found")"
  fi

  sbd_load_runtime_env "${SBD_CONFIG_DIR}/runtime.env"
  local engine_bin="${SBD_BIN_DIR}/${engine}"
  local engine_version_file="${SBD_DATA_DIR}/engine-version"
  local rollback_dir="${SBD_STATE_DIR:-/var/lib/sing-box-deve}/core-update-rollback"
  local backup_bin="${rollback_dir}/${engine}.bak"
  local backup_version="${rollback_dir}/engine-version.bak"
  mkdir -p "$rollback_dir"
  if [[ -x "$engine_bin" ]]; then
    cp -p "$engine_bin" "$backup_bin"
  else
    rm -f "$backup_bin"
  fi
  if [[ -f "$engine_version_file" ]]; then
    cp -p "$engine_version_file" "$backup_version"
  else
    rm -f "$backup_version"
  fi

  provider_restore_core_backup() {
    if [[ -f "$backup_bin" ]]; then
      install -m 0755 "$backup_bin" "$engine_bin"
    fi
    if [[ -f "$backup_version" ]]; then
      install -m 0644 "$backup_version" "$engine_version_file"
    fi
  }

  install_engine_binary "$engine"
  if ! safe_service_restart; then
    log_warn "$(msg "核心服务重启失败，正在恢复更新前内核" "Core service restart failed; restoring previous engine binary")"
    provider_restore_core_backup
    safe_service_restart >/dev/null 2>&1 || true
    die "$(msg "核心更新失败，已尝试恢复旧内核" "Core update failed; previous engine restore attempted")"
  fi

  if [[ -f "$SBD_SERVICE_FILE" ]]; then
    local wait_count=0
    while ! sbd_service_is_active "sing-box-deve" && (( wait_count < 15 )); do
      sleep 1
      ((wait_count++))
    done
    if (( wait_count >= 15 )); then
      log_warn "$(msg "核心服务启动超时，正在恢复更新前内核" "Core service start timeout; restoring previous engine binary")"
      provider_restore_core_backup
      safe_service_restart >/dev/null 2>&1 || true
      die "$(msg "核心更新失败，已尝试恢复旧内核" "Core update failed; previous engine restore attempted")"
    else
      log_info "$(msg "核心服务已就绪" "Core service ready")"
    fi
  fi

  if [[ -f "$SBD_ARGO_SERVICE_FILE" ]]; then
    sbd_service_restart "sing-box-deve-argo"
  fi
  provider_psiphon_sync_service
  log_success "$(msg "内核已更新并重启服务" "Engine updated and service restarted")"
  provider_panel
}

provider_kernel_show() {
  local sb_local xr_local sb_remote xr_remote
  if [[ -x "${SBD_BIN_DIR}/sing-box" ]]; then
    sb_local="$("${SBD_BIN_DIR}/sing-box" version 2>/dev/null | awk '/version/{print $NF}' | head -n1)"
  else
    sb_local=""
  fi
  if [[ -x "${SBD_BIN_DIR}/xray" ]]; then
    xr_local="$("${SBD_BIN_DIR}/xray" version 2>/dev/null | awk '/^Xray/{print $2}' | head -n1)"
  else
    xr_local=""
  fi
  sb_remote="$(fetch_latest_release_tag "SagerNet/sing-box" 2>/dev/null || true)"
  xr_remote="$(fetch_latest_release_tag "XTLS/Xray-core" 2>/dev/null || true)"
  log_info "$(msg "sing-box 本地=${sb_local:-n/a} 远端=${sb_remote:-n/a}" "sing-box local=${sb_local:-n/a} remote=${sb_remote:-n/a}")"
  log_info "$(msg "xray 本地=${xr_local:-n/a} 远端=${xr_remote:-n/a}" "xray local=${xr_local:-n/a} remote=${xr_remote:-n/a}")"
}

provider_kernel_set() {
  ensure_root
  local target_engine="$1" target_tag="${2:-latest}"
  validate_engine "$target_engine"

  local has_runtime="false"
  if [[ -f "${SBD_CONFIG_DIR}/runtime.env" ]]; then
    has_runtime="true"
    sbd_load_runtime_env "${SBD_CONFIG_DIR}/runtime.env"
  fi

  install_engine_binary "$target_engine" "$target_tag"

  if [[ "$has_runtime" == "true" ]]; then
    provider_cfg_load_runtime_exports

    assert_engine_protocol_compatibility "$target_engine" "${protocols:-vless-reality}"
    case "$target_engine" in
      sing-box) build_sing_box_config "${protocols:-vless-reality}" ;;
      xray) build_xray_config "${protocols:-vless-reality}" ;;
    esac
    validate_generated_config "$target_engine" "true"
    write_systemd_service "$target_engine"
    write_nodes_output "$target_engine" "${protocols:-vless-reality}"
    persist_runtime_state "${provider:-vps}" "${profile:-lite}" "$target_engine" "${protocols:-vless-reality}"
  fi

  log_success "$(msg "内核已设置: engine=${target_engine} tag=${target_tag}" "Kernel set: engine=${target_engine} tag=${target_tag}")"
}

provider_warp_status() {
  local w4 w6
  w4="$(curl -s4m5 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | awk -F= '/^warp=/{print $2}' | head -n1 || true)"
  w6="$(curl -s6m5 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | awk -F= '/^warp=/{print $2}' | head -n1 || true)"
  log_info "$(msg "warp 状态 ipv4=${w4:-unknown} ipv6=${w6:-unknown}" "warp status ipv4=${w4:-unknown} ipv6=${w6:-unknown}")"
}

provider_warp_register() {
  ensure_root
  local keypair private_key public_key response client_id reserved_hex reserved_dec
  local local_v4 local_v6
  keypair="$(openssl genpkey -algorithm X25519 | openssl pkey -text -noout)"
  private_key="$(echo "$keypair" | awk '/priv:/{flag=1;next}/pub:/{flag=0}flag' | tr -d '[:space:]' | xxd -r -p | base64)"
  public_key="$(echo "$keypair" | awk '/pub:/{flag=1}flag' | tr -d '[:space:]' | xxd -r -p | base64)"
  response="$(curl -fsSL --tlsv1.3 -X POST 'https://api.cloudflareclient.com/v0a2158/reg' -H 'CF-Client-Version: a-7.21-0721' -H 'Content-Type: application/json' -d '{"key":"'"$public_key"'","tos":"'"$(date -u +'%Y-%m-%dT%H:%M:%S.000Z')"'"}')"
  client_id="$(echo "$response" | jq -r '.config.client_id // empty')"
  local_v4="$(echo "$response" | jq -r '.config.interface.addresses.v4 // empty')"
  local_v6="$(echo "$response" | jq -r '.config.interface.addresses.v6 // empty')"
  reserved_hex="$(echo "$client_id" | base64 -d 2>/dev/null | xxd -p -c 256 || true)"
  reserved_dec="$(python3 - <<PY
h='${reserved_hex}'
try:
    vals=[int(h[i:i+2],16) for i in range(0,6,2)]
    print(f'[{vals[0]},{vals[1]},{vals[2]}]')
except Exception:
    print('[0,0,0]')
PY
)"
  [[ -n "$local_v4" ]] || local_v4="172.16.0.2"
  [[ -n "$local_v6" ]] || local_v6="2606:4700:110:876d:4d3c:4206:c90c:6bd0"
  [[ "$local_v4" == */* ]] || local_v4="${local_v4}/32"
  [[ "$local_v6" == */* ]] || local_v6="${local_v6}/128"
  mkdir -p "$SBD_DATA_DIR"
  cat > "${SBD_DATA_DIR}/warp-account.env" <<EOF
WARP_PRIVATE_KEY=${private_key}
WARP_PEER_PUBLIC_KEY=bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=
WARP_RESERVED=${reserved_dec:-[0,0,0]}
WARP_CLIENT_ID=${client_id}
WARP_LOCAL_V4=${local_v4}
WARP_LOCAL_V6=${local_v6}
EOF
  if [[ -n "$client_id" ]]; then
    printf '%s\n' "$client_id" > "${SBD_DATA_DIR}/warp-client-id"
    chmod 600 "${SBD_DATA_DIR}/warp-client-id"
  fi
  chmod 600 "${SBD_DATA_DIR}/warp-account.env"
  log_info "$(msg "WARP 地址 ipv4=${local_v4} ipv6=${local_v6}" "WARP addresses ipv4=${local_v4} ipv6=${local_v6}")"
  log_success "$(msg "WARP 账户已生成: ${SBD_DATA_DIR}/warp-account.env" "WARP account generated: ${SBD_DATA_DIR}/warp-account.env")"
  if declare -F provider_warp_rebuild_runtime_from_account >/dev/null 2>&1; then
    if ! ( provider_warp_rebuild_runtime_from_account "auto" ); then
      log_warn "$(msg "WARP 账户已生成，但自动应用到运行时失败；可稍后执行 warp config 手动应用" "WARP account generated, but auto-apply to runtime failed; run warp config to apply manually later")"
    fi
  fi
}
