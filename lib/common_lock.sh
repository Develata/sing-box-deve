#!/usr/bin/env bash
# shellcheck disable=SC2034

# Stable control state survives runtime uninstall and release switches.
sbd_host_state_dir() {
  if [[ -n "${SBD_HOST_STATE_DIR:-}" ]]; then
    printf '%s\n' "$SBD_HOST_STATE_DIR"
  elif [[ "$SBD_STATE_DIR" == "$SBD_INSTALL_DIR/"* ]]; then
    printf '%s.host\n' "$SBD_INSTALL_DIR"
  else
    printf '%s.host\n' "$SBD_STATE_DIR"
  fi
}

SBD_MUTATION_DEPTH=0

sbd_with_mutation_lock() {
  if declare -F sbd_git_source_guard >/dev/null; then sbd_git_source_guard || return 1; fi
  if (( SBD_MUTATION_DEPTH > 0 )); then
    "$@"
    return $?
  fi
  (
    local host_state lock_fd wait_seconds="${SBD_LOCK_TIMEOUT:-30}"
    [[ "$wait_seconds" =~ ^[0-9]+$ ]] || exit 2
    host_state="$(sbd_host_state_dir)" || exit 1
    [[ "$host_state" == /* && ! -L "$host_state" ]] || { log_error "Unsafe host state path"; exit 1; }
    command -v flock >/dev/null || { log_error "flock is required for safe mutation serialization"; exit 127; }
    (umask 077; mkdir -p "$host_state") || exit 1
    [[ ! -L "$host_state/mutation.lock" ]] || exit 1
    exec {lock_fd}> "$host_state/mutation.lock" || exit 1
    flock -w "$wait_seconds" "$lock_fd" || { log_error "Another mutation is in progress (lock timeout)"; exit 1; }
    if declare -F sbd_git_source_guard >/dev/null; then sbd_git_source_guard || exit 1; fi
    SBD_MUTATION_DEPTH=1
    SBD_MUTATION_LOCK_FD="$lock_fd"
    if declare -F sbd_transaction_recover >/dev/null; then sbd_transaction_recover || exit 1; fi
    # Non-exported nesting marker; exec'd CLI instances acquire their own lock.
    "$@"
  )
}
