#!/usr/bin/env bash
# shellcheck disable=SC2016

# Deadlines apply to commands and their process groups. A timeout may leave an
# interrupted package database or remote job; callers must reconcile that state.
sbd_positive_seconds() {
  [[ "${1:-}" =~ ^[1-9][0-9]*$ ]]
}

sbd_run_deadline() (
  local seconds="$1" grace="${SBD_TIMEOUT_KILL_AFTER:-3}" runner
  shift
  if ! sbd_positive_seconds "$seconds" || ! sbd_positive_seconds "$grace"; then
    log_error "Invalid deadline/grace: ${seconds}/${grace}"; return 2
  fi
  runner="$(command -v timeout || command -v gtimeout)" || {
    log_error "A timeout implementation is required (coreutils timeout/gtimeout)"; return 127;
  }
  if [[ -n "${SBD_MUTATION_LOCK_FD:-}" ]]; then exec {SBD_MUTATION_LOCK_FD}>&-; fi
  if declare -F "$1" >/dev/null; then
    # Allows deterministic command substitutes in tests; real I/O uses binaries.
    (export -f "${1?}"; "$runner" -k "${grace}s" "${seconds}s" bash -c '"$@"' sbd-deadline "$@")
  else
    "$runner" -k "${grace}s" "${seconds}s" "$@"
  fi
)

sbd_http_small() {
  local seconds="${SBD_HTTP_TIMEOUT:-20}"
  sbd_positive_seconds "$seconds" || return 2
  curl -fsSL --connect-timeout 5 --max-time "$seconds" \
    --max-filesize "${SBD_HTTP_MAX_BYTES:-2097152}" "$@"
}

sbd_service_op() {
  sbd_run_deadline "${SBD_SERVICE_TIMEOUT:-30}" "$@"
}

sbd_package_run() (
  local seconds="${SBD_PACKAGE_TIMEOUT:-300}" grace="${SBD_PACKAGE_TERM_GRACE:-30}"
  sbd_positive_seconds "$seconds" && sbd_positive_seconds "$grace" || return 2
  if [[ -n "${SBD_MUTATION_LOCK_FD:-}" ]]; then exec {SBD_MUTATION_LOCK_FD}>&-; fi
  DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l python3 "$PROJECT_ROOT/scripts/package-run.py" "$seconds" "$grace" "$@"
)

sbd_package_database_unlocked() {
  sbd_run_deadline 5 python3 "$PROJECT_ROOT/scripts/package-run.py" --check-dpkg-locks
}

sbd_package_audit() {
  local output rc=0
  output="$(sbd_run_deadline 15 dpkg --audit 2>&1)" || rc=$?
  printf 'dpkg --audit: rc=%s\n%.65536s\n' "$rc" "$output" >> "$package_log" || return 2
  (( rc == 0 )) || { log_error "Package audit failed; inspect $package_log"; return 2; }
  [[ -z "$output" ]] || return 1
}

sbd_package_reconcile() {
  local audit_rc reconcile_rc=0
  if sbd_package_audit; then return 0; else audit_rc=$?; fi
  (( audit_rc == 1 )) || return 1
  [[ "$package_reconciled" == false ]] || return 1
  package_reconciled=true
  log_warn "Package reconciliation attempted: dpkg --configure -a (one bounded round)"
  printf 'reconciliation: dpkg --configure -a\n' >> "$package_log" || return 1
  sbd_package_database_unlocked || return 1
  sbd_package_run dpkg --configure -a || reconcile_rc=$?
  printf 'reconciliation: rc=%s\n' "$reconcile_rc" >> "$package_log" || return 1
  (( reconcile_rc == 0 )) || return 1
  sbd_package_audit
}

sbd_package_op() {
  local rc=0 debian=false host marker package_log package_reconciled=false
  case "${1##*/}" in apt|apt-get|dpkg) debian=true ;; esac
  host="$(sbd_host_state_dir)" || return 1
  marker="$host/package_recovery_required"; package_log="$host/package-recovery.log"
  [[ ! -L "$host" && ! -L "$marker" && ! -L "$package_log" ]] || return 1
  (umask 077; mkdir -p "$host"; : > "$package_log") || return 1
  if [[ "$debian" == true ]]; then
    # Write ahead even on the first invocation: SIGKILL/reboot cannot erase the
    # requirement to audit before the next package mutation.
    (umask 077; printf 'audit required\n' > "$marker") || return 1
    chmod 0600 "$marker" "$package_log" || return 1
    sbd_sync_directory "$host" || return 1
    if ! sbd_package_database_unlocked || ! sbd_package_reconcile; then
      log_error "Package state still requires attention; refusing new mutation. See $marker and $package_log"
      return 1
    fi
  fi
  if [[ -n "${SBD_ACTIVE_TRANSACTION:-}" ]] && command -v dpkg-query >/dev/null; then
    if [[ ! -f "$SBD_ACTIVE_TRANSACTION/packages.before" ]]; then
      sbd_run_deadline 15 dpkg-query -W -f='${Package} ${Version} ${db:Status-Abbrev}\n' > "$SBD_ACTIVE_TRANSACTION/packages.before" || return 1
    fi
  fi
  if sbd_package_run "$@"; then
    rc=0
  else
    rc=$?
  fi
  printf 'package operation: rc=%s\n' "$rc" >> "$package_log" || return 1
  if [[ "$debian" == true ]]; then
    if sbd_package_database_unlocked && sbd_package_reconcile; then
      rm -f -- "$marker" || return 1
      sbd_sync_directory "$host" || return 1
    else
      log_error "Package state still requires attention; reconciliation incomplete. See $marker and $package_log"
      (( rc != 0 )) || rc=1
    fi
  fi
  if [[ -n "${SBD_ACTIVE_TRANSACTION:-}" && -f "$SBD_ACTIVE_TRANSACTION/packages.before" ]]; then
    sbd_run_deadline 15 dpkg-query -W -f='${Package} ${Version} ${db:Status-Abbrev}\n' > "$SBD_ACTIVE_TRANSACTION/packages.after" || return 1
  fi
  (( rc != 0 )) || return 0
  log_error "Package operation failed (${rc}); inspect package-manager state before retrying"
  return "$rc"
}

sbd_apt_get() {
  DEBIAN_FRONTEND=noninteractive sbd_package_op apt-get \
    -o Acquire::Retries=1 -o Acquire::http::Timeout=15 \
    -o Acquire::https::Timeout=15 -o DPkg::Lock::Timeout=30 "$@"
}

sbd_ssh_exec() {
  local host="$1" user="$2" password="$3" command_text="$4"
  local known_hosts="${SERV00_KNOWN_HOSTS_FILE:-${HOME}/.ssh/known_hosts}"
  [[ "$host" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ && "$user" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || {
    log_error "Invalid SSH host/user"; return 2;
  }
  [[ -s "$known_hosts" ]] || { log_error "Verified SSH known_hosts file required: ${known_hosts}"; return 1; }
  SSHPASS="$password" sbd_run_deadline "${SBD_SSH_TIMEOUT:-180}" sshpass -e ssh -n \
    -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=${known_hosts}" \
    -o ConnectTimeout=10 -o ServerAliveInterval=10 -o ServerAliveCountMax=3 \
    "${user}@${host}" "$command_text"
}
