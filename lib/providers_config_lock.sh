#!/usr/bin/env bash

provider_cfg_with_lock() {
  local lock_file="${SBD_CFG_LOCK_FILE:-${SBD_STATE_DIR}/cfg.lock}" rc=0
  mkdir -p "$SBD_STATE_DIR"
  if [[ "${SBD_FORCE_MKDIR_LOCK:-false}" != "true" ]] && command -v flock >/dev/null 2>&1; then
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
  local waited=0 owner_pid="" lock_mtime="" now
  while ! mkdir "$lock_dir" 2>/dev/null; do
    owner_pid=""
    if [[ -r "${lock_dir}/pid" ]]; then
      read -r owner_pid < "${lock_dir}/pid" || true
    fi
    if [[ "$owner_pid" =~ ^[0-9]+$ ]] && ! kill -0 "$owner_pid" 2>/dev/null; then
      rm -f "${lock_dir}/pid" "${lock_dir}/created" 2>/dev/null || true
      rmdir "$lock_dir" 2>/dev/null || true
      continue
    fi
    if [[ -z "$owner_pid" ]]; then
      lock_mtime="$(stat -c %Y "$lock_dir" 2>/dev/null || stat -f %m "$lock_dir" 2>/dev/null || true)"
      now="$(date +%s)"
      if [[ "$lock_mtime" =~ ^[0-9]+$ ]] && (( now - lock_mtime > 60 )); then
        rm -f "${lock_dir}/pid" "${lock_dir}/created" 2>/dev/null || true
        rmdir "$lock_dir" 2>/dev/null || true
        continue
      fi
    fi
    sleep 1
    waited=$((waited + 1))
    (( waited < 30 )) || die "cfg operation is busy (lock timeout): $lock_file"
  done
  printf '%s\n' "$$" > "${lock_dir}/pid"
  date +%s > "${lock_dir}/created"
  (
    trap 'rm -f "${lock_dir}/pid" "${lock_dir}/created" 2>/dev/null || true; rmdir "$lock_dir" 2>/dev/null || true' EXIT INT TERM HUP
    "$@"
  ) || rc=$?
  return "$rc"
}
