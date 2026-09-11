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
  log_info "$(msg "当前脚本版本" "Current script version"): ${local_ver}"
  sbd_show_script_source
  remote_ver="$(fetch_remote_script_version "auto" 2>/dev/null || true)"
  if [[ -n "$remote_ver" ]]; then
    log_info "$(msg "远程最新版本" "Remote latest version"): ${remote_ver}"
    [[ -n "${SBD_ACTIVE_UPDATE_BASE_URL:-}" ]] && log_info "$(msg "更新源" "Update source"): ${SBD_ACTIVE_UPDATE_BASE_URL}"
  else
    log_warn "$(msg "无法获取远程版本（可设置 SBD_UPDATE_BASE_URL）" "Unable to fetch remote version (set SBD_UPDATE_BASE_URL if needed)")"
  fi
  return 0
}

update_command() {
  parse_update_args "$@"
  if [[ -n "$UPDATE_BIND_GIT" ]]; then
    log_warn "$(msg "sb 将执行固定 Git 目录中的代码；能修改该目录的用户也能修改这些管理命令。" "sb will execute the fixed Git checkout; its owner can modify these management commands.")"
    prompt_yes_no "$(msg "绑定该 Git 目录？" "Bind this Git directory?") $UPDATE_BIND_GIT" N || return 1
    sbd_with_mutation_lock sbd_transaction_run script-update sbd_bind_git_source "$UPDATE_BIND_GIT"
    return $?
  fi
  if [[ "$UPDATE_CHECK_SOURCE" == true ]]; then sbd_check_script_source; return $?; fi
  if [[ "$UPDATE_ROLLBACK" == true ]]; then perform_script_rollback; return $?; fi
  if [[ "$UPDATE_SCRIPT" == true ]]; then
    if sbd_source_is_git && [[ "$UPDATE_RELEASE" == false ]]; then
      sbd_check_script_source || return 1
      log_info "$(msg "Git 模式请手动 git pull；安装 Release 并解除绑定请使用 update --release。" "In Git mode, run git pull manually; use update --release to install a Release and remove the binding.")"
    else
      prompt_yes_no "$(msg "安装完整 Release（解除已有 Git 绑定）？" "Install a verified script Release (remove any Git binding)?")" N || return 1
      perform_script_self_update || return 1
      unset SBD_GIT_SOURCE_STAMP SBD_GIT_SOURCE_UID
    fi
    if [[ "$UPDATE_CORE" == true ]]; then
      local next_root
      next_root="$(sbd_read_runtime_script_root)" || return 1
      local -a next_args=(update --core)
      [[ "$AUTO_YES" != true ]] || next_args+=(--yes)
      exec bash "$next_root/sing-box-deve.sh" "${next_args[@]}"
    fi
  fi
  if [[ "$UPDATE_CORE" == true ]]; then
    prompt_yes_no "Update installed core?" N || return 1
    provider_update
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
          set_setting "$key" "$value" || return 1
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
  log_info "$(msg "开始执行诊断检查" "Running diagnostics")"
  doctor_system
  fw_detect_backend
  fw_status
  provider_doctor
}
