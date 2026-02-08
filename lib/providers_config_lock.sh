#!/usr/bin/env bash

provider_cfg_with_lock() {
  local lock_file="${SBD_CFG_LOCK_FILE:-${SBD_STATE_DIR}/cfg.lock}" rc=0
  mkdir -p "$SBD_STATE_DIR"
  if command -v flock >/dev/null 2>&1; then
    exec 9>"$lock_file"
    if ! flock -w 30 9; then
      exec 9>&-
      die "cfg operation is busy (lock timeout): $lock_file"
    fi
    "$@" || rc=$?
    flock -u 9 || true
    exec 9>&-
    return "$rc"
  fi

  local lock_dir="${lock_file}.d"
  local waited=0
  while ! mkdir "$lock_dir" 2>/dev/null; do
    sleep 1
    waited=$((waited + 1))
    (( waited < 30 )) || die "cfg operation is busy (lock timeout): $lock_file"
  done
  "$@" || rc=$?
  rmdir "$lock_dir" >/dev/null 2>&1 || true
  return "$rc"
}
