#!/usr/bin/env bash
# shellcheck disable=SC2034

perform_git_update() {
  local branch old_commit new_commit
  branch="$(get_git_branch)"
  old_commit="$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")"

  log_info "$(msg "检测到 Git 仓库，使用 git pull 更新" "Git repository detected, updating via git pull")"
  log_info "$(msg "当前分支" "Current branch"): ${branch}"
  log_info "$(msg "当前提交" "Current commit"): ${old_commit}"

  if ! git -C "$PROJECT_ROOT" diff --quiet 2>/dev/null; then
    log_warn "$(msg "检测到本地修改，将尝试 stash 保存" "Local modifications detected, will stash changes")"
    if ! git -C "$PROJECT_ROOT" stash push -m "sing-box-deve auto-stash before update" 2>/dev/null; then
      die "$(msg "无法 stash 本地修改，请手动处理后重试" "Failed to stash local changes, please handle manually")"
    fi
    log_info "$(msg "本地修改已暂存" "Local changes stashed")"
  fi

  log_info "$(msg "正在从远程拉取更新..." "Fetching updates from remote...")"
  if ! git -C "$PROJECT_ROOT" fetch origin "$branch" 2>&1; then
    die "$(msg "git fetch 失败" "git fetch failed")"
  fi

  if ! git -C "$PROJECT_ROOT" pull --ff-only origin "$branch" 2>&1; then
    log_warn "$(msg "快进合并失败，尝试 rebase" "Fast-forward failed, trying rebase")"
    if ! git -C "$PROJECT_ROOT" pull --rebase origin "$branch" 2>&1; then
      die "$(msg "git pull 失败，请手动解决冲突" "git pull failed, please resolve conflicts manually")"
    fi
  fi

  new_commit="$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")"

  if [[ "$old_commit" == "$new_commit" ]]; then
    log_info "$(msg "已是最新版本" "Already up to date") (${new_commit})"
  else
    log_success "$(msg "Git 更新完成" "Git update complete"): ${old_commit} -> ${new_commit}"
  fi

  # shellcheck source=lib/update_manifest.sh
  source "${PROJECT_ROOT}/lib/update_manifest.sh"
  local rel
  for rel in "${UPDATE_MANIFEST_EXECUTABLES[@]}"; do
    chmod +x "${PROJECT_ROOT}/${rel}" 2>/dev/null || true
  done

  return 0
}

perform_download_update() {
  local mode="${UPDATE_SOURCE:-auto}" base_url ok="false" cb
  cb="$(date +%s)"

  # shellcheck source=lib/update_manifest.sh
  source "${PROJECT_ROOT}/lib/update_manifest.sh"

  local tmp_dir=""
  local _update_cleanup_done="false"

  # shellcheck disable=SC2317 # Called indirectly via trap.
  _update_cleanup() {
    [[ "${_update_cleanup_done:-false}" == "true" ]] && return 0
    _update_cleanup_done="true"
    if [[ -n "${tmp_dir:-}" && -d "${tmp_dir}" ]]; then
      rm -rf "$tmp_dir"
    fi
  }
  trap _update_cleanup EXIT INT TERM

  backup_for_rollback

  while IFS= read -r base_url; do
    [[ -n "$base_url" ]] || continue
    local checksums_file failed rel expected actual

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
      for rel in "${UPDATE_MANIFEST_FILES[@]}"; do
        install -D -m 0644 "${tmp_dir}/${rel}" "${PROJECT_ROOT}/${rel}"
      done
      install -D -m 0644 "$checksums_file" "${PROJECT_ROOT}/checksums.txt"

      for rel in "${UPDATE_MANIFEST_EXECUTABLES[@]}"; do
        chmod +x "${PROJECT_ROOT}/${rel}" 2>/dev/null || true
      done

      if ! verify_installed_files; then
        log_error "$(msg "安装验证失败，系统可能处于不一致状态。使用 'sb update --rollback' 恢复" "Install verification failed. System may be inconsistent. Use 'sb update --rollback' to restore")"
        rm -rf "$tmp_dir"
        tmp_dir=""
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

  [[ "$ok" == "true" ]] || die "$(msg "安全更新失败：所有更新源不可用或校验失败。可使用 'sb update --rollback' 恢复" "Secure update failed: all sources unavailable or verification failed. Use 'sb update --rollback' to restore")"
}

perform_script_self_update() {
  validate_project_root
  check_update_disk_space 10
  acquire_update_lock

  if is_git_repo; then
    perform_git_update
  else
    perform_download_update
  fi

  release_update_lock
}
