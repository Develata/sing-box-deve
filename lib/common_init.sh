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
  log_info "$(msg "以非 root 模式运行（用户模式）" "Running as non-root (user mode)")"
  init_user_mode_paths
}

init_user_mode_paths() {
  local home="${HOME:-$(eval echo ~)}"
  local base="${home}/sing-box-deve"

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

  # Service files — set but not necessarily used in nohup mode
  SBD_SERVICE_FILE="${base}/service/sing-box-deve.service"
  SBD_ARGO_SERVICE_FILE="${base}/service/sing-box-deve-argo.service"
  SBD_PSIPHON_SERVICE_FILE="${base}/service/sing-box-deve-psiphon.service"

  mkdir -p "${base}/service" 2>/dev/null || true
}

detect_init_system() {
  # Already detected?
  [[ -n "$SBD_INIT_SYSTEM" ]] && return 0

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

# Write an OpenRC init script for the given service name and exec command
write_openrc_service() {
  local svc_name="$1"
  local exec_cmd="$2"
  local log_file="${3:-/var/log/${svc_name}.log}"
  local svc_file="/etc/init.d/${svc_name}"

  if [[ "$SBD_USER_MODE" == "true" ]]; then
    svc_file="${SBD_INSTALL_DIR}/service/${svc_name}.openrc"
    log_file="${SBD_DATA_DIR}/${svc_name}.log"
    log_warn "$(msg "非 root 模式下 OpenRC 服务仅生成脚本，需手动安装" \
                 "User mode: OpenRC script generated but needs manual install")"
  fi

  cat > "$svc_file" <<EOF
#!/sbin/openrc-run

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
  chmod +x "$svc_file"

  if [[ "$SBD_USER_MODE" == "false" ]]; then
    rc-update add "$svc_name" default 2>/dev/null || true
    rc-service "$svc_name" restart 2>/dev/null || true
  fi
}

# Launch a process via nohup with optional crontab @reboot persistence
nohup_start_service() {
  local svc_name="$1"
  local exec_cmd="$2"
  local log_file="${SBD_DATA_DIR}/${svc_name}.log"
  local pid_file="${SBD_RUNTIME_DIR}/${svc_name}.pid"

  mkdir -p "$SBD_RUNTIME_DIR" "$SBD_DATA_DIR" 2>/dev/null || true

  # Kill existing process if any
  if [[ -f "$pid_file" ]]; then
    local old_pid
    old_pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
      kill "$old_pid" 2>/dev/null || true
      sleep 1
      kill -9 "$old_pid" 2>/dev/null || true
    fi
    rm -f "$pid_file"
  fi

  # Start via nohup (exec_cmd intentionally unquoted; contains command + arguments)
  # shellcheck disable=SC2086
  nohup $exec_cmd >> "$log_file" 2>&1 &
  local new_pid=$!
  echo "$new_pid" > "$pid_file"

  # Register @reboot crontab entry
  nohup_register_crontab "$svc_name" "$exec_cmd" "$log_file"

  log_info "$(msg "已通过 nohup 启动 ${svc_name} (PID: ${new_pid})" \
               "Started ${svc_name} via nohup (PID: ${new_pid})")"
}

nohup_stop_service() {
  local svc_name="$1"
  local pid_file="${SBD_RUNTIME_DIR}/${svc_name}.pid"

  if [[ -f "$pid_file" ]]; then
    local pid
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      sleep 1
      kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$pid_file"
  fi

  nohup_remove_crontab "$svc_name"
}

nohup_register_crontab() {
  local svc_name="$1"
  local exec_cmd="$2"
  local log_file="$3"
  local tag="# sbd:${svc_name}"

  # Remove existing entry for this service
  local existing
  existing="$(crontab -l 2>/dev/null || true)"
  existing="$(echo "$existing" | grep -v "$tag" || true)"

  # Add @reboot entry
  local new_entry="@reboot nohup ${exec_cmd} >> ${log_file} 2>&1 & ${tag}"
  if [[ -n "$existing" ]]; then
    printf '%s\n%s\n' "$existing" "$new_entry" | crontab -
  else
    printf '%s\n' "$new_entry" | crontab -
  fi
}

nohup_remove_crontab() {
  local svc_name="$1"
  local tag="# sbd:${svc_name}"
  local existing
  existing="$(crontab -l 2>/dev/null || true)"
  if [[ -n "$existing" ]]; then
    echo "$existing" | grep -v "$tag" | crontab - 2>/dev/null || true
  fi
}

# Check if a nohup-managed service is running
nohup_is_active() {
  local svc_name="$1"
  local pid_file="${SBD_RUNTIME_DIR}/${svc_name}.pid"
  [[ -f "$pid_file" ]] || return 1
  local pid
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

# Generic service operations that dispatch to the correct init system
sbd_service_enable_and_start() {
  local svc_name="$1"
  local exec_cmd="$2"

  detect_init_system

  case "$SBD_INIT_SYSTEM" in
    systemd)
      systemctl daemon-reload
      systemctl enable "${svc_name}.service" >/dev/null 2>&1 || true
      systemctl restart "${svc_name}.service"
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
  local svc_name="$1"

  detect_init_system

  case "$SBD_INIT_SYSTEM" in
    systemd)
      systemctl stop "${svc_name}.service" 2>/dev/null || true
      systemctl disable "${svc_name}.service" 2>/dev/null || true
      ;;
    openrc)
      rc-service "$svc_name" stop 2>/dev/null || true
      rc-update del "$svc_name" default 2>/dev/null || true
      ;;
    nohup)
      nohup_stop_service "$svc_name"
      ;;
  esac
}

sbd_service_restart() {
  local svc_name="$1"
  local exec_cmd="${2:-}"

  detect_init_system

  case "$SBD_INIT_SYSTEM" in
    systemd)
      systemctl restart "${svc_name}.service"
      ;;
    openrc)
      rc-service "$svc_name" restart 2>/dev/null || true
      ;;
    nohup)
      if [[ -n "$exec_cmd" ]]; then
        nohup_start_service "$svc_name" "$exec_cmd"
      else
        log_warn "$(msg "nohup 模式下重启需要完整命令" "nohup mode restart requires full command")"
      fi
      ;;
  esac
}

sbd_service_is_active() {
  local svc_name="$1"

  detect_init_system

  case "$SBD_INIT_SYSTEM" in
    systemd)
      systemctl is-active --quiet "${svc_name}.service"
      ;;
    openrc)
      rc-service "$svc_name" status 2>/dev/null | grep -q "started"
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
      journalctl -u "${svc_name}.service" -n "$lines" --no-pager
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
    systemctl daemon-reload
  fi
}

# Check if a service unit/config exists
sbd_service_unit_exists() {
  local svc_name="$1"
  detect_init_system
  case "$SBD_INIT_SYSTEM" in
    systemd)  systemctl list-unit-files "${svc_name}.service" 2>/dev/null | grep -q "^${svc_name}.service" ;;
    openrc)   [[ -f "/etc/init.d/${svc_name}" ]] ;;
    nohup)    [[ -f "${SBD_RUNTIME_DIR}/${svc_name}.pid" ]] || crontab -l 2>/dev/null | grep -q "# sbd:${svc_name}" ;;
  esac
}

# Check if a service is enabled at boot
sbd_service_is_enabled() {
  local svc_name="$1"
  detect_init_system
  case "$SBD_INIT_SYSTEM" in
    systemd)  systemctl is-enabled --quiet "${svc_name}.service" 2>/dev/null ;;
    openrc)   rc-update show default 2>/dev/null | grep -q "$svc_name" ;;
    nohup)    crontab -l 2>/dev/null | grep -q "# sbd:${svc_name}" ;;
  esac
}

# Enable a oneshot service (fw-replay, jump-replay) — runs once at boot
sbd_service_enable_oneshot() {
  local svc_name="$1"
  local exec_cmd="$2"
  detect_init_system
  case "$SBD_INIT_SYSTEM" in
    systemd)
      # Caller must have already written the systemd unit file
      systemctl daemon-reload
      systemctl enable "${svc_name}.service" >/dev/null 2>&1 || true
      ;;
    openrc|nohup)
      nohup_register_crontab "$svc_name" "$exec_cmd" "/dev/null"
      ;;
  esac
}

# Disable a oneshot/any service and remove artifacts
sbd_service_disable_oneshot() {
  local svc_name="$1"
  detect_init_system
  case "$SBD_INIT_SYSTEM" in
    systemd)
      systemctl disable --now "${svc_name}.service" 2>/dev/null || true
      ;;
    openrc)
      rc-service "$svc_name" stop 2>/dev/null || true
      rc-update del "$svc_name" default 2>/dev/null || true
      ;;
    nohup)
      nohup_remove_crontab "$svc_name"
      ;;
  esac
}
