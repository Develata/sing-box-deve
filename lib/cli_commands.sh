#!/usr/bin/env bash

show_version() {
  local local_ver remote_ver
  local_ver="$(current_script_version)"
  remote_ver="$(fetch_remote_script_version 2>/dev/null || true)"

  log_info "$(msg "当前脚本版本" "Current script version"): ${local_ver}"
  if [[ -n "$remote_ver" ]]; then
    log_info "$(msg "远程最新版本" "Remote latest version"): ${remote_ver}"
  else
    log_warn "$(msg "无法获取远程版本（可设置 SBD_UPDATE_BASE_URL）" "Unable to fetch remote version (set SBD_UPDATE_BASE_URL if needed)")"
  fi
}

update_command() {
  parse_update_args "$@"

  if [[ "$UPDATE_SCRIPT" == "true" ]]; then
    local local_ver remote_ver
    local_ver="$(current_script_version)"
    remote_ver="$(fetch_remote_script_version 2>/dev/null || true)"

    if [[ -n "$remote_ver" && "$remote_ver" == "$local_ver" ]]; then
      log_info "$(msg "脚本已是最新版本" "Script is already up to date") (${local_ver})"
    else
      if prompt_yes_no "$(msg "更新脚本本体与模块文件吗？" "Update script and module files?")" "Y"; then
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

  export ARGO_MODE ARGO_DOMAIN ARGO_TOKEN WARP_MODE ROUTE_MODE OUTBOUND_PROXY_MODE OUTBOUND_PROXY_HOST OUTBOUND_PROXY_PORT OUTBOUND_PROXY_USER OUTBOUND_PROXY_PASS

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
  export OUTBOUND_PROXY_MODE="${outbound_proxy_mode:-${OUTBOUND_PROXY_MODE:-direct}}"
  export OUTBOUND_PROXY_HOST="${outbound_proxy_host:-${OUTBOUND_PROXY_HOST:-}}"
  export OUTBOUND_PROXY_PORT="${outbound_proxy_port:-${OUTBOUND_PROXY_PORT:-}}"
  export OUTBOUND_PROXY_USER="${outbound_proxy_user:-${OUTBOUND_PROXY_USER:-}}"
  export OUTBOUND_PROXY_PASS="${outbound_proxy_pass:-${OUTBOUND_PROXY_PASS:-}}"

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
  export OUTBOUND_PROXY_MODE="${outbound_proxy_mode:-direct}"
  export OUTBOUND_PROXY_HOST="${outbound_proxy_host:-}"
  export OUTBOUND_PROXY_PORT="${outbound_proxy_port:-}"
  export OUTBOUND_PROXY_USER="${outbound_proxy_user:-}"
  export OUTBOUND_PROXY_PASS="${outbound_proxy_pass:-}"

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
