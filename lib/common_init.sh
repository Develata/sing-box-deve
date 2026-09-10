#!/usr/bin/env bash
# common_init.sh — Privilege detection, init system detection, user-mode paths
# shellcheck disable=SC2034

# Global flags set by detect_privilege_level / detect_init_system
SBD_USER_MODE="false"
SBD_INIT_SYSTEM=""  # systemd | openrc | nohup

detect_privilege_level() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    SBD_USER_MODE="false"
    return 0
  fi

  # Non-root — switch to user-mode paths
  SBD_USER_MODE="true"
  init_user_mode_paths
}

init_user_mode_paths() {
  local user_home="${HOME:?HOME is required}"
  local base="${user_home}/sing-box-deve"

  SBD_STATE_DIR="${base}/state"
  SBD_CONFIG_DIR="${base}/config"
  SBD_RUNTIME_DIR="${base}/run"
  SBD_RULES_FILE="${SBD_STATE_DIR}/firewall-rules.db"
  SBD_CONTEXT_FILE="${SBD_STATE_DIR}/context.env"
  SBD_FW_SNAPSHOT_FILE="${SBD_STATE_DIR}/firewall-rules.snapshot"
  SBD_CFG_LOCK_FILE="${SBD_STATE_DIR}/cfg.lock"
  CONFIG_SNAPSHOT_FILE="${SBD_CONFIG_DIR}/config.yaml"
  SBD_SETTINGS_FILE="${SBD_CONFIG_DIR}/settings.conf"
  SBD_INSTALL_DIR="${base}"
  SBD_BIN_DIR="${base}/bin"
  SBD_DATA_DIR="${base}/data"
  SBD_CACHE_DIR="${base}/cache"
  SBD_NODES_FILE="${SBD_DATA_DIR}/nodes.txt"
  SBD_NODES_BASE_FILE="${SBD_DATA_DIR}/nodes-base.txt"
  SBD_SUB_FILE="${SBD_DATA_DIR}/nodes-sub.txt"
  SBD_NODE_MODEL_FILE="${SBD_DATA_DIR}/nodes-model.json"
  SBD_ARGO_TOKEN_FILE="${SBD_DATA_DIR}/argo-token"
  SBD_ARGO_EXEC_FILE="${SBD_DATA_DIR}/argo-exec"

  # Service files — set but not necessarily used in nohup mode
  SBD_SERVICE_FILE="${base}/service/sing-box-deve.service"
  SBD_ARGO_SERVICE_FILE="${base}/service/sing-box-deve-argo.service"
  SBD_WARP_SOCKS_SERVICE_FILE="${base}/service/sing-box-deve-warp-socks5.service"
  SBD_WARP_SOCKS_CONFIG_FILE="${SBD_CONFIG_DIR}/warp-socks5.json"
  SBD_WARP_SOCKS_PORT_FILE="${SBD_DATA_DIR}/warp-socks5-port"
  SBD_FW_REPLAY_SERVICE_FILE="${base}/service/sing-box-deve-fw-replay.service"
}

detect_init_system() {
  # Already detected?
  [[ -n "$SBD_INIT_SYSTEM" ]] && return 0

  if [[ "${SBD_USER_MODE:-false}" == true ]]; then SBD_INIT_SYSTEM="nohup"; return 0; fi

  # Check systemd first (most common)
  if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system || -d /sys/fs/cgroup/systemd ]]; then
    SBD_INIT_SYSTEM="systemd"
    return 0
  fi

  # Check OpenRC (Alpine, Gentoo)
  if command -v rc-service >/dev/null 2>&1 && command -v rc-update >/dev/null 2>&1; then
    SBD_INIT_SYSTEM="openrc"
    return 0
  fi

  # Fallback — nohup + crontab
  SBD_INIT_SYSTEM="nohup"
  log_warn "$(msg "未检测到 systemd 或 OpenRC，将使用 nohup+crontab 后备方案" \
               "No systemd or OpenRC detected, using nohup+crontab fallback")"
}

sbd_systemd_daemon_reload() {
  local required="${1:-false}" context="${2:-systemd daemon-reload}"
  local rc output
  if output="$(sbd_service_op systemctl daemon-reload 2>&1)"; then
    return 0
  else
    rc=$?
  fi

  [[ -n "$output" ]] && log_warn "$output"
  log_warn "$(msg \
    "${context} 失败。若提示 /run/systemd 空间不足，请清理 /run 或重启 VPS 后重试；当前脚本会继续处理可继续的步骤。" \
    "${context} failed. If /run/systemd is out of space, clean /run or reboot the VPS and retry; continuing where possible.")"
  [[ "$required" == "true" ]] && return "$rc"
  return 0
}

# Write an OpenRC init script for the given service name and exec command
write_openrc_service() {
  local svc_name="$1"
  local exec_cmd="$2"
  local log_file="${3:-/var/log/${svc_name}.log}"
  local svc_file="${SBD_OPENRC_DIR:-/etc/init.d}/${svc_name}" svc_tmp

  if [[ "$SBD_USER_MODE" == "true" ]]; then
    svc_file="${SBD_INSTALL_DIR}/service/${svc_name}.openrc"
    log_file="${SBD_DATA_DIR}/${svc_name}.log"
    log_warn "$(msg "非 root 模式下 OpenRC 服务仅生成脚本，需手动安装" \
                 "User mode: OpenRC script generated but needs manual install")"
  fi

  mkdir -p "$(dirname "$svc_file")" || return 1
  svc_tmp="$(mktemp "${svc_file}.tmp.XXXXXX")" || return 1
  cat > "$svc_tmp" <<EOF
#!/sbin/openrc-run
# Managed by sing-box-deve: service-v1

name="${svc_name}"
description="sing-box-deve ${svc_name} service"
command="${exec_cmd%% *}"
command_args="${exec_cmd#* }"
command_background=true
pidfile="/run/${svc_name}.pid"
output_log="${log_file}"
error_log="${log_file}"

depend() {
  need net
  after firewall
}
EOF
  chmod +x "$svc_tmp" || return 1
  sbd_host_file_publish "$svc_file" "$svc_tmp" || return 1

  if [[ "$SBD_USER_MODE" == "false" ]]; then
    sbd_service_op rc-update add "$svc_name" default >/dev/null || return 1
    sbd_service_op rc-service "$svc_name" restart || return 1
    sbd_service_wait_active "$svc_name" 10
  fi
}

# Generic service operations that dispatch to the correct init system
sbd_service_enable_and_start() {
  local svc_name="$1"
  local exec_cmd="$2"

  detect_init_system

  case "$SBD_INIT_SYSTEM" in
    systemd)
      sbd_systemd_daemon_reload true "systemd daemon-reload" || return 1
      sbd_service_op systemctl enable "${svc_name}.service" >/dev/null 2>&1 || return 1
      sbd_service_op systemctl restart "${svc_name}.service"
      ;;
    openrc)
      write_openrc_service "$svc_name" "$exec_cmd"
      ;;
    nohup)
      nohup_start_service "$svc_name" "$exec_cmd"
      ;;
  esac
}

sbd_service_stop() {
  local svc_name="$1" load_state
  detect_init_system || return 1
  case "$SBD_INIT_SYSTEM" in
    systemd)
      load_state="$(sbd_service_op systemctl show -p LoadState --value "${svc_name}.service")" || return 1
      [[ "$load_state" != not-found ]] || return 0
      sbd_service_op systemctl stop "${svc_name}.service" || return 1
      sbd_service_op systemctl disable "${svc_name}.service" || return 1 ;;
    openrc)
      [[ -f "/etc/init.d/$svc_name" ]] || return 0
      sbd_service_op rc-service "$svc_name" stop || return 1
      sbd_service_op rc-update del "$svc_name" default || return 1 ;;
    nohup) nohup_stop_service "$svc_name" ;;
    *) return 1 ;;
  esac
}

sbd_service_restart() {
  local svc_name="$1"
  local exec_cmd="${2:-}"

  detect_init_system

  case "$SBD_INIT_SYSTEM" in
    systemd)
      sbd_service_op systemctl restart "${svc_name}.service"
      ;;
    openrc)
      sbd_service_op rc-service "$svc_name" restart
      ;;
    nohup)
      if [[ -n "$exec_cmd" ]]; then
        nohup_start_service "$svc_name" "$exec_cmd"
      else
        log_error "$(msg "nohup 模式下重启需要完整命令" "nohup mode restart requires full command")"
        return 1
      fi
      ;;
  esac
}

sbd_service_wait_active() {
  local svc_name="$1" timeout_seconds="${2:-10}" deadline remaining
  sbd_positive_seconds "$timeout_seconds" || return 2
  deadline=$((SECONDS + timeout_seconds))
  while (( SECONDS < deadline )); do
    remaining=$((deadline - SECONDS))
    if SBD_SERVICE_TIMEOUT="$remaining" sbd_service_is_active "$svc_name"; then
      return 0
    fi
    (( SECONDS < deadline )) && sleep 1
  done
  log_error "Service failed health check: ${svc_name}"
  return 1
}

sbd_service_is_active() {
  local svc_name="$1"

  detect_init_system

  case "$SBD_INIT_SYSTEM" in
    systemd)
      sbd_service_op systemctl is-active --quiet "${svc_name}.service"
      ;;
    openrc)
      sbd_service_op rc-service "$svc_name" status 2>/dev/null | grep -q "started"
      ;;
    nohup)
      nohup_is_active "$svc_name"
      ;;
  esac
}

sbd_service_logs() {
  local svc_name="$1"
  local lines="${2:-120}"

  detect_init_system

  case "$SBD_INIT_SYSTEM" in
    systemd)
      sbd_service_op journalctl -u "${svc_name}.service" -n "$lines" --no-pager || true
      ;;
    openrc|nohup)
      local log_file="${SBD_DATA_DIR}/${svc_name}.log"
      if [[ -f "$log_file" ]]; then
        tail -n "$lines" "$log_file"
      else
        log_warn "$(msg "未找到日志文件: ${log_file}" "Log file not found: ${log_file}")"
      fi
      ;;
  esac
}

# Daemon-reload (systemd only; no-op on other init systems)
sbd_service_daemon_reload() {
  detect_init_system
  if [[ "$SBD_INIT_SYSTEM" == "systemd" ]]; then
    sbd_systemd_daemon_reload true "systemd daemon-reload" || return 1
  fi
}

# Check if a service unit/config exists
sbd_service_unit_exists() {
  local svc_name="$1"
  detect_init_system
  case "$SBD_INIT_SYSTEM" in
    systemd)  sbd_service_op systemctl list-unit-files "${svc_name}.service" 2>/dev/null | grep -q "^${svc_name}.service" ;;
    openrc)   [[ -f "/etc/init.d/${svc_name}" ]] ;;
    nohup)    [[ -f "${SBD_RUNTIME_DIR}/${svc_name}.pid" ]] || crontab -l 2>/dev/null | grep -q "# sbd:${svc_name}" ;;
  esac
}

# Check if a service is enabled at boot
sbd_service_is_enabled() {
  local svc_name="$1"
  detect_init_system
  case "$SBD_INIT_SYSTEM" in
    systemd)  sbd_service_op systemctl is-enabled --quiet "${svc_name}.service" 2>/dev/null ;;
    openrc)   sbd_service_op rc-update show default 2>/dev/null | grep -q "$svc_name" ;;
    nohup)    crontab -l 2>/dev/null | grep -q "# sbd:${svc_name}" ;;
  esac
}

# Enable a oneshot service (fw-replay) — runs once at boot
sbd_service_enable_oneshot() {
  local svc_name="$1"
  local exec_cmd="$2"
  detect_init_system
  case "$SBD_INIT_SYSTEM" in
    systemd)
      # Caller must have already written the systemd unit file
      sbd_systemd_daemon_reload true "systemd daemon-reload" || return 1
      sbd_service_op systemctl enable "${svc_name}.service" >/dev/null 2>&1 || return 1
      ;;
    openrc|nohup)
      nohup_register_crontab "$svc_name" "$exec_cmd" "/dev/null"
      ;;
  esac
}

# Disable a oneshot/any service and remove artifacts
sbd_service_disable_oneshot() {
  sbd_service_stop "$1"
}
