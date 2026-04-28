#!/usr/bin/env bash

nohup_start_service() {
  local svc_name="$1"
  local exec_cmd="$2"
  local log_file="${SBD_DATA_DIR}/${svc_name}.log"
  local pid_file="${SBD_RUNTIME_DIR}/${svc_name}.pid"

  mkdir -p "$SBD_RUNTIME_DIR" "$SBD_DATA_DIR" 2>/dev/null || true

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

  # shellcheck disable=SC2086
  nohup $exec_cmd >> "$log_file" 2>&1 &
  local new_pid=$!
  echo "$new_pid" > "$pid_file"

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

  local existing
  existing="$(crontab -l 2>/dev/null || true)"
  existing="$(echo "$existing" | grep -v "$tag" || true)"

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

nohup_is_active() {
  local svc_name="$1"
  local pid_file="${SBD_RUNTIME_DIR}/${svc_name}.pid"
  [[ -f "$pid_file" ]] || return 1
  local pid
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}
