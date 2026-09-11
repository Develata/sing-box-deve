#!/usr/bin/env bash

sbd_read_source_state() {
  local file="$SBD_CONFIG_DIR/runtime.env"
  [[ -f "$file" ]] || return 0
  sbd_verify_runtime_file "$file" && sbd_parse_env_file "$file" "$1"
}

sbd_source_is_git() {
  local -A source_state=()
  sbd_read_source_state source_state || return 1
  [[ "${source_state[script_source]:-release}" == git ]]
}

sbd_git_source_path_allowed() {
  local path="$1" managed
  sbd_is_ephemeral_script_root "$path" && { log_error "Git binding requires a permanent directory"; return 1; }
  for managed in "$SBD_INSTALL_DIR" "$SBD_CONFIG_DIR" "$SBD_STATE_DIR" "$SBD_RUNTIME_DIR" "$SBD_BIN_DIR" "$SBD_DATA_DIR" "$(sbd_host_state_dir)"; do
    managed="$(realpath -m "$managed")" || return 1
    [[ "$path" != "$managed" && "$path" != "$managed/"* && "$managed" != "$path/"* ]] || {
      log_error "Git source must be outside managed runtime roots: $managed"; return 1;
    }
  done
}

sbd_bind_git_source() {
  local root="$1" owner fallback
  local -A source_state=()
  [[ "$root" == /* ]] || { log_error "--bind-git requires an absolute directory"; return 1; }
  root="$(cd "$root" && pwd -P)" || return 1
  sbd_git_source_path_allowed "$root" || return 1
  owner="$(stat -c %u "$root")" || return 1
  sbd_git_source_validate "$root" "$owner" || return 1
  sbd_read_source_state source_state || return 1
  [[ -n "${source_state[script_root]:-}" ]] || { log_error "Install a runtime before binding Git source"; return 1; }
  sbd_validate_runtime_values source_state || return 1
  if [[ "${source_state[script_source]:-release}" == git ]]; then
    fallback="${source_state[script_fallback_root]}"
  else
    sbd_release_migrate_legacy || return 1
    fallback="$(readlink -f "$SBD_INSTALL_DIR/current")" || return 1
    # Freeze the new recovery implementation too: a missing checkout must not
    # prevent rollback, even when the preceding release predates Git binding.
    sbd_release_install_tree "$root" || return 1
  fi
  [[ "$fallback" == "$SBD_INSTALL_DIR/releases/"* ]] || return 1
  sbd_release_verify "$fallback" || return 1
  sbd_git_source_validate "$root" "$owner" || return 1
  write_sb_launcher || return 1
  sbd_update_runtime_script_root "$root" git "$owner" "$fallback" || return 1
  log_success "$(msg "已绑定 Git 源码" "Git source bound"): $root"
  log_info "$(msg "git pull 前退出菜单并暂停管理命令；拉取后重新运行 sb。源码目录由你维护，卸载会保留该目录。" "Exit menus and pause management commands before git pull; run sb again afterward. You maintain the checkout; uninstall preserves it.")"
}

sbd_rollback_git_source() {
  local fallback
  local -A source_state=()
  sbd_read_source_state source_state || return 1
  fallback="${source_state[script_fallback_root]:-}"
  [[ "$fallback" == "$SBD_INSTALL_DIR/releases/"* && "$(realpath -e "$fallback")" == "$fallback" ]] || return 1
  sbd_release_verify "$fallback" || return 1
  sbd_atomic_symlink "$fallback" "$SBD_INSTALL_DIR/current" || return 1
  sbd_update_runtime_script_root "$SBD_INSTALL_DIR/current" || return 1
  write_sb_launcher || return 1
  log_success "$(msg "已解除 Git 绑定，恢复绑定前的完整脚本版本" "Git binding removed; restored the complete pre-binding release"): $(basename "$fallback")"
}

sbd_check_script_source() {
  local -A source_state=()
  sbd_read_source_state source_state || return 1
  if [[ "${source_state[script_source]:-release}" == git ]]; then
    sbd_git_source_validate "${source_state[script_root]}" "${source_state[script_source_uid]}" || return 1
    log_success "$(msg "已校验绑定源码；git pull 后的新调用直接使用新代码，无需再次复制。" "Bound source verified; new invocations use pulled code without copying it again.")"
  else
    sbd_release_verify "${source_state[script_root]:-$PROJECT_ROOT}" || return 1
    log_success "$(msg "完整 Release 校验通过" "Complete release verified")"
  fi
}

# Configuration rebuilds preserve source authority; only source transactions
# change these fields. Omit new keys in release mode for older-release rollback.
sbd_write_runtime_source() {
  local -A source_state=()
  sbd_read_source_state source_state || return 1
  if [[ "${source_state[script_source]:-release}" == git ]]; then
    local key
    for key in script_root script_source script_source_uid script_fallback_root; do
      sbd_write_env_kv "$key" "${source_state[$key]}" || return 1
    done
  elif [[ -L "$SBD_INSTALL_DIR/current" ]]; then
    sbd_write_env_kv script_root "$SBD_INSTALL_DIR/current"
  else
    sbd_write_env_kv script_root "$PROJECT_ROOT"
  fi
}

sbd_show_script_source() {
  local stamp
  if sbd_is_git_checkout_root "$PROJECT_ROOT"; then
    stamp="$(sbd_git_source_verify "$PROJECT_ROOT" "$(stat -c %u "$PROJECT_ROOT")" 2>/dev/null)" || {
      log_warn "$(msg "执行源码尚未通过绑定校验" "Executing checkout has not passed binding validation"): $PROJECT_ROOT"; return 0;
    }
    log_info "$(msg "执行来源: Git" "Executing source: Git") | ${stamp:0:12} | ${stamp##*:} | $PROJECT_ROOT"
  else
    log_info "$(msg "执行来源: Release" "Executing source: Release") | $PROJECT_ROOT"
  fi
}
