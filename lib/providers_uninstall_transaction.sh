#!/usr/bin/env bash
# shellcheck disable=SC2034
# Uninstall reuses the persistent transaction. Its closed snapshots survive the
# deletion roots; only this transaction's proven pre-state may be restored.

sbd_uninstall_finalize() {
  local dir="$1" root
  root="$(sbd_host_state_dir)/transactions"
  [[ "$dir" == "$root/uninstall."* && ! -L "$dir" && "$(cat "$dir/phase")" == complete ]] || return 1
  # Commit is durable and verified. Cleanup errors retain the complete marker;
  # recovery then retries cleanup, never resurrecting a committed uninstall.
  rm -rf -- "$dir/before" "$dir/rescue" "$dir/scripts-before" "$dir/derived-before" "$dir/host" || return 1
  sbd_sync_directory "$dir" || return 1
  rm -f "$root/active" || return 1
  rm -rf -- "$dir" || return 1
  sbd_transaction_prune "" || return 1
  sbd_sync_directory "$root"
}

sbd_uninstall_prepare_recovery() {
  local dir="$1" target name index=0 scope path status record deletion_root
  local SBD_ACTIVE_TRANSACTION="$1"
  local -a targets=()
  detect_init_system >&2 || return 1
  [[ "$SBD_BIN_DIR" == "$SBD_INSTALL_DIR/"* && "$SBD_DATA_DIR" == "$SBD_INSTALL_DIR/"* && "$SBD_RULES_FILE" == "$SBD_STATE_DIR/firewall-rules.db" ]] || return 1
  printf '%s\n' "$SBD_SERVICE_FILE" "$SBD_ARGO_SERVICE_FILE" "$SBD_FW_REPLAY_SERVICE_FILE" "$SBD_WARP_SOCKS_SERVICE_FILE" "$SBD_INIT_SYSTEM" > "$dir/uninstall-services" || return 1
  : > "$dir/uninstall-managed-services" || return 1
  for scope in argo core warp firewall; do
    case "$scope" in core) name=sing-box-deve ;; argo) name=sing-box-deve-argo ;;
      warp) name=sing-box-deve-warp-socks5 ;; firewall) name=sing-box-deve-fw-replay ;; esac
    path="$(sbd_state_path service "$scope")" || return 1
    [[ "$SBD_INIT_SYSTEM" != openrc ]] || path="${SBD_OPENRC_DIR:-/etc/init.d}/$name"
    if [[ "$SBD_INIT_SYSTEM" == nohup ]] || { [[ -f "$path" ]] && sbd_managed_unit_file "$path"; }; then
      printf '%s\n' "$name" >> "$dir/uninstall-managed-services" || return 1
    else
      grep -Fxq "$name inactive disabled" "$dir/lifecycle" || {
        log_error "Cannot uninstall running/enabled service without an owned service file: $name"; return 1;
      }
    fi
  done
  sbd_run_deadline 60 python3 "$PROJECT_ROOT/scripts/runtime-archive.py" pack "$PROJECT_ROOT" "$dir/rescue.tar.gz" || return 1
  mkdir "$dir/rescue" || return 1
  sbd_run_deadline 60 python3 "$PROJECT_ROOT/scripts/runtime-archive.py" extract "$dir/rescue.tar.gz" "$dir/rescue" || return 1
  rm -f "$dir/rescue.tar.gz" "$dir/rescue.tar.gz.sha256" || return 1
  for name in current previous; do
    target="$(cat "$dir/selector-$name")" || return 1
    [[ "$target" == absent ]] || targets+=("$target")
  done
  if [[ -f "$SBD_CONFIG_DIR/runtime.env" ]]; then
    target="$(sbd_read_runtime_script_root)" || return 1
    if [[ "$target" == "$SBD_INSTALL_DIR" || "$target" == "$SBD_INSTALL_DIR/"* ]]; then
      target="$(realpath -e "$target")" || return 1
      targets+=("$target")
    fi
  fi
  : > "$dir/uninstall-scripts" || return 1
  mkdir "$dir/scripts-before" || return 1
  for target in "${targets[@]}"; do
    grep -Fxq -- "$target" "$dir/uninstall-scripts" && continue
    [[ "$target" == "$SBD_INSTALL_DIR" || "$target" == "$SBD_INSTALL_DIR/"* ]] || return 1
    sbd_run_deadline 60 python3 "$PROJECT_ROOT/scripts/runtime-archive.py" backup-script "$target" "$dir/scripts-before/$index" || return 1
    printf '%s\n' "$target" >> "$dir/uninstall-scripts" || return 1
    index=$((index + 1))
  done
  # Preserve the artifacts of retired deployments without invoking a renderer.
  mkdir "$dir/derived-before" || return 1
  for name in nodes.txt nodes-base.txt nodes-sub.txt nodes-model.json jhdy.txt jh_sub.txt sing-ruleset/geoip-cn.srs sing-ruleset/geosite-cn.srs; do
    path="$SBD_DATA_DIR/$name"
    [[ ! -L "$path" ]] || return 1
    mkdir -p "$(dirname "$dir/derived-before/$name")" || return 1
    [[ ! -f "$path" ]] || cp -p "$path" "$dir/derived-before/$name" || return 1
  done
  # Record legacy services that uninstall may remove, before stopping anything.
  : > "$dir/uninstall-legacy" || return 1
  if [[ "${SBD_USER_MODE:-false}" != true && "$SBD_INIT_SYSTEM" == systemd ]]; then
    for name in sing-box xray; do
      path="${SBD_SYSTEMD_DIR:-/etc/systemd/system}/$name.service"
      if [[ -f "$path" ]] && sbd_managed_unit_file "$path"; then
        status="$(sbd_service_probe "$name")" || return 1
        printf '%s %s\n' "$name" "$status" >> "$dir/uninstall-legacy" || return 1
        sbd_host_record_removal "$path" || return 1
      fi
    done
  fi
  for scope in core argo firewall warp; do
    path="$(sbd_state_path service "$scope")" || return 1
    [[ ! -f "$path" ]] || sbd_host_record_removal "$path" || return 1
  done
  if [[ "$SBD_INIT_SYSTEM" == openrc ]]; then
    for name in sing-box-deve sing-box-deve-argo sing-box-deve-fw-replay sing-box-deve-warp-socks5; do
      path="${SBD_OPENRC_DIR:-/etc/init.d}/$name"
      [[ -e "$path" || -L "$path" ]] || continue
      sbd_managed_unit_file "$path" && sbd_host_record_removal "$path" || return 1
    done
  fi
  uninstall_remove_managed_global_bins capture || return 1
  # Static web files inside the deletion roots are rollback-critical too.
  # Only ledger-proven files are included; never copy an entire site/root.
  for record in "$(sbd_host_state_dir)/ownership"/*; do
    [[ -f "$record/path" ]] || continue
    IFS= read -r path < "$record/path" || return 1
    for deletion_root in "$SBD_INSTALL_DIR" "$SBD_CONFIG_DIR" "$SBD_STATE_DIR" "$SBD_RUNTIME_DIR"; do
      [[ "$path" == "$deletion_root/"* ]] || continue
      sbd_host_file_unchanged "$path" || { log_error "Changed managed file inside deletion root: $path"; return 1; }
      sbd_host_record_removal "$path" || return 1
      break
    done
  done
  # Recovery command carries the saved roots, not guesses from runtime.env
  # (which final deletion may have removed). It acquires the normal lock once.
  {
    printf '#!/usr/bin/env bash\nset -euo pipefail\n'
    # shellcheck disable=SC2016 # expanded by the generated recovery entry
    printf 'PROJECT_ROOT=%q\nsource "$PROJECT_ROOT/lib/load.sh"\n' "$dir/rescue"
    for scope in SBD_INSTALL_DIR SBD_CONFIG_DIR SBD_DATA_DIR SBD_BIN_DIR SBD_STATE_DIR SBD_RUNTIME_DIR SBD_RULES_FILE SBD_CONTEXT_FILE SBD_HOST_STATE_DIR SBD_SERVICE_FILE SBD_ARGO_SERVICE_FILE SBD_ARGO_EXEC_FILE SBD_ARGO_TOKEN_FILE SBD_FW_REPLAY_SERVICE_FILE SBD_WARP_SOCKS_SERVICE_FILE SBD_INIT_SYSTEM SBD_USER_MODE SBD_SYSTEMD_DIR SBD_OPENRC_DIR SBD_GLOBAL_BIN_DIR SBD_LAUNCHER_PATH; do
      printf '%s=%q\n' "$scope" "${!scope-}"
    done
    printf 'sbd_with_mutation_lock sbd_transaction_recover\n'
  } > "$dir/recover.sh" || return 1
  chmod 0700 "$dir/recover.sh" || return 1
  mkdir -p "$dir/host" || return 1
  (cd "$dir" && find scripts-before derived-before host -type f -exec sha256sum {} + > uninstall-payload.sha256) || return 1
  sbd_sync_directory "$dir"
}

sbd_uninstall_check_survivors() {
  local dir="$1" scope name path before index=0 target journal hash
  detect_init_system || return 1
  [[ "$(printf '%s\n' "$SBD_SERVICE_FILE" "$SBD_ARGO_SERVICE_FILE" "$SBD_FW_REPLAY_SERVICE_FILE" "$SBD_WARP_SOCKS_SERVICE_FILE" "$SBD_INIT_SYSTEM")" == "$(cat "$dir/uninstall-services")" ]] || return 1
  for name in current previous; do
    path="$SBD_INSTALL_DIR/$name"
    if [[ -L "$path" ]]; then
      [[ "$(realpath -m "$path")" == "$(cat "$dir/selector-$name")" ]] || { log_error "Script selector changed outside uninstall: $path"; return 1; }
    else [[ ! -e "$path" ]] || return 1; fi
  done
  while IFS='|' read -r scope name; do
    path="$(sbd_state_path "$scope" "$name")" || return 1
    before="$dir/before/files/$scope/$name"
    [[ ! -L "$path" && "$(realpath -m "$path")" == "$path" ]] || return 1
    [[ -e "$path" ]] || continue
    if [[ -f "$before" ]] && cmp -s "$before" "$path"; then continue; fi
    journal="$dir/host/$(basename "$(sbd_host_file_record "$path")")"
    if [[ -f "$journal/expected" && -f "$path" ]]; then
      hash="$(sha256sum "$path")" || return 1
      grep -Fxq "${hash%% *}" "$journal/expected" && continue
    fi
    log_error "State changed outside uninstall; keeping recovery snapshot: $path"; return 1
  done < "$dir/before/inventory"
  while IFS= read -r target; do
    sbd_run_deadline 60 python3 "$dir/rescue/scripts/runtime-archive.py" check-script "$dir/scripts-before/$index" "$target" || return 1
    index=$((index + 1))
  done < "$dir/uninstall-scripts"
  for journal in "$dir/host"/*; do
    [[ -d "$journal" ]] || continue
    IFS= read -r path < "$journal/path" || return 1
    [[ "$(realpath -m "$(dirname "$path")")" == "$(dirname "$path")" ]] || return 1
    [[ -e "$path" || -L "$path" ]] || continue
    if [[ -L "$path" ]]; then
      [[ -f "$journal/link-before" && "$(readlink "$path")" == "$(cat "$journal/link-before")" ]] || return 1
    elif [[ -f "$journal/before" ]] && cmp -s "$path" "$journal/before"; then :
    elif [[ -f "$path" && -f "$journal/expected" ]]; then
      hash="$(sha256sum "$path")" || return 1
      grep -Fxq "${hash%% *}" "$journal/expected" || return 1
    else log_error "Host file changed outside uninstall: $path"; return 1; fi
  done
}

sbd_uninstall_restore_file() {
  local before="$1" target="$2" tmp
  [[ ! -L "$target" && "$(realpath -m "$target")" == "$target" ]] || return 1
  if [[ -e "$target" ]]; then cmp -s "$before" "$target"; return $?; fi
  mkdir -p "$(dirname "$target")" || return 1
  tmp="$(mktemp "${target}.recover.XXXXXX")" || return 1
  if ! cp -p "$before" "$tmp"; then rm -f "$tmp"; return 1; fi
  # Exclusive publication: never replace a path recreated during recovery.
  if ! ln "$tmp" "$target"; then rm -f "$tmp"; return 1; fi
  rm -f "$tmp"
}

sbd_uninstall_restore() {
  local dir="$1" phase="$2" scope name path target index=0 active enabled
  [[ "$phase" != prepared ]] || return 0
  PROJECT_ROOT="$dir/rescue"
  sbd_release_verify "$PROJECT_ROOT" || return 1
  if [[ -s "$dir/uninstall-payload.sha256" ]]; then
    (cd "$dir" && sha256sum --status -c uninstall-payload.sha256) || return 1
  fi
  sbd_uninstall_check_survivors "$dir" || return 1
  while IFS= read -r name; do
    sbd_service_stop "$name" || return 1
  done < "$dir/uninstall-managed-services"
  while IFS= read -r target; do
    sbd_run_deadline 60 python3 "$PROJECT_ROOT/scripts/runtime-archive.py" restore-script "$dir/scripts-before/$index" "$target" || return 1
    index=$((index + 1))
  done < "$dir/uninstall-scripts"
  sbd_host_transaction_restore "$dir" || return 1
  # Uninstall only deletes these inputs. Never remove a newly created path that
  # was absent at prepare time; the survivor check rejects it instead.
  while IFS='|' read -r scope name; do
    path="$dir/before/files/$scope/$name"
    [[ -f "$path" ]] || continue
    target="$(sbd_state_path "$scope" "$name")" || return 1
    sbd_uninstall_restore_file "$path" "$target" || return 1
  done < "$dir/before/inventory"
  find "$dir/derived-before" -type f -print0 > "$dir/derived-list" || return 1
  while IFS= read -r -d '' path; do
    [[ -f "$path" ]] || continue
    target="$SBD_DATA_DIR/${path#"$dir/derived-before/"}"
    sbd_uninstall_restore_file "$path" "$target" || return 1
  done < "$dir/derived-list"
  sbd_transaction_restore_selectors "$dir" || return 1
  sbd_service_daemon_reload || return 1
  fw_replay || return 1
  if [[ -f "$SBD_CONFIG_DIR/runtime.env" ]]; then
    CFG_RUNTIME_LOADED=false
    provider_cfg_load_runtime_exports || return 1
  fi
  sbd_transaction_restore_lifecycle "$dir" || return 1
  while read -r name active enabled; do
    case "$name:$active:$enabled" in sing-box:active:enabled|sing-box:active:disabled|xray:active:enabled|xray:active:disabled)
      sbd_service_op systemctl start "$name.service" || return 1 ;;
      sing-box:inactive:*|xray:inactive:*) ;;
      *) return 1 ;;
    esac
    if [[ "$enabled" == enabled ]]; then sbd_service_op systemctl enable "$name.service" || return 1; fi
  done < "$dir/uninstall-legacy"
}
