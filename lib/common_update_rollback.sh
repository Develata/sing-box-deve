#!/usr/bin/env bash

backup_for_rollback() {
  local rollback_dir="${SBD_STATE_DIR:-/var/lib/sing-box-deve}/rollback"
  rm -rf "$rollback_dir"
  mkdir -p "$rollback_dir"
  chmod 700 "$rollback_dir"

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
  [[ -f "${PROJECT_ROOT}/version" ]] && cp "${PROJECT_ROOT}/version" "${rollback_dir}/version"
  [[ -f "${PROJECT_ROOT}/checksums.txt" ]] && cp "${PROJECT_ROOT}/checksums.txt" "${rollback_dir}/checksums.txt"

  log_info "$(msg "已创建回滚备份: ${backup_count} 个文件" "Rollback backup created: ${backup_count} files")"
}

perform_script_rollback() {
  local rollback_dir="${SBD_STATE_DIR:-/var/lib/sing-box-deve}/rollback"

  validate_project_root

  if [[ ! -d "$rollback_dir" ]]; then
    die "$(msg "没有可用的回滚备份" "No rollback backup available")"
  fi

  local file_count
  file_count="$(find "$rollback_dir" -type f 2>/dev/null | wc -l)"
  if [[ "$file_count" -eq 0 ]]; then
    die "$(msg "回滚备份为空" "Rollback backup is empty")"
  fi

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

  [[ -f "${rollback_dir}/version" ]] && cp "${rollback_dir}/version" "${PROJECT_ROOT}/version"
  [[ -f "${rollback_dir}/checksums.txt" ]] && cp "${rollback_dir}/checksums.txt" "${PROJECT_ROOT}/checksums.txt"

  for rel in "${UPDATE_MANIFEST_EXECUTABLES[@]}"; do
    chmod +x "${PROJECT_ROOT}/${rel}" 2>/dev/null || true
  done

  log_success "$(msg "回滚完成: 已恢复 ${restored} 个文件" "Rollback complete: ${restored} files restored")"
}

verify_installed_files() {
  local checksums_file="${PROJECT_ROOT}/checksums.txt"

  if [[ ! -f "$checksums_file" ]]; then
    log_warn "$(msg "校验文件不存在，跳过验证" "Checksums file missing, skipping verification")"
    return 0
  fi

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
