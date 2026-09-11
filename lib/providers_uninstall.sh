#!/usr/bin/env bash

uninstall_disable_unit() {
  sbd_service_disable_oneshot "${1%.service}"
}

sbd_managed_unit_file() {
  local file="$1" exec_cmd launcher="${SBD_LAUNCHER_PATH:-/usr/local/bin/sb}"
  [[ -f "$file" && ! -L "$file" ]] || return 1
  if [[ -f "$(sbd_host_file_record "$file")/after.sha256" ]]; then sbd_host_file_unchanged "$file"; return $?; fi
  grep -q '^# Managed by sing-box-deve: service-v1$' "$file" && return 0
  exec_cmd="$(sed -n 's/^ExecStart=//p' "$file" | head -n1)"
  [[ "$exec_cmd" == "$SBD_INSTALL_DIR/"* ]] && return 0
  # Pre-ledger firewall units used the global launcher outside the install root.
  # Adopt only the complete historical template and a recognized project launcher.
  [[ "$file" == "${SBD_FW_REPLAY_SERVICE_FILE:-}" ]] || return 1
  sbd_managed_launcher "$launcher" || return 1
  cmp -s -- "$file" <(cat <<EOF
[Unit]
Description=sing-box-deve firewall replay
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${launcher} fw replay

[Install]
WantedBy=multi-user.target
EOF
  )
}

uninstall_remove_legacy_engine_units() {
  [[ "${SBD_USER_MODE:-false}" != true ]] || return 0
  local unit file
  for unit in sing-box.service xray.service; do
    file="${SBD_SYSTEMD_DIR:-/etc/systemd/system}/${unit}"
    [[ -f "$file" ]] || continue
    if sbd_managed_unit_file "$file"; then
      uninstall_disable_unit "$unit" || return 1
      rm -f -- "$file" || return 1
    else
      log_warn "Keeping service with unproven ownership: ${file}"
    fi
  done
}


uninstall_remove_managed_global_bins() {
  local global_bin_dir="${SBD_GLOBAL_BIN_DIR:-/usr/local/bin}" p real
  [[ "${SBD_USER_MODE:-false}" != true ]] || global_bin_dir="${HOME}/.local/bin"
  for p in "$global_bin_dir/sb" "$global_bin_dir/sing-box" "$global_bin_dir/xray"; do
    [[ -e "$p" || -L "$p" ]] || continue
    real="$(readlink -f "$p" 2>/dev/null || true)"
    if [[ -L "$p" && "$real" == "$SBD_INSTALL_DIR/"* ]] || sbd_managed_launcher "$p"; then
      rm -f -- "$p" || return 1
      sbd_host_forget_file "$p" || return 1
    else
      log_warn "Keeping command with unproven ownership: ${p}"
    fi
  done
}

sbd_uninstall_validate_roots() {
  local root canonical host_state protected_home="${HOME:-}"
  if [[ -z "$protected_home" ]]; then
    protected_home="$(sbd_run_deadline 5 python3 -c 'import os,pwd; print(pwd.getpwuid(os.geteuid()).pw_dir)')" || return 1
  fi
  [[ "$protected_home" == /* ]] || return 1
  host_state="$(sbd_host_state_dir)" || return 1
  for root in "$SBD_CONFIG_DIR" "$SBD_STATE_DIR" "$SBD_RUNTIME_DIR" "$SBD_INSTALL_DIR" "$SBD_BIN_DIR" "$SBD_DATA_DIR"; do
    [[ "$root" == /* && "$root" != *$'\n'* && "$root" != *'|'* && ! -L "$root" && "$root" != *'/../'* && "$root" != */.. ]] || return 1
    canonical="$(realpath -m "$root")" || return 1
    [[ "$canonical" == "${root%/}" && "$host_state" != "$canonical" && "$host_state" != "$canonical/"* ]] || return 1
    case "$canonical" in /|/etc|/opt|/usr|/usr/local|/bin|/sbin|/lib|/tmp|/var|/var/tmp|/var/lib|/run|/home|/root|"${protected_home%/}"|'') return 1 ;; esac
  done
}

sbd_uninstall_backup() {
  local destination="$1" root
  [[ "$destination" == "$(realpath -m "$destination")" ]] || return 1
  for root in "$SBD_CONFIG_DIR" "$SBD_STATE_DIR" "$SBD_RUNTIME_DIR" "$SBD_INSTALL_DIR"; do
    [[ "$destination" != "$root" && "$destination" != "$root/"* ]] || {
      log_error "Backup is inside uninstall deletion set: ${destination}"; return 1;
    }
  done
  sbd_state_capture "$destination" false || return 1
  sbd_state_verify "$destination"
}

provider_uninstall() {
  sbd_with_mutation_lock provider_uninstall_unlocked "$@"
}

provider_uninstall_unlocked() {
  local keep_settings="${1:-false}" backup="" svc file
  local -a service_files=("$SBD_SERVICE_FILE" "$SBD_ARGO_SERVICE_FILE" "$SBD_FW_REPLAY_SERVICE_FILE" "$SBD_WARP_SOCKS_SERVICE_FILE")
  detect_init_system || return 1
  if [[ "$SBD_INIT_SYSTEM" == openrc && "${SBD_USER_MODE:-false}" != true ]]; then
    for svc in sing-box-deve sing-box-deve-argo sing-box-deve-fw-replay sing-box-deve-warp-socks5; do
      service_files+=("${SBD_OPENRC_DIR:-/etc/init.d}/$svc")
    done
  fi
  ensure_root
  sbd_uninstall_validate_roots || { log_error "Unsafe uninstall roots"; return 1; }
  if [[ "$keep_settings" == true ]]; then
    backup="${SBD_INSTALL_DIR}.backup-$(date -u +%Y%m%dT%H%M%SZ)-$(rand_hex_8)"
    sbd_uninstall_backup "$backup" || { log_error "Backup verification failed; uninstall aborted"; return 1; }
  fi
  for file in "${service_files[@]}"; do
    [[ ! -e "$file" ]] || sbd_managed_unit_file "$file" || {
      log_error "Service ownership unproven; uninstall aborted: $file"; return 1;
    }
  done
  log_warn "Uninstall requested; removing verified managed runtime resources"
  for svc in sing-box-deve sing-box-deve-argo sing-box-deve-fw-replay sing-box-deve-warp-socks5; do
    # Stop before deleting PID files; a stop failure must leave recovery state.
    uninstall_disable_unit "${svc}.service" || return 1
    if sbd_service_is_active "$svc"; then log_error "Service still active: ${svc}"; return 1; fi
  done
  uninstall_remove_legacy_engine_units || return 1
  for file in "${service_files[@]}"; do
    [[ ! -f "$file" ]] || rm -f -- "$file" || return 1
    sbd_host_forget_file "$file" || return 1
  done
  uninstall_remove_managed_global_bins || return 1
  sbd_service_daemon_reload || return 1
  if fw_detect_backend_optional; then
    fw_clear_managed_rules || return 1
  elif [[ -s "$SBD_RULES_FILE" ]]; then
    log_error "Firewall backend unavailable; keeping ownership records for recovery"
    return 1
  else
    log_warn "No firewall backend detected; no managed rules to remove"
  fi
  if [[ "${PURGE_MANAGED_HOST_CHANGES:-false}" == true ]]; then
    sbd_host_purge || return 1
  fi
  sbd_uninstall_validate_roots || return 1
  rm -rf -- "$SBD_CONFIG_DIR" "$SBD_STATE_DIR" "$SBD_RUNTIME_DIR" "$SBD_INSTALL_DIR" || return 1
  verify_uninstall || return 1
  [[ -z "$backup" ]] || log_info "Backup preserved and verified: ${backup}"
  log_success "Uninstall complete"
}

verify_uninstall() {
  local path
  for path in "$SBD_CONFIG_DIR" "$SBD_STATE_DIR" "$SBD_RUNTIME_DIR" "$SBD_INSTALL_DIR"; do
    [[ ! -e "$path" && ! -L "$path" ]] || { log_error "Managed path remains: ${path}"; return 1; }
  done
}
