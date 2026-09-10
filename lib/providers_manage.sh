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
  sbd_with_mutation_lock provider_restart_unlocked "$@"
}

provider_restart_unlocked() {
  local target="${1:-all}"

  if [[ "$target" == "core" || "$target" == "all" ]]; then
    if [[ -f "$SBD_SERVICE_FILE" ]] || sbd_service_unit_exists "sing-box-deve"; then
      safe_service_restart
      log_success "$(msg "sing-box-deve 服务已重启" "sing-box-deve service restarted")"
    else
      log_warn "$(msg "服务未安装" "Service not installed")"
    fi
  fi

  if [[ "$target" == "argo" || "$target" == "all" ]]; then
    if [[ -f "$SBD_ARGO_SERVICE_FILE" ]] || sbd_service_unit_exists "sing-box-deve-argo"; then
      local argo_exec=""
      if [[ -f "$SBD_ARGO_EXEC_FILE" ]]; then
        argo_exec="$(<"$SBD_ARGO_EXEC_FILE")"
      fi
      detect_init_system
      if [[ "$SBD_INIT_SYSTEM" == "nohup" && -z "$argo_exec" ]]; then
        if ! argo_exec="$(argo_restore_nohup_exec_command)"; then
          log_error "$(msg "无法从 runtime.env 迁移旧版 Argo nohup 启动命令" \
            "Unable to migrate legacy Argo nohup command from runtime.env")"
          return 1
        fi
        log_info "$(msg "已从 runtime.env 迁移旧版 Argo nohup 启动命令" \
          "Migrated legacy Argo nohup command from runtime.env")"
      fi
      sbd_service_restart "sing-box-deve-argo" "$argo_exec"
      sbd_service_wait_active "sing-box-deve-argo" 10
      log_success "$(msg "sing-box-deve argo 服务已重启" "sing-box-deve argo service restarted")"
    else
      log_warn "$(msg "未找到 Argo 服务文件" "Argo service file not found")"
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
        log_warn "$(msg "Argo 服务未安装" "Argo service is not installed")"
        return 0
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
  sbd_load_runtime_env "${SBD_CONFIG_DIR}/runtime.env" || return 1
  local runtime_engine="${engine:-sing-box}"
  local runtime_protocols="${protocols:-vless-reality}"
  write_nodes_output "$runtime_engine" "$runtime_protocols"
  log_success "$(msg "节点已重生成: $SBD_NODES_FILE" "Nodes regenerated: $SBD_NODES_FILE")"
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
  sbd_with_mutation_lock sbd_transaction_run kernel-set provider_kernel_set_unlocked "$@"
}

provider_kernel_set_unlocked() {
  ensure_root
  local target_engine="$1" target_tag="${2:-latest}" has_runtime=false runtime_protocols=""
  local candidate_root="$SBD_ACTIVE_TRANSACTION/candidate"
  validate_engine "$target_engine" || return 1
  if [[ -f "$SBD_CONFIG_DIR/runtime.env" ]]; then
    has_runtime=true
    provider_cfg_load_runtime_exports || return 1
    runtime_protocols="$protocols"
    assert_engine_protocol_compatibility "$target_engine" "$runtime_protocols" || return 1
    sbd_export_protocol_ports_from_engine "$engine" "$runtime_protocols" || return 1
  fi
  init_runtime_layout || return 1
  provider_core_candidate_install "$target_engine" "$candidate_root" "$target_tag" || return 1
  if [[ "$has_runtime" == true ]]; then
    provider_core_candidate_build "$target_engine" "$runtime_protocols" "$candidate_root" || return 1
  fi
  sbd_transaction_phase "$SBD_ACTIVE_TRANSACTION" committing || return 1
  provider_core_candidate_binary_commit "$target_engine" "$candidate_root" || return 1
  if [[ "$has_runtime" == true ]]; then
    provider_core_candidate_data_commit "$candidate_root" || return 1
    provider_core_candidate_commit "$target_engine" "$candidate_root" || return 1
    write_systemd_service "$target_engine" || return 1
    provider_core_health_check "$target_engine" "" || return 1
    configure_argo_tunnel "$runtime_protocols" "$target_engine" || return 1
    write_nodes_output "$target_engine" "$runtime_protocols" || return 1
    persist_runtime_state "${provider:?Runtime provider missing}" "${profile:?Runtime profile missing}" "$target_engine" "$runtime_protocols" || return 1
  fi
  log_success "Kernel set: engine=${target_engine} tag=${target_tag}"
}

provider_warp_status() {
  local w4 w6
  w4="$(curl -s4m5 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | awk -F= '/^warp=/{print $2}' | head -n1 || true)"
  w6="$(curl -s6m5 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | awk -F= '/^warp=/{print $2}' | head -n1 || true)"
  log_info "$(msg "warp 状态 ipv4=${w4:-unknown} ipv6=${w6:-unknown}" "warp status ipv4=${w4:-unknown} ipv6=${w6:-unknown}")"
}

provider_warp_register() {
  sbd_with_mutation_lock sbd_transaction_run config-change provider_warp_register_unlocked
}

provider_warp_register_unlocked() {
  provider_warp_register_account || return 1
  provider_warp_rebuild_runtime_from_account "auto" || return 1
}

provider_warp_register_account() {
  ensure_root
  local keypair encoded private_key public_key response client_id reserved_dec
  local local_v4 local_v6
  keypair="$(sbd_run_deadline 30 openssl genpkey -algorithm X25519 | sbd_run_deadline 30 openssl pkey -text -noout)" || return 1
  encoded="$(printf '%s' "$keypair" | python3 -c '
import base64, sys
parts = sys.stdin.read().split("priv:", 1)[1].split("pub:", 1)
keys = [bytes.fromhex(p.replace(":", " ")) for p in parts]
assert len(keys) == 2 and all(len(k) == 32 for k in keys)
print(" ".join(base64.b64encode(k).decode() for k in keys))')" || return 1
  read -r private_key public_key <<< "$encoded"
  response="$(sbd_http_small --tlsv1.3 -X POST 'https://api.cloudflareclient.com/v0a2158/reg' -H 'CF-Client-Version: a-7.21-0721' -H 'Content-Type: application/json' -d '{"key":"'"$public_key"'","tos":"'"$(date -u +'%Y-%m-%dT%H:%M:%S.000Z')"'"}')" || return 1
  client_id="$(echo "$response" | jq -er '.config.client_id | strings | select(length > 0)')" || return 1
  local_v4="$(echo "$response" | jq -er '.config.interface.addresses.v4 | strings | select(length > 0)')" || return 1
  local_v6="$(echo "$response" | jq -er '.config.interface.addresses.v6 | strings | select(length > 0)')" || return 1
  reserved_dec="$(python3 -c 'import base64,json,sys; b=base64.b64decode(sys.argv[1],validate=True); assert len(b)==3; print(json.dumps(list(b)))' "$client_id")" || return 1
  [[ "$local_v4" == */* ]] || local_v4="${local_v4}/32"
  [[ "$local_v6" == */* ]] || local_v6="${local_v6}/128"
  provider_warp_account_write "$private_key" 'bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=' "$reserved_dec" "$local_v4" "$local_v6" "$client_id" || return 1
  log_info "$(msg "WARP 地址 ipv4=${local_v4} ipv6=${local_v6}" "WARP addresses ipv4=${local_v4} ipv6=${local_v6}")"
  log_success "$(msg "WARP 账户已生成: ${SBD_DATA_DIR}/warp-account.env" "WARP account generated: ${SBD_DATA_DIR}/warp-account.env")"
}
