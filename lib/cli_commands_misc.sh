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
  if [[ "$UPDATE_ROLLBACK" == true ]]; then perform_script_rollback; return $?; fi
  if [[ "$UPDATE_SCRIPT" == true ]]; then
    prompt_yes_no "Install a verified script release?" N || return 1
    perform_script_self_update || return 1
    if [[ "$UPDATE_CORE" == true ]]; then
      local -a next_args=(update --core)
      [[ "$AUTO_YES" != true ]] || next_args+=(--yes)
      exec bash "$SBD_INSTALL_DIR/current/sing-box-deve.sh" "${next_args[@]}"
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
