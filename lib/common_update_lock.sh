#!/usr/bin/env bash
# shellcheck disable=SC2034

UPDATE_LOCK_FD=200

check_update_disk_space() {
  local required_mb="${1:-10}"
  local available_kb available_mb
  available_kb="$(df -k "${PROJECT_ROOT}" 2>/dev/null | awk 'NR==2 {print $4}')"
  if [[ -z "$available_kb" ]]; then
    log_warn "$(msg "无法检查磁盘空间" "Unable to check disk space")"
    return 0
  fi
  available_mb=$((available_kb / 1024))
  if [[ "$available_mb" -lt "$required_mb" ]]; then
    die "$(msg "磁盘空间不足: 需要 ${required_mb}MB, 可用 ${available_mb}MB" "Insufficient disk space: need ${required_mb}MB, have ${available_mb}MB")"
  fi
  log_info "$(msg "磁盘空间检查通过: 可用 ${available_mb}MB" "Disk space check passed: ${available_mb}MB available")"
}

acquire_update_lock() {
  local lock_file="${SBD_STATE_DIR:-/var/lib/sing-box-deve}/update.lock"
  mkdir -p "$(dirname "$lock_file")" 2>/dev/null || true
  eval "exec ${UPDATE_LOCK_FD}>\"$lock_file\""
  if ! flock -w 30 "$UPDATE_LOCK_FD" 2>/dev/null; then
    die "$(msg "另一个更新进程正在运行 (锁文件: $lock_file)" "Another update is in progress (lock: $lock_file)")"
  fi
  log_info "$(msg "已获取更新锁" "Update lock acquired")"
}

release_update_lock() {
  flock -u "$UPDATE_LOCK_FD" 2>/dev/null || true
  eval "exec ${UPDATE_LOCK_FD}>&-" 2>/dev/null || true
}
