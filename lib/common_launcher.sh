#!/usr/bin/env bash

sbd_is_project_root() {
  local root="$1"
  [[ -n "$root" && -x "$root/sing-box-deve.sh" && -f "$root/lib/common.sh" ]]
}

sbd_is_git_checkout_root() {
  local root="$1"
  sbd_is_project_root "$root" || return 1
  [[ -d "$root/.git" ]]
}

sbd_is_ephemeral_script_root() {
  local root="$1"
  case "$root" in
    ""|/tmp/*|/var/tmp/*|/dev/fd*|/proc/*/fd/*|/run/*) return 0 ;;
    *) return 1 ;;
  esac
}

sbd_read_script_version() {
  local root="$1"
  if [[ -f "$root/version" ]]; then
    tr -d '[:space:]' < "$root/version"
  else
    printf '%s\n' "v0.0.0"
  fi
}

sbd_normalize_script_version() {
  local raw="${1#v}" core major minor patch extra
  core="${raw%%[-+]*}"
  IFS=. read -r major minor patch extra <<< "$core"
  [[ -z "${extra:-}" ]] || return 1
  [[ "${major:-}" =~ ^[0-9]+$ ]] || return 1
  [[ "${minor:-0}" =~ ^[0-9]+$ ]] || return 1
  [[ "${patch:-0}" =~ ^[0-9]+$ ]] || return 1
  printf '%d.%d.%d\n' "$major" "${minor:-0}" "${patch:-0}"
}

sbd_script_version_ge() {
  local left right lm ln lp rm rn rp
  left="$(sbd_normalize_script_version "${1:-}")" || return 1
  right="$(sbd_normalize_script_version "${2:-}")" || return 1
  IFS=. read -r lm ln lp <<< "$left"
  IFS=. read -r rm rn rp <<< "$right"
  (( lm > rm )) && return 0
  (( lm < rm )) && return 1
  (( ln > rn )) && return 0
  (( ln < rn )) && return 1
  (( lp >= rp ))
}

sbd_runtime_env_files() {
  printf '%s\n' \
    "/etc/sing-box-deve/runtime.env" \
    "${HOME:-}/sing-box-deve/config/runtime.env"
}

sbd_read_runtime_script_root() {
  local runtime_file root
  while IFS= read -r runtime_file; do
    [[ -f "$runtime_file" ]] || continue
    root="$(awk -F= '/^script_root=/{print substr($0, index($0, "=") + 1); exit}' "$runtime_file" 2>/dev/null || true)"
    if [[ -n "$root" ]]; then
      printf '%s\n' "$root"
      return 0
    fi
  done < <(sbd_runtime_env_files)
  return 1
}

sbd_update_runtime_script_root() {
  local new_root="$1" runtime_file tmp updated line seen=0 written=0
  [[ -n "$new_root" ]] || return 1
  while IFS= read -r runtime_file; do
    [[ -f "$runtime_file" ]] || continue
    ((seen += 1))
    if ! tmp="$(mktemp "${runtime_file}.tmp.XXXXXX" 2>/dev/null)"; then
      log_warn "$(msg "无法更新运行时入口: ${runtime_file}" "Unable to update runtime entrypoint: ${runtime_file}")"
      continue
    fi
    updated="false"
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" == script_root=* ]]; then
        printf 'script_root=%s\n' "$new_root" >> "$tmp"
        updated="true"
      else
        printf '%s\n' "$line" >> "$tmp"
      fi
    done < "$runtime_file"
    [[ "$updated" == "true" ]] || printf 'script_root=%s\n' "$new_root" >> "$tmp"
    if ! sbd_commit_file_with_backups "$runtime_file" "$tmp" 600; then
      rm -f "$tmp" 2>/dev/null || true
      log_warn "$(msg "无法写入运行时入口: ${runtime_file}" "Unable to write runtime entrypoint: ${runtime_file}")"
      continue
    fi
    ((written += 1))
  done < <(sbd_runtime_env_files)
  (( seen == 0 || written > 0 ))
}

sbd_choose_authoritative_script_root() {
  local current="${1:-${PROJECT_ROOT:-}}" runtime_root runtime_version current_version

  if sbd_is_project_root "$current" && ! sbd_is_ephemeral_script_root "$current"; then
    printf '%s\n' "$current"
    return 0
  fi

  runtime_root="$(sbd_read_runtime_script_root 2>/dev/null || true)"
  if sbd_is_project_root "$runtime_root"; then
    printf '%s\n' "$runtime_root"
    return 0
  fi

  if sbd_is_project_root "$current"; then
    printf '%s\n' "$current"
    return 0
  fi

  runtime_version="v0.0.0"
  [[ -n "$runtime_root" ]] && runtime_version="$(sbd_read_script_version "$runtime_root")"
  for current in "$PWD" "$PWD/sing-box-deve" "${HOME:-}/sing-box-deve" "/root/sing-box-deve" "/opt/sing-box-deve" "/opt/sing-box-deve/script" "/usr/local/src/sing-box-deve"; do
    sbd_is_git_checkout_root "$current" || continue
    current_version="$(sbd_read_script_version "$current")"
    if sbd_script_version_ge "$current_version" "$runtime_version"; then
      printf '%s\n' "$current"
      return 0
    fi
  done
}

sbd_persist_script_root_if_needed() {
  local source_dir="${1:-${PROJECT_ROOT:-}}" persist_dir="${SBD_INSTALL_DIR:-/opt/sing-box-deve}/script"
  local rel copied=0

  sbd_is_project_root "$source_dir" || {
    log_warn "$(msg "无法找到完整脚本源，跳过脚本持久化" "Unable to find complete script source, skipping script persistence")"
    return 0
  }

  if ! sbd_is_ephemeral_script_root "$source_dir"; then
    PROJECT_ROOT="$source_dir"
    sbd_update_runtime_script_root "$PROJECT_ROOT" 2>/dev/null || true
    return 0
  fi

  log_info "$(msg "当前脚本位于临时目录，正在持久化到 ${persist_dir}" "Current script is in a temporary directory; persisting to ${persist_dir}")"
  mkdir -p "$persist_dir"
  # shellcheck source=lib/update_manifest.sh
  source "${source_dir}/lib/update_manifest.sh"
  for rel in "${UPDATE_MANIFEST_FILES[@]}"; do
    [[ -f "${source_dir}/${rel}" ]] || continue
    install -D -m 0644 "${source_dir}/${rel}" "${persist_dir}/${rel}"
    ((copied += 1))
  done
  [[ -f "${source_dir}/checksums.txt" ]] && install -D -m 0644 "${source_dir}/checksums.txt" "${persist_dir}/checksums.txt"
  for rel in "${UPDATE_MANIFEST_EXECUTABLES[@]}"; do
    chmod +x "${persist_dir}/${rel}" 2>/dev/null || true
  done
  PROJECT_ROOT="$persist_dir"
  sbd_update_runtime_script_root "$PROJECT_ROOT" 2>/dev/null || true
  log_success "$(msg "脚本已持久化到 ${persist_dir} (${copied} 个文件)" "Script persisted to ${persist_dir} (${copied} files)")"
}

write_sb_launcher() {
  local launcher_path="${1:-/usr/local/bin/sb}"
  cat > "$launcher_path" <<'SBEOF'
#!/usr/bin/env bash
set -euo pipefail

is_sbd_project_root() {
  local root="$1"
  [[ -x "$root/sing-box-deve.sh" && -f "$root/lib/common.sh" ]]
}

is_sbd_git_checkout() {
  local root="$1" origin=""
  is_sbd_project_root "$root" || return 1
  [[ -d "$root/.git" ]] || return 1
  if command -v git >/dev/null 2>&1; then
    origin="$(git -C "$root" config --get remote.origin.url 2>/dev/null || true)"
    [[ -z "$origin" || "$origin" == *sing-box-deve* ]] || return 1
  fi
}

read_sbd_version() {
  local root="$1"
  if [[ -f "$root/version" ]]; then
    tr -d '[:space:]' < "$root/version"
  else
    printf '%s\n' "v0.0.0"
  fi
}

normalize_sbd_version() {
  local raw="${1#v}" core major minor patch extra
  core="${raw%%[-+]*}"
  IFS=. read -r major minor patch extra <<< "$core"
  [[ -z "${extra:-}" ]] || return 1
  [[ "${major:-}" =~ ^[0-9]+$ ]] || return 1
  [[ "${minor:-0}" =~ ^[0-9]+$ ]] || return 1
  [[ "${patch:-0}" =~ ^[0-9]+$ ]] || return 1
  printf '%d.%d.%d\n' "$major" "${minor:-0}" "${patch:-0}"
}

sbd_version_ge() {
  local left right lm ln lp rm rn rp
  left="$(normalize_sbd_version "${1:-}")" || return 1
  right="$(normalize_sbd_version "${2:-}")" || return 1
  IFS=. read -r lm ln lp <<< "$left"
  IFS=. read -r rm rn rp <<< "$right"
  (( lm > rm )) && return 0
  (( lm < rm )) && return 1
  (( ln > rn )) && return 0
  (( ln < rn )) && return 1
  (( lp >= rp ))
}

choose_git_checkout_root() {
  local reference_root="${1:-}" reference_version candidate candidate_version
  local -a candidates=(
    "$PWD"
    "$PWD/sing-box-deve"
  )

  if [[ -n "$reference_root" && -f "$reference_root/version" ]]; then
    reference_version="$(read_sbd_version "$reference_root")"
  else
    reference_version="v0.0.0"
  fi

  for candidate in "${candidates[@]}"; do
    [[ -n "$candidate" ]] || continue
    is_sbd_git_checkout "$candidate" || continue
    candidate_version="$(read_sbd_version "$candidate")"
    if sbd_version_ge "$candidate_version" "$reference_version"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
}

script_root=""

for _p in "/etc/sing-box-deve/runtime.env" "${HOME:-}/sing-box-deve/config/runtime.env"; do
  if [[ -f "$_p" ]]; then
    script_root="$(awk -F= '/^script_root=/{print substr($0, index($0, "=") + 1); exit}' "$_p" 2>/dev/null || true)"
    [[ -n "$script_root" ]] && break
  fi
done

git_root="$(choose_git_checkout_root "$script_root" || true)"
[[ -n "$git_root" ]] && script_root="$git_root"

if [[ -n "$script_root" && -x "$script_root/sing-box-deve.sh" ]]; then
  :
else
  script_root=""
  for candidate in "/opt/sing-box-deve/script" "/opt/sing-box-deve" "/usr/local/share/sing-box-deve" "$PWD/sing-box-deve"; do
    if is_sbd_project_root "$candidate"; then
      script_root="$candidate"
      break
    fi
  done
fi

if [[ -z "$script_root" || ! -x "$script_root/sing-box-deve.sh" ]]; then
  echo "[ERROR] Unable to locate sing-box-deve.sh. Reinstall with: sudo bash ./sing-box-deve.sh install ..." >&2
  exit 1
fi

case "${1:-}" in
  --print-root)
    printf '%s\n' "$script_root"
    exit 0
    ;;
  --print-version)
    read_sbd_version "$script_root"
    exit 0
    ;;
esac

if [[ $# -eq 0 ]]; then
  exec "$script_root/sing-box-deve.sh" menu
fi

exec "$script_root/sing-box-deve.sh" "$@"
SBEOF
  chmod +x "$launcher_path"
}
