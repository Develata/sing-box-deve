#!/usr/bin/env bash
# shellcheck disable=SC2034

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

perform_script_self_update() {
  local mode="${UPDATE_SOURCE:-auto}" base_url ok="false" cb
  cb="$(date +%s)"

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
  }
  trap _update_cleanup EXIT INT TERM

  while IFS= read -r base_url; do
    [[ -n "$base_url" ]] || continue
    local checksums_file failed rel expected actual
    tmp_dir="$(mktemp -d)"
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
      # Set executable permissions using the manifest
      for rel in "${UPDATE_MANIFEST_EXECUTABLES[@]}"; do
        chmod +x "${PROJECT_ROOT}/${rel}" 2>/dev/null || true
      done
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

  [[ "$ok" == "true" ]] || die "$(msg "安全更新失败：所有更新源不可用或校验失败" "Secure update failed: all update sources unavailable or checksum verification failed")"
}
