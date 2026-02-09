#!/usr/bin/env bash
# shellcheck disable=SC2034

# Update lock file descriptor (use high number to avoid conflicts)
UPDATE_LOCK_FD=200

current_script_version() {
  local version_file="${PROJECT_ROOT}/version"
  if [[ -f "$version_file" ]]; then
    tr -d '[:space:]' < "$version_file"
  else
    echo "v0.0.0-dev"
  fi
}

update_url_with_cache_bust() {
  local url="$1" token="${2:-}"
  [[ -n "$token" ]] || {
    echo "$url"
    return 0
  }
  if [[ "$url" == *\?* ]]; then
    echo "${url}&_cb=${token}"
  else
    echo "${url}?_cb=${token}"
  fi
}

fetch_remote_script_version() {
  local mode="${1:-${UPDATE_SOURCE:-auto}}" base_url version cb version_url
  cb="$(date +%s)"
  while IFS= read -r base_url; do
    [[ -n "$base_url" ]] || continue
    version_url="$(update_url_with_cache_bust "${base_url}/version" "$cb")"
    version="$(curl -fsSL "$version_url" 2>/dev/null | tr -d '[:space:]' || true)"
    if [[ -n "$version" ]]; then
      SBD_ACTIVE_UPDATE_BASE_URL="$base_url"
      echo "$version"
      return 0
    fi
  done < <(update_base_candidates "$mode")
  return 1
}

# Priority 1.2: Validate PROJECT_ROOT before update
validate_project_root() {
  if [[ -z "${PROJECT_ROOT:-}" ]]; then
    die "$(msg "PROJECT_ROOT 未设置" "PROJECT_ROOT is not set")"
  fi
  if [[ ! -d "$PROJECT_ROOT" ]]; then
    die "$(msg "PROJECT_ROOT 不是目录: $PROJECT_ROOT" "PROJECT_ROOT is not a directory: $PROJECT_ROOT")"
  fi
  if [[ ! -w "$PROJECT_ROOT" ]]; then
    die "$(msg "PROJECT_ROOT 不可写: $PROJECT_ROOT" "PROJECT_ROOT is not writable: $PROJECT_ROOT")"
  fi
}

# Priority 3.1: Check disk space before update
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

# Priority 1.1: Acquire update lock to prevent concurrent updates
acquire_update_lock() {
  local lock_file="${SBD_STATE_DIR:-/var/lib/sing-box-deve}/update.lock"
  mkdir -p "$(dirname "$lock_file")" 2>/dev/null || true
  # Open lock file on designated FD
  eval "exec ${UPDATE_LOCK_FD}>\"$lock_file\""
  if ! flock -n -w 30 "$UPDATE_LOCK_FD" 2>/dev/null; then
    die "$(msg "另一个更新进程正在运行 (锁文件: $lock_file)" "Another update is in progress (lock: $lock_file)")"
  fi
  log_info "$(msg "已获取更新锁" "Update lock acquired")"
}

release_update_lock() {
  flock -u "$UPDATE_LOCK_FD" 2>/dev/null || true
  eval "exec ${UPDATE_LOCK_FD}>&-" 2>/dev/null || true
}

# Priority 3.2: Backup current files for rollback
backup_for_rollback() {
  local rollback_dir="${SBD_STATE_DIR:-/var/lib/sing-box-deve}/rollback"
  rm -rf "$rollback_dir"
  mkdir -p "$rollback_dir"
  chmod 700 "$rollback_dir"

  # Source manifest if not already loaded
  if [[ -z "${UPDATE_MANIFEST_FILES[*]:-}" ]]; then
    # shellcheck source=lib/update_manifest.sh
    source "${PROJECT_ROOT}/lib/update_manifest.sh"
  fi

  local rel backup_count=0
  for rel in "${UPDATE_MANIFEST_FILES[@]}"; do
    if [[ -f "${PROJECT_ROOT}/${rel}" ]]; then
      mkdir -p "${rollback_dir}/$(dirname "$rel")"
      cp "${PROJECT_ROOT}/${rel}" "${rollback_dir}/${rel}"
      ((backup_count++))
    fi
  done
  # Also backup version file
  [[ -f "${PROJECT_ROOT}/version" ]] && cp "${PROJECT_ROOT}/version" "${rollback_dir}/version"
  [[ -f "${PROJECT_ROOT}/checksums.txt" ]] && cp "${PROJECT_ROOT}/checksums.txt" "${rollback_dir}/checksums.txt"
  
  log_info "$(msg "已创建回滚备份: ${backup_count} 个文件" "Rollback backup created: ${backup_count} files")"
}

# Priority 3.2: Restore from rollback backup
perform_script_rollback() {
  local rollback_dir="${SBD_STATE_DIR:-/var/lib/sing-box-deve}/rollback"
  
  validate_project_root
  
  if [[ ! -d "$rollback_dir" ]]; then
    die "$(msg "没有可用的回滚备份" "No rollback backup available")"
  fi
  
  # Check if rollback has content
  local file_count
  file_count="$(find "$rollback_dir" -type f 2>/dev/null | wc -l)"
  if [[ "$file_count" -eq 0 ]]; then
    die "$(msg "回滚备份为空" "Rollback backup is empty")"
  fi
  
  # Source manifest
  # shellcheck source=lib/update_manifest.sh
  source "${PROJECT_ROOT}/lib/update_manifest.sh"
  
  log_warn "$(msg "正在从备份恢复..." "Restoring from backup...")"
  
  local rel restored=0
  for rel in "${UPDATE_MANIFEST_FILES[@]}"; do
    if [[ -f "${rollback_dir}/${rel}" ]]; then
      install -D -m 0644 "${rollback_dir}/${rel}" "${PROJECT_ROOT}/${rel}"
      ((restored++))
    fi
  done
  
  # Restore version and checksums
  [[ -f "${rollback_dir}/version" ]] && cp "${rollback_dir}/version" "${PROJECT_ROOT}/version"
  [[ -f "${rollback_dir}/checksums.txt" ]] && cp "${rollback_dir}/checksums.txt" "${PROJECT_ROOT}/checksums.txt"
  
  # Restore executable permissions
  for rel in "${UPDATE_MANIFEST_EXECUTABLES[@]}"; do
    chmod +x "${PROJECT_ROOT}/${rel}" 2>/dev/null || true
  done
  
  log_success "$(msg "回滚完成: 已恢复 ${restored} 个文件" "Rollback complete: ${restored} files restored")"
}

# Priority 2.1: Verify installed files match checksums
verify_installed_files() {
  local checksums_file="${PROJECT_ROOT}/checksums.txt"
  
  if [[ ! -f "$checksums_file" ]]; then
    log_warn "$(msg "校验文件不存在，跳过验证" "Checksums file missing, skipping verification")"
    return 0
  fi
  
  # Source manifest if not already loaded
  if [[ -z "${UPDATE_MANIFEST_FILES[*]:-}" ]]; then
    # shellcheck source=lib/update_manifest.sh
    source "${PROJECT_ROOT}/lib/update_manifest.sh"
  fi
  
  local rel expected actual failed_files=() verified=0
  for rel in "${UPDATE_MANIFEST_FILES[@]}"; do
    if [[ ! -f "${PROJECT_ROOT}/${rel}" ]]; then
      failed_files+=("$rel (missing)")
      continue
    fi
    expected="$(awk -v r="$rel" '$2==r {print $1; exit}' "$checksums_file")"
    if [[ -z "$expected" ]]; then
      # File not in checksums, skip
      continue
    fi
    actual="$(sha256sum "${PROJECT_ROOT}/${rel}" | awk '{print $1}')"
    if [[ "$expected" != "$actual" ]]; then
      failed_files+=("$rel")
    else
      ((verified++))
    fi
  done
  
  if [[ ${#failed_files[@]} -gt 0 ]]; then
    log_error "$(msg "安装后验证失败，以下文件校验不匹配:" "Post-install verification failed, checksum mismatch for:")"
    printf '  - %s\n' "${failed_files[@]}"
    return 1
  fi
  
  log_success "$(msg "安装后验证通过: ${verified} 个文件" "Post-install verification passed: ${verified} files")"
  return 0
}

perform_script_self_update() {
  local mode="${UPDATE_SOURCE:-auto}" base_url ok="false" cb
  cb="$(date +%s)"

  # Priority 1.2: Validate PROJECT_ROOT
  validate_project_root
  
  # Priority 3.1: Check disk space (require at least 10MB free)
  check_update_disk_space 10
  
  # Priority 1.1: Acquire lock to prevent concurrent updates
  acquire_update_lock

  # Source the unified file manifest
  # shellcheck source=lib/update_manifest.sh
  source "${PROJECT_ROOT}/lib/update_manifest.sh"

  local tmp_dir=""
  local _update_cleanup_done="false"

  _update_cleanup() {
    [[ "$_update_cleanup_done" == "true" ]] && return 0
    _update_cleanup_done="true"
    if [[ -n "${tmp_dir:-}" && -d "${tmp_dir}" ]]; then
      rm -rf "$tmp_dir"
    fi
    release_update_lock
  }
  trap _update_cleanup EXIT INT TERM

  # Priority 3.2: Create rollback backup before modifying files
  backup_for_rollback

  while IFS= read -r base_url; do
    [[ -n "$base_url" ]] || continue
    local checksums_file failed rel expected actual
    
    # Priority 2.2: Create temp dir with restricted permissions
    tmp_dir="$(mktemp -d)"
    chmod 700 "$tmp_dir"
    
    checksums_file="${tmp_dir}/checksums.txt"
    failed="false"
    log_info "$(msg "尝试更新源" "Trying update source"): ${base_url}"
    if ! download_file "$(update_url_with_cache_bust "${base_url}/checksums.txt" "$cb")" "$checksums_file"; then
      log_warn "$(msg "无法下载校验文件: ${base_url}/checksums.txt" "Failed to download checksum file: ${base_url}/checksums.txt")"
      failed="true"
    fi

    if [[ "$failed" == "false" ]]; then
      for rel in "${UPDATE_MANIFEST_FILES[@]}"; do
        mkdir -p "${tmp_dir}/$(dirname "$rel")"
        if ! download_file "$(update_url_with_cache_bust "${base_url}/${rel}" "$cb")" "${tmp_dir}/${rel}"; then
          log_warn "$(msg "下载失败: ${rel}" "Download failed: ${rel}")"
          failed="true"; break
        fi
        expected="$(awk -v r="$rel" '$2==r {print $1; exit}' "$checksums_file")"
        if [[ -z "$expected" ]]; then
          log_warn "$(msg "校验表缺少条目: ${rel} (更新源: ${base_url})" "Checksum entry missing: ${rel} (source: ${base_url})")"
          failed="true"
          break
        fi
        actual="$(sha256sum "${tmp_dir}/${rel}" | awk '{print $1}')"
        if [[ "$expected" != "$actual" ]]; then
          log_warn "$(msg "校验失败: ${rel} 期望=${expected} 实际=${actual}" "Checksum mismatch: ${rel} expected=${expected} actual=${actual}")"
          failed="true"
          break
        fi
      done
    fi

    if [[ "$failed" == "false" ]]; then
      # Install all files
      for rel in "${UPDATE_MANIFEST_FILES[@]}"; do
        install -D -m 0644 "${tmp_dir}/${rel}" "${PROJECT_ROOT}/${rel}"
      done
      install -D -m 0644 "$checksums_file" "${PROJECT_ROOT}/checksums.txt"
      
      # Set executable permissions using the manifest
      for rel in "${UPDATE_MANIFEST_EXECUTABLES[@]}"; do
        chmod +x "${PROJECT_ROOT}/${rel}" 2>/dev/null || true
      done
      
      # Priority 2.1: Verify installed files match expected checksums (detect TOCTOU)
      if ! verify_installed_files; then
        log_error "$(msg "安装验证失败，系统可能处于不一致状态。使用 'sb update --rollback' 恢复" "Install verification failed. System may be inconsistent. Use 'sb update --rollback' to restore")"
        rm -rf "$tmp_dir"
        tmp_dir=""
        # Don't break, try next source or fail
        failed="true"
        continue
      fi
      
      rm -rf "$tmp_dir"
      tmp_dir=""
      SBD_ACTIVE_UPDATE_BASE_URL="$base_url"
      ok="true"
      break
    fi
    rm -rf "$tmp_dir"
    tmp_dir=""
    log_warn "$(msg "该更新源失败，尝试下一个" "Update source failed, trying next one")"
  done < <(update_base_candidates "$mode")

  trap - EXIT INT TERM
  release_update_lock

  [[ "$ok" == "true" ]] || die "$(msg "安全更新失败：所有更新源不可用或校验失败。可使用 'sb update --rollback' 恢复" "Secure update failed: all sources unavailable or verification failed. Use 'sb update --rollback' to restore")"
}
