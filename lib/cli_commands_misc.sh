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

  if [[ "${UPDATE_ROLLBACK:-false}" == "true" ]]; then
    log_warn "$(msg "正在执行脚本回滚..." "Performing script rollback...")"
    perform_script_rollback
    log_success "$(msg "回滚完成，请重新执行命令验证" "Rollback completed, please rerun command to verify")"
    return 0
  fi

  if [[ "$UPDATE_SCRIPT" == "true" ]]; then
    local local_ver remote_ver
    local_ver="$(current_script_version)"
    remote_ver="$(fetch_remote_script_version "${UPDATE_SOURCE:-auto}" 2>/dev/null || true)"

    if [[ -z "$remote_ver" ]]; then
      log_warn "$(msg "无法获取远程版本，跳过脚本更新" "Unable to fetch remote version, skipping script update")"
    elif [[ "$remote_ver" == "$local_ver" ]]; then
      log_info "$(msg "脚本已是最新版本" "Script is already up to date") (${local_ver})"
    else
      log_info "$(msg "本地版本" "Local version"): ${local_ver}"
      log_info "$(msg "远程版本" "Remote version"): ${remote_ver}"
      if [[ "$remote_ver" < "$local_ver" ]]; then
        log_warn "$(msg "远程版本低于本地版本，可能是切换了分支或更新源" "Remote version is older than local, possibly due to branch/source change")"
      fi
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

doctor() {
  ensure_root
  detect_os
  init_runtime_layout
  log_info "$(msg "开始执行诊断检查" "Running diagnostics")"
  doctor_system
  fw_detect_backend
  fw_status
  provider_doctor
}
