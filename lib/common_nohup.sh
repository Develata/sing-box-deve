#!/usr/bin/env bash

# pid + boot/start identity + executable. Never signal a bare legacy PID.
sbd_process_identity() {
  local pid="$1" stat rest executable boot start inode
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
  if [[ -r "/proc/${pid}/stat" ]]; then
    IFS= read -r stat < "/proc/${pid}/stat" || return 1
    rest="${stat##*) }"
    local -a fields
    read -r -a fields <<< "$rest"
    [[ "${fields[0]:-}" != Z && "${fields[0]:-}" != X ]] || return 1
    start="${fields[19]:-}"
    executable="$(readlink "/proc/${pid}/exe")" || return 1
    executable="${executable% (deleted)}"
    inode="$(stat -Lc '%d:%i' "/proc/${pid}/exe" 2>/dev/null)" || return 1
    IFS= read -r boot < /proc/sys/kernel/random/boot_id || return 1
    printf '%s|%s|%s|%s\n' "$boot" "$start" "$inode" "$executable"
  elif [[ "$(uname -s)" == FreeBSD ]]; then
    start="$(ps -p "$pid" -o lstart=)" || return 1
    executable="$(ps -p "$pid" -o comm=)" || return 1
    [[ -n "$start" && -n "$executable" ]] || return 1
    printf '%s|%s\n' "$start" "$executable"
  else
    return 1
  fi
}

nohup_read_identity() {
  local pid_file="$1" pid saved current
  [[ -f "$pid_file" && -f "${pid_file}.identity" ]] || return 1
  IFS= read -r pid < "$pid_file" || return 1
  IFS= read -r saved < "${pid_file}.identity" || return 1
  [[ "$pid" =~ ^[1-9][0-9]*$ && -n "$saved" ]] || return 1
  current="$(sbd_process_identity "$pid")" || return 1
  [[ "$current" == "$saved" ]] || return 1
  printf '%s\n' "$pid"
}

nohup_rotate_log() {
  local file="$1" max_bytes="${SBD_LOG_MAX_BYTES:-10485760}" bytes
  [[ "$max_bytes" =~ ^[1-9][0-9]*$ ]] || return 2
  [[ -f "$file" && ! -L "$file" ]] || return 0
  bytes="$(wc -c < "$file")" || return 1
  (( bytes >= max_bytes )) || [[ "${2:-false}" == true ]] || return 0
  [[ ! -f "${file}.1" ]] || mv -f "${file}.1" "${file}.2" || return 1
  cp -p "$file" "${file}.1" || return 1
  : > "$file"
}

nohup_start_service() {
  local svc_name="$1" exec_cmd="$2" new_pid identity executable observed attempt startup_identity=""
  [[ "$svc_name" =~ ^[A-Za-z0-9_-]+$ ]] || return 2
  local log_file="${SBD_DATA_DIR}/${svc_name}.log" pid_file="${SBD_RUNTIME_DIR}/${svc_name}.pid"
  local -a argv
  read -r -a argv <<< "$exec_cmd"
  (( ${#argv[@]} > 0 )) || return 2
  executable="$(command -v "${argv[0]}")" || return 1
  executable="$(readlink -f "$executable")" || return 1
  mkdir -p "$SBD_RUNTIME_DIR" "$SBD_DATA_DIR" || return 1
  nohup_stop_service "$svc_name" || return 1
  if [[ "$svc_name" == sing-box-deve-argo ]]; then nohup_rotate_log "$log_file" true || return 1
  else nohup_rotate_log "$log_file" || return 1; fi
  command -v python3 >/dev/null || return 1
  [[ -f "$PROJECT_ROOT/scripts/bounded-log.py" ]] || return 1
  (
    if [[ -n "${SBD_MUTATION_LOCK_FD:-}" ]]; then exec {SBD_MUTATION_LOCK_FD}>&-; fi
    exec nohup "${argv[@]}" > >(exec python3 "$PROJECT_ROOT/scripts/bounded-log.py" "$log_file" "${SBD_LOG_MAX_BYTES:-10485760}") 2>&1
  ) &
  new_pid=$!
  identity=""
  for ((attempt = 0; attempt < 20; attempt++)); do
    observed="$(sbd_process_identity "$new_pid")" || break
    startup_identity="$observed"
    if [[ "${observed##*|}" == "$executable" ]]; then identity="$observed"; break; fi
    sleep 0.1
  done
  if [[ -z "$identity" ]]; then
    if [[ -n "$startup_identity" && "$(sbd_process_identity "$new_pid" 2>/dev/null || true)" == "$startup_identity" ]]; then
      kill "$new_pid" 2>/dev/null || true
    fi
    log_error "Unable to verify started process: ${svc_name}; see ${log_file}"
    return 1
  fi
  if ! nohup_write_identity "$pid_file" "$new_pid" "$identity"; then
    if [[ "$(sbd_process_identity "$new_pid" 2>/dev/null || true)" == "$identity" ]]; then kill "$new_pid" 2>/dev/null || true; fi
    log_error "Unable to persist process identity: ${svc_name}"
    return 1
  fi
  sleep 1
  if ! nohup_is_active "$svc_name"; then
    rm -f "$pid_file" "${pid_file}.identity"
    log_error "nohup service failed to start: ${svc_name}; see ${log_file}"
    return 1
  fi
  if ! nohup_register_crontab "$svc_name" "$exec_cmd" "$log_file"; then
    nohup_stop_service "$svc_name" || true
    log_error "Unable to register nohup service at boot: ${svc_name}"
    return 1
  fi
  log_info "Started ${svc_name} via nohup (PID: ${new_pid})"
}

nohup_stop_service() {
  local svc_name="$1" pid_file="${SBD_RUNTIME_DIR}/${1}.pid" pid saved deadline saved_boot current_boot
  if [[ -f "$pid_file" ]]; then
    IFS= read -r pid < "$pid_file" || return 1
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || { log_error "Invalid PID state: ${pid_file}"; return 1; }
    if [[ -r /proc/sys/kernel/random/boot_id && -f "${pid_file}.identity" ]]; then
      IFS='|' read -r saved_boot _ < "${pid_file}.identity" || return 1
      IFS= read -r current_boot < /proc/sys/kernel/random/boot_id || return 1
      if [[ "$saved_boot" =~ ^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$ && "$saved_boot" != "$current_boot" ]]; then
        # An earlier boot cannot own any current process; retire only its files.
        rm -f "$pid_file" "${pid_file}.identity" || return 1
        nohup_remove_crontab "$svc_name"
        return $?
      fi
    fi
    if kill -0 "$pid" 2>/dev/null; then
      saved="$(nohup_read_identity "$pid_file")" || {
        log_error "Refusing to signal an unverified/stale PID: ${pid}; inspect ${pid_file}"; return 1;
      }
      kill -- "$saved" 2>/dev/null || return 1
      deadline=$((SECONDS + ${SBD_NOHUP_STOP_TIMEOUT:-5}))
      while (( SECONDS < deadline )) && nohup_read_identity "$pid_file" >/dev/null; do sleep 0.1; done
      if saved="$(nohup_read_identity "$pid_file")"; then
        kill -KILL -- "$saved" 2>/dev/null || return 1
        deadline=$((SECONDS + 3))
        while (( SECONDS < deadline )) && nohup_read_identity "$pid_file" >/dev/null; do sleep 0.1; done
        if nohup_read_identity "$pid_file" >/dev/null; then
          log_error "Process did not stop: ${svc_name}"; return 1
        fi
      fi
    fi
    rm -f "$pid_file" "${pid_file}.identity" || return 1
  fi
  nohup_remove_crontab "$svc_name"
}

nohup_register_crontab() {
  local svc_name="$1" exec_cmd="$2" log_file="$3" tag="# sbd:${1}"
  local existing runner entry
  existing="$(crontab -l 2>/dev/null || true)"
  existing="$(printf '%s\n' "$existing" | awk -v tag="$tag" 'substr($0, length($0)-length(tag)+1) != tag')" || return 1
  # Boot uses the same PID/identity writer as an interactive restart.
  local runtime_root="$PROJECT_ROOT"
  [[ ! -L "$SBD_INSTALL_DIR/current" ]] || runtime_root="$SBD_INSTALL_DIR/current"
  printf -v runner '%q' "${runtime_root}/scripts/nohup-run.sh"
  printf -v entry '@reboot %s %q %q %q %q %s' "$runner" "$svc_name" "$exec_cmd" "$SBD_RUNTIME_DIR" "$SBD_DATA_DIR" "$tag"
  printf '%s\n%s\n' "$existing" "$entry" | crontab -
}

nohup_remove_crontab() {
  local svc_name="$1" tag="# sbd:${1}" existing updated
  existing="$(crontab -l 2>/dev/null || true)"
  [[ -n "$existing" ]] || return 0
  updated="$(printf '%s\n' "$existing" | awk -v tag="$tag" 'substr($0, length($0)-length(tag)+1) != tag')" || return 1
  printf '%s\n' "$updated" | crontab -
}

nohup_is_active() {
  nohup_read_identity "${SBD_RUNTIME_DIR}/${1}.pid" >/dev/null
}

nohup_write_identity() {
  local pid_file="$1" pid="$2" identity="$3" tmp
  tmp="$(mktemp "${pid_file}.identity.XXXXXX")" || return 1
  printf '%s\n' "$identity" > "$tmp" || return 1
  chmod 0600 "$tmp" || return 1
  mv -f "$tmp" "${pid_file}.identity" || return 1
  tmp="$(mktemp "${pid_file}.XXXXXX")" || return 1
  printf '%s\n' "$pid" > "$tmp" || return 1
  chmod 0600 "$tmp" || return 1
  mv -f "$tmp" "$pid_file"
}
