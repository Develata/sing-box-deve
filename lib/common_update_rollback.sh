#!/usr/bin/env bash

perform_script_rollback() {
  sbd_with_mutation_lock sbd_transaction_run script-rollback sbd_release_rollback
}

verify_installed_files() {
  local checksums_file="${PROJECT_ROOT}/checksums.txt"

  if [[ ! -f "$checksums_file" ]]; then
    log_error "$(msg "校验文件不存在，无法验证安装完整性" "Checksums file missing; cannot verify installed files")"
    return 1
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
      failed_files+=("$rel (missing checksum)")
      continue
    fi
    actual="$(sha256sum "${PROJECT_ROOT}/${rel}" | awk '{print $1}')"
    if [[ "$expected" != "$actual" ]]; then
      failed_files+=("$rel")
    else
      ((verified += 1))
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
