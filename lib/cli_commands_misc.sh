#!/usr/bin/env bash

normalize_version_for_compare() {
  local raw="${1#v}" core major minor patch extra
  core="${raw%%[-+]*}"
  IFS=. read -r major minor patch extra <<< "$core"
  [[ -z "${extra:-}" ]] || return 1
  [[ "${major:-}" =~ ^[0-9]+$ ]] || return 1
  [[ "${minor:-0}" =~ ^[0-9]+$ ]] || return 1
  [[ "${patch:-0}" =~ ^[0-9]+$ ]] || return 1
  printf '%d.%d.%d' "$major" "${minor:-0}" "${patch:-0}"
}

version_eq() {
  local left right
  left="$(normalize_version_for_compare "${1:-}")" || return 1
  right="$(normalize_version_for_compare "${2:-}")" || return 1
  [[ "$left" == "$right" ]]
}

version_lt() {
  local left right
  local left_major left_minor left_patch right_major right_minor right_patch
  left="$(normalize_version_for_compare "${1:-}")" || return 1
  right="$(normalize_version_for_compare "${2:-}")" || return 1
  [[ -n "$left" && -n "$right" ]] || return 1
  [[ "$left" == "$right" ]] && return 1
  IFS=. read -r left_major left_minor left_patch <<< "$left"
  IFS=. read -r right_major right_minor right_patch <<< "$right"
  (( left_major < right_major )) && return 0
  (( left_major > right_major )) && return 1
  (( left_minor < right_minor )) && return 0
  (( left_minor > right_minor )) && return 1
  (( left_patch < right_patch ))
}

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
  local script_refreshed="false"

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
      log_warn "$(msg "无法获取远程版本，将直接尝试更新" "Unable to fetch remote version, will attempt update directly")"
      if prompt_yes_no "$(msg "继续更新脚本本体与模块文件吗？" "Continue updating script and module files?")" "Y"; then
        perform_script_self_update
        script_refreshed="true"
        log_success "$(msg "脚本更新完成，请重新执行命令" "Script update completed, please rerun command")"
      else
        log_warn "$(msg "已跳过脚本更新" "Skipped script update")"
      fi
    elif version_eq "$remote_ver" "$local_ver" && [[ "${UPDATE_FORCE:-false}" != "true" ]]; then
      log_info "$(msg "脚本已是最新版本" "Script is already up to date") (${local_ver})"
    else
      log_info "$(msg "本地版本" "Local version"): ${local_ver}"
      log_info "$(msg "远程版本" "Remote version"): ${remote_ver}"
      if [[ "${UPDATE_FORCE:-false}" == "true" && "$remote_ver" == "$local_ver" ]]; then
        log_info "$(msg "已启用强制刷新，将重新同步脚本文件" "Force refresh enabled; script files will be re-synced")"
      fi
      if version_lt "$remote_ver" "$local_ver"; then
        log_warn "$(msg "远程版本低于本地版本，可能是切换了分支或更新源" "Remote version is older than local, possibly due to branch/source change")"
      fi
      if prompt_yes_no "$(msg "更新脚本本体与模块文件吗？" "Update script and module files?")" "Y"; then
        [[ -n "${SBD_ACTIVE_UPDATE_BASE_URL:-}" ]] && log_info "$(msg "更新源" "Update source"): ${SBD_ACTIVE_UPDATE_BASE_URL}"
        perform_script_self_update
        script_refreshed="true"
        log_success "$(msg "脚本更新完成，请重新执行命令" "Script update completed, please rerun command")"
      else
        log_warn "$(msg "已跳过脚本更新" "Skipped script update")"
      fi
    fi
  fi

  if [[ "$script_refreshed" == "true" && "$UPDATE_CORE" == "true" ]]; then
    local next_root next_script
    next_root="$(sbd_choose_authoritative_script_root "$PROJECT_ROOT" || true)"
    [[ -n "$next_root" ]] || next_root="$PROJECT_ROOT"
    next_script="${next_root}/sing-box-deve.sh"
    local -a next_args=("update" "--core")
    [[ "${AUTO_YES:-false}" == "true" ]] && next_args+=("--yes")
    [[ -x "$next_script" || -f "$next_script" ]] || die "$(msg "脚本已更新，但找不到新入口: ${next_script}；请重新执行 sb update --core" "Script updated but new entrypoint is missing: ${next_script}; rerun sb update --core")"
    log_info "$(msg "脚本已刷新，将使用新脚本继续核心更新: ${next_script}" "Script refreshed; continuing core update with refreshed script: ${next_script}")"
    exec bash "$next_script" "${next_args[@]}"
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
