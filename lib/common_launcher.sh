#!/usr/bin/env bash

sbd_is_project_root() {
  local root="$1"
  [[ -n "$root" && -x "$root/sing-box-deve.sh" && -f "$root/lib/common.sh" ]]
}

sbd_is_git_checkout_root() {
  local root="$1"
  sbd_is_project_root "$root" || return 1
  [[ -d "$root/.git" || -f "$root/.git" ]]
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
    "${SBD_CONFIG_DIR}/runtime.env"
}

sbd_read_runtime_script_root() {
  local runtime_file root
  while IFS= read -r runtime_file; do
    [[ -f "$runtime_file" ]] || continue
    root="$(awk -F= '/^script_root=/{print substr($0, index($0, "=") + 1); exit}' "$runtime_file" 2>/dev/null || true)"
    root="$(sbd_unquote_env_value "$root")"
    if [[ -n "$root" ]]; then
      printf '%s\n' "$root"
      return 0
    fi
  done < <(sbd_runtime_env_files)
  return 1
}

sbd_update_runtime_script_root() {
  local new_root="$1" runtime_file tmp updated line seen=0 written=0
  local source_mode="${2:-release}" source_uid="${3:-}" fallback="${4:-}"
  [[ -n "$new_root" ]] || return 1
  case "$source_mode" in
    release) ;;
    git) [[ "$source_uid" =~ ^[0-9]+$ && "$new_root" == /* && "$fallback" == "$SBD_INSTALL_DIR/releases/"* ]] || return 1 ;;
    *) return 1 ;;
  esac
  while IFS= read -r runtime_file; do
    [[ -f "$runtime_file" ]] || continue
    ((seen += 1))
    if ! tmp="$(mktemp "${runtime_file}.tmp.XXXXXX" 2>/dev/null)"; then
      log_warn "$(msg "无法更新运行时入口: ${runtime_file}" "Unable to update runtime entrypoint: ${runtime_file}")"
      continue
    fi
    updated="false"
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" == script_source=* || "$line" == script_source_uid=* || "$line" == script_fallback_root=* ]]; then
        continue
      elif [[ "$line" == script_root=* ]]; then
        sbd_write_env_kv script_root "$new_root" >> "$tmp" || return 1
        updated="true"
      else
        printf '%s\n' "$line" >> "$tmp"
      fi
    done < "$runtime_file"
    [[ "$updated" == "true" ]] || sbd_write_env_kv script_root "$new_root" >> "$tmp" || return 1
    if [[ "$source_mode" == git ]]; then
      sbd_write_env_kv script_source git >> "$tmp" || return 1
      sbd_write_env_kv script_source_uid "$source_uid" >> "$tmp" || return 1
      sbd_write_env_kv script_fallback_root "$fallback" >> "$tmp" || return 1
    fi
    sbd_seal_runtime_file "$tmp" || { rm -f "$tmp"; return 1; }
    if ! sbd_commit_file_with_backups "$runtime_file" "$tmp" 600; then
      rm -f "$tmp" 2>/dev/null || true
      log_warn "$(msg "无法写入运行时入口: ${runtime_file}" "Unable to write runtime entrypoint: ${runtime_file}")"
      continue
    fi
    ((written += 1))
  done < <(sbd_runtime_env_files)
  (( seen == 0 || written > 0 ))
}

sbd_persist_script_root_if_needed() {
  local source_dir="${1:-${PROJECT_ROOT:-}}"
  if sbd_source_is_git; then
    sbd_check_script_source
    return $?
  fi

  sbd_is_project_root "$source_dir" || {
    log_warn "$(msg "无法找到完整脚本源，跳过脚本持久化" "Unable to find complete script source, skipping script persistence")"
    return 0
  }

  sbd_release_install_tree "$source_dir" || return 1
  PROJECT_ROOT="$(readlink -f "$SBD_INSTALL_DIR/current")" || return 1

}

write_sb_launcher() {
  local launcher_path="${1:-${SBD_LAUNCHER_PATH:-/usr/local/bin/sb}}" launcher_tmp
  if [[ $# == 0 && -z "${SBD_LAUNCHER_PATH:-}" && "${SBD_USER_MODE:-false}" == true ]]; then
    launcher_path="${HOME}/.local/bin/sb"
  fi
  if [[ -e "$launcher_path" || -L "$launcher_path" ]]; then
    sbd_managed_launcher "$launcher_path" || { log_error "Launcher path belongs to another program: $launcher_path"; return 1; }
  fi
  mkdir -p "$(dirname "$launcher_path")" || return 1
  launcher_tmp="$(mktemp "${launcher_path}.tmp.XXXXXX")" || return 1
  cat > "$launcher_tmp" <<'SBEOF'
#!/usr/bin/env bash
set -euo pipefail
# Managed by sing-box-deve: launcher-v1
SBEOF
  declare -f sbd_unquote_env_value sbd_verify_runtime_file sbd_git_source_verify log_error >> "$launcher_tmp" || return 1
  printf 'runtime_file=%q\n' "${SBD_CONFIG_DIR}/runtime.env" >> "$launcher_tmp" || return 1
  printf 'recovery_selector=%q\n' "$SBD_INSTALL_DIR/current" >> "$launcher_tmp" || return 1
  printf 'releases_dir=%q\n' "$SBD_INSTALL_DIR/releases" >> "$launcher_tmp" || return 1
  cat >> "$launcher_tmp" <<'SBEOF'

is_sbd_project_root() {
  local root="$1"
  [[ -x "$root/sing-box-deve.sh" && -f "$root/lib/common.sh" ]]
}

read_sbd_version() {
  local root="$1"
  if [[ -f "$root/version" ]]; then
    tr -d '[:space:]' < "$root/version"
  else
    printf '%s\n' "v0.0.0"
  fi
}

script_root=""
source_mode=release
source_uid=""
unset SBD_GIT_SOURCE_STAMP SBD_GIT_SOURCE_UID

for _p in "$runtime_file"; do
  if [[ -f "$_p" ]]; then
    sbd_verify_runtime_file "$_p" || exit 1
    script_root="$(awk -F= '/^script_root=/{print substr($0, index($0, "=") + 1); exit}' "$_p" 2>/dev/null || true)"
    script_root="$(sbd_unquote_env_value "$script_root")"
    source_mode="$(awk -F= '/^script_source=/{print substr($0, index($0, "=") + 1); exit}' "$_p")"
    source_mode="$(sbd_unquote_env_value "$source_mode")"
    source_mode="${source_mode:-release}"
    source_uid="$(awk -F= '/^script_source_uid=/{print substr($0, index($0, "=") + 1); exit}' "$_p")"
    source_uid="$(sbd_unquote_env_value "$source_uid")"
    [[ -n "$script_root" ]] && break
  fi
done

if [[ "${1:-}" == --rollback-source ]]; then
  [[ $# == 1 && "$source_mode" == git ]] || { echo '[ERROR] --rollback-source requires a Git binding and no other arguments' >&2; exit 2; }
  recovery_root="$(readlink -f "$recovery_selector")"
  [[ "$recovery_root" == "$releases_dir/"* && -x "$recovery_root/sing-box-deve.sh" ]] || exit 1
  timeout -k 3s 30s python3 "$recovery_root/scripts/runtime-archive.py" verify "$recovery_root" || exit 1
  exec "$recovery_root/sing-box-deve.sh" update --rollback
fi

case "$source_mode" in
  git)
    if ! SBD_GIT_SOURCE_STAMP="$(sbd_git_source_verify "$script_root" "$source_uid")"; then
      echo '[ERROR] Bound Git source is unavailable or invalid. Restore with: sb --rollback-source' >&2
      exit 1
    fi
    SBD_GIT_SOURCE_UID="$source_uid"
    export SBD_GIT_SOURCE_STAMP SBD_GIT_SOURCE_UID
    ;;
  release) ;;
  *) echo '[ERROR] Invalid script source mode' >&2; exit 1 ;;
esac

if [[ -z "$script_root" || ! -x "$script_root/sing-box-deve.sh" ]]; then
  echo '[ERROR] Unable to locate installed source. Use a verified checkout to run update --script; preserve the running core.' >&2
  exit 1
fi

script_root="$(cd "$script_root" && pwd -P)"

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
  chmod 0755 "$launcher_tmp" || { rm -f "$launcher_tmp"; return 1; }
  sbd_host_file_publish "$launcher_path" "$launcher_tmp" || { rm -f "$launcher_tmp"; return 1; }
}

sbd_managed_launcher() {
  local file="$1"
  [[ -f "$file" && ! -L "$file" ]] || return 1
  grep -q '^# Managed by sing-box-deve: launcher-v1$' "$file" && return 0
  # Legacy launcher migration: require project-specific structure, not its name.
  grep -q '^is_sbd_project_root()' "$file" && grep -q 'sing-box-deve/runtime.env' "$file"
}
