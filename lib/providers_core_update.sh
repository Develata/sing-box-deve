#!/usr/bin/env bash
# shellcheck disable=SC2030,SC2031

provider_core_rollback_dir() {
  printf '%s/core-update-rollback' "${SBD_STATE_DIR:-/var/lib/sing-box-deve}"
}

provider_core_backup_one() {
  local source_file="$1" backup_name="$2" rollback_dir="$3"
  rm -f "${rollback_dir}/${backup_name}.bak" "${rollback_dir}/${backup_name}.missing"
  if [[ -f "$source_file" ]]; then
    cp -p "$source_file" "${rollback_dir}/${backup_name}.bak"
  else
    : > "${rollback_dir}/${backup_name}.missing"
  fi
}

provider_core_restore_one() {
  local target_file="$1" backup_name="$2" rollback_dir="$3" mode="$4"
  if [[ -f "${rollback_dir}/${backup_name}.bak" ]]; then
    install -m "$mode" "${rollback_dir}/${backup_name}.bak" "$target_file"
  elif [[ -f "${rollback_dir}/${backup_name}.missing" ]]; then
    rm -f "$target_file"
  fi
}

provider_core_backup_prepare() {
  local target_engine="$1" rollback_dir
  rollback_dir="$(provider_core_rollback_dir)"
  mkdir -p "$rollback_dir"
  rm -f "${rollback_dir}/install-reused-existing"
  provider_core_backup_one "${SBD_BIN_DIR}/${target_engine}" "${target_engine}" "$rollback_dir"
  provider_core_backup_one "${SBD_DATA_DIR}/engine-version" engine-version "$rollback_dir"
  provider_core_backup_one "${SBD_CONFIG_DIR}/config.json" config.json "$rollback_dir"
  provider_core_backup_one "${SBD_CONFIG_DIR}/xray-config.json" xray-config.json "$rollback_dir"
}

provider_core_backup_restore() {
  local target_engine="$1" rollback_dir
  rollback_dir="$(provider_core_rollback_dir)"
  provider_core_restore_one "${SBD_BIN_DIR}/${target_engine}" "${target_engine}" "$rollback_dir" 0755
  provider_core_restore_one "${SBD_DATA_DIR}/engine-version" engine-version "$rollback_dir" 0644
  provider_core_restore_one "${SBD_CONFIG_DIR}/config.json" config.json "$rollback_dir" 0600
  provider_core_restore_one "${SBD_CONFIG_DIR}/xray-config.json" xray-config.json "$rollback_dir" 0600
}

provider_install_engine_safely() {
  local target_engine="$1" target_tag="${2:-latest}" rollback_dir install_reused_file
  rollback_dir="$(provider_core_rollback_dir)"
  install_reused_file="${rollback_dir}/install-reused-existing"
  provider_core_backup_prepare "$target_engine"
  if ! (export SBD_ENGINE_INSTALL_REUSED_EXISTING_FILE="$install_reused_file"; install_engine_binary "$target_engine" "$target_tag"); then
    log_warn "$(msg "核心安装失败，正在恢复更新前内核与配置" "Engine install failed; restoring previous binary and config")"
    provider_core_backup_restore "$target_engine"
    return 1
  fi
  [[ ! -f "$install_reused_file" ]] || return 2
  return 0
}

provider_core_candidate_build() {
  local target_engine="$1" protocols_csv="$2" candidate_root="$3"
  (
    SBD_CONFIG_DIR="${candidate_root}/config"
    SBD_BIN_DIR="${candidate_root}/bin"
    mkdir -p "$SBD_CONFIG_DIR"
    case "$target_engine" in
      sing-box) build_sing_box_config "$protocols_csv" ;;
      xray) build_xray_config "$protocols_csv" ;;
      *) die "Unsupported engine for candidate config: ${target_engine}" ;;
    esac
    validate_generated_config "$target_engine" false
  )
}

provider_core_candidate_install() {
  local target_engine="$1" candidate_root="$2" target_tag="${3:-latest}"
  (
    SBD_BIN_DIR="${candidate_root}/bin"
    SBD_DATA_DIR="${candidate_root}/data"
    SBD_CACHE_DIR="${candidate_root}/cache"
    mkdir -p "$SBD_BIN_DIR" "$SBD_DATA_DIR" "$SBD_CACHE_DIR"
    install_engine_binary "$target_engine" "$target_tag"
    [[ -x "${SBD_BIN_DIR}/${target_engine}" ]]
  )
}

provider_core_candidate_binary_commit() {
  local target_engine="$1" candidate_root="$2" candidate live tmp
  candidate="${candidate_root}/bin/${target_engine}"
  live="${SBD_BIN_DIR}/${target_engine}"
  [[ -x "$candidate" ]] || return 1
  tmp="$(mktemp "${live}.candidate.XXXXXX")"
  cp -p "$candidate" "$tmp"
  chmod 0755 "$tmp"
  mv -f "$tmp" "$live"
  if [[ -s "${candidate_root}/data/engine-version" ]]; then
    tmp="$(mktemp "${SBD_DATA_DIR}/engine-version.candidate.XXXXXX")"
    cp -p "${candidate_root}/data/engine-version" "$tmp"
    sbd_commit_file_with_backups "${SBD_DATA_DIR}/engine-version" "$tmp" 0644
  fi
}

provider_core_candidate_commit() {
  local target_engine="$1" candidate_root="$2" name live candidate tmp
  case "$target_engine" in
    sing-box) name="config.json" ;;
    xray) name="xray-config.json" ;;
    *) return 1 ;;
  esac
  candidate="${candidate_root}/config/${name}"
  live="${SBD_CONFIG_DIR}/${name}"
  [[ -s "$candidate" ]] || return 1
  tmp="$(mktemp "${live}.candidate.XXXXXX")"
  cp -p "$candidate" "$tmp"
  sbd_commit_file_with_backups "$live" "$tmp" 600
}

sbd_service_main_pid() {
  local svc_name="$1" pid_file pid=""
  detect_init_system >&2
  case "$SBD_INIT_SYSTEM" in
    systemd) pid="$(systemctl show -p MainPID --value "${svc_name}.service" 2>/dev/null || true)" ;;
    openrc)
      pid_file="/run/${svc_name}.pid"
      if [[ -r "$pid_file" ]]; then read -r pid < "$pid_file" || true; fi
      ;;
    nohup)
      pid_file="${SBD_RUNTIME_DIR}/${svc_name}.pid"
      if [[ -r "$pid_file" ]]; then read -r pid < "$pid_file" || true; fi
      ;;
  esac
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] && printf '%s\n' "$pid"
}

provider_core_health_check() {
  local target_engine="$1" old_pid="${2:-}" new_pid binary_path process_exe
  sbd_service_wait_active "sing-box-deve" 15 || return 1
  new_pid="$(sbd_service_main_pid "sing-box-deve")"
  [[ -n "$new_pid" ]] || { log_error "Unable to resolve core service PID"; return 1; }
  if [[ -n "$old_pid" && "$new_pid" == "$old_pid" ]]; then
    log_error "Core service PID did not change after restart: ${new_pid}"
    return 1
  fi
  binary_path="$(readlink -f "${SBD_BIN_DIR}/${target_engine}" 2>/dev/null || true)"
  if [[ -e "/proc/${new_pid}/exe" ]]; then
    process_exe="$(readlink -f "/proc/${new_pid}/exe" 2>/dev/null || true)"
    [[ "$process_exe" == "$binary_path" ]] || {
      log_error "Running core does not match installed binary: ${process_exe:-unknown}"
      return 1
    }
  fi
  return 0
}

provider_core_rollback_after_failure() {
  local target_engine="$1" reason="$2"
  log_warn "$reason"
  provider_core_backup_restore "$target_engine"
  if ! safe_service_restart || ! provider_core_health_check "$target_engine" ""; then
    log_error "Rollback restored files but the previous core did not recover"
    return 1
  fi
  return 0
}

provider_update() {
  ensure_root
  [[ -f "${SBD_CONFIG_DIR}/runtime.env" ]] || die "$(msg "未检测到已安装运行时" "No installed runtime found")"
  provider_cfg_load_runtime_exports
  validate_feature_modes
  local target_engine="${engine:-sing-box}" runtime_protocols="${protocols:-vless-reality}"
  local candidate_root old_pid
  old_pid="$(sbd_service_main_pid "sing-box-deve")"
  candidate_root="$(mktemp -d "${SBD_STATE_DIR}/core-update-candidate.XXXXXX")"
  provider_core_backup_prepare "$target_engine"
  if ! provider_core_candidate_install "$target_engine" "$candidate_root" latest; then
    rm -rf "$candidate_root"
    die "Core candidate download or installation failed; live service was not changed"
  fi
  if ! provider_core_candidate_build "$target_engine" "$runtime_protocols" "$candidate_root"; then
    rm -rf "$candidate_root"
    die "Candidate config validation failed; live service was not changed"
  fi
  if ! provider_core_candidate_binary_commit "$target_engine" "$candidate_root"; then
    rm -rf "$candidate_root"
    provider_core_backup_restore "$target_engine"
    die "Candidate binary commit failed; live files were restored"
  fi
  if ! provider_core_candidate_commit "$target_engine" "$candidate_root"; then
    rm -rf "$candidate_root"
    provider_core_backup_restore "$target_engine"
    die "Candidate config commit failed; live files were restored without restarting the running service"
  fi
  rm -rf "$candidate_root"

  if ! safe_service_restart || ! provider_core_health_check "$target_engine" "$old_pid"; then
    provider_core_rollback_after_failure "$target_engine" "New core failed runtime health check; rolling back binary and config" || true
    die "Core update failed; previous binary and config restore attempted"
  fi
  if [[ -f "$SBD_ARGO_SERVICE_FILE" ]]; then
    provider_restart argo || log_warn "Argo sidecar restart failed after successful core update"
  fi
  log_success "$(msg "内核与配置已事务化更新" "Engine and config updated transactionally")"
  provider_panel
}
