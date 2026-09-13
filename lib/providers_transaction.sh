#!/usr/bin/env bash
# shellcheck disable=SC2034

SBD_ACTIVE_TRANSACTION=""

sbd_transaction_phase() {
  local dir="$1" phase="$2" tmp
  tmp="$(mktemp "$dir/phase.XXXXXX")" || return 1
  printf '%s\n' "$phase" > "$tmp" || return 1
  mv -f "$tmp" "$dir/phase" || return 1
  sbd_sync_directory "$dir"
}

sbd_transaction_begin() (
  local kind="$1" root dir scope path binaries=sidecars
  case "$kind" in
    script-update|script-rollback|uninstall) ;;
    *) sbd_require_supported_runtime || return 1 ;;
  esac
  root="$(sbd_host_state_dir)/transactions"
  [[ ! -e "$root/active" && ! -L "$root/active" ]] || { log_error "Unfinished transaction; run recover first"; return 1; }
  for scope in core argo firewall warp; do
    path="$(sbd_state_path service "$scope")" || return 1
    if [[ -e "$path" || -L "$path" ]]; then
      sbd_managed_unit_file "$path" || { log_error "Service ownership unproven; transaction aborted: $path"; return 1; }
    fi
  done
  (umask 077; mkdir -p "$root") || return 1
  dir="$(mktemp -d "$root/${kind}.XXXXXX")" || return 1
  # Before publication no runtime mutation is allowed. Failed preparation owns
  # only this private directory; never discard an active recovery journal.
  trap 'if [[ ! -e "$root/active" && ! -L "$root/active" ]]; then rm -rf -- "$dir"; fi' EXIT
  sbd_uninstall_validate_roots || return 1
  case "$kind" in install|core-update|kernel-set|uninstall) binaries=true ;; script-update|script-rollback) binaries=false ;; esac
  sbd_state_capture "$dir/before" "$binaries" || return 1
  sbd_transaction_capture_lifecycle "$dir" || return 1
  sbd_transaction_roots > "$dir/roots" || return 1
  sbd_transaction_capture_selectors "$dir" || return 1
  [[ "$kind" != uninstall ]] || sbd_uninstall_prepare_recovery "$dir" || return 1
  for scope in config data bin state run install; do
    case "$scope" in
      config) path="$SBD_CONFIG_DIR" ;; data) path="$SBD_DATA_DIR" ;;
      bin) path="$SBD_BIN_DIR" ;; state) path="$SBD_STATE_DIR" ;;
      run) path="$SBD_RUNTIME_DIR" ;; install) path="$SBD_INSTALL_DIR" ;;
    esac
    [[ -d "$path" ]] || printf '%s\n' "$scope" >> "$dir/created-roots"
  done
  printf '%s\n' "$kind" > "$dir/kind" || return 1
  sbd_transaction_metadata "$dir" > "$dir/metadata.sha256" || return 1
  sbd_transaction_phase "$dir" prepared || return 1
  sbd_atomic_symlink "$dir" "$root/active" || return 1
  printf '%s\n' "$dir"
)

sbd_transaction_restore_firewall() {
  local dir="$1" backend proto port tag created saved
  saved="$dir/before/files/state/firewall-rules.db"
  sbd_restore_firewall_delta "$saved" || return 1
  [[ -f "$dir/firewall-pending" ]] || return 0
  while IFS='|' read -r backend proto port tag created; do
    fw_validate_port_proto "$port" "$proto" || return 1
    fw_validate_tag "$tag" || return 1
    if [[ -f "$saved" ]] && grep -Fq "${backend}|${proto}|${port}|${tag}|" "$saved"; then continue; fi
    fw_remove_rule_by_record "$backend" "$proto" "$port" "$tag" || return 1
  done < "$dir/firewall-pending"
}

sbd_restore_firewall_delta() {
  local saved="$1" backend proto port tag created
  [[ -s "$SBD_RULES_FILE" ]] || return 0
  while IFS='|' read -r backend proto port tag created; do
    [[ -n "$backend" ]] || continue
    if [[ -f "$saved" ]] && grep -Fqx "${backend}|${proto}|${port}|${tag}|${created}" "$saved"; then continue; fi
    fw_validate_port_proto "$port" "$proto" || return 1
    fw_validate_tag "$tag" || return 1
    fw_remove_rule_by_record "$backend" "$proto" "$port" "$tag" || return 1
  done < "$SBD_RULES_FILE"
}

sbd_transaction_recover() (
  local root dir phase scope path script_only=false
  root="$(sbd_host_state_dir)/transactions"
  if [[ ! -L "$root/active" ]]; then
    [[ ! -e "$root/active" ]] || { log_error "Invalid transaction pointer"; return 1; }
    for dir in "$root"/uninstall.*; do
      [[ -d "$dir" && ! -L "$dir" && -f "$dir/phase" ]] || continue
      [[ "$(cat "$dir/phase")" != complete ]] || sbd_uninstall_finalize "$dir" || return 1
    done
    return 0
  fi
  dir="$(readlink -f "$root/active")" || return 1
  [[ "$dir" == "$root/"* && -f "$dir/phase" ]] || { log_error "Invalid transaction pointer"; return 1; }
  phase="$(<"$dir/phase")"
  case "$phase" in prepared|staging|committing|recovery-failed|complete|recovered) ;; *) return 1 ;; esac
  if [[ "$phase" == complete || "$phase" == recovered ]]; then
    if [[ "$phase" == complete && "$(cat "$dir/kind")" == uninstall ]]; then
      sbd_uninstall_finalize "$dir" || return 1
      return 0
    fi
    rm -f "$root/active" || return 1
    sbd_sync_directory "$root"
    return $?
  fi
  log_warn "Recovering interrupted transaction: $(basename "$dir") (${phase})"
  sbd_uninstall_validate_roots || return 1
  [[ "$(sbd_transaction_roots)" == "$(cat "$dir/roots")" ]] || { log_error "Recovery roots differ from saved transaction"; return 1; }
  [[ "$(sbd_transaction_metadata "$dir")" == "$(cat "$dir/metadata.sha256")" ]] || { log_error "Transaction metadata is incomplete or corrupt"; return 1; }
  case "$(cat "$dir/kind")" in script-update|script-rollback) script_only=true ;; esac
  sbd_state_verify "$dir/before" || return 1
  if [[ "$(cat "$dir/kind")" == uninstall ]]; then
    if ! sbd_uninstall_restore "$dir" "$phase"; then
      sbd_transaction_phase "$dir" recovery-failed || return 1
      log_error "Uninstall recovery incomplete. After resolving the reported conflict, run: bash $dir/recover.sh"
      return 1
    fi
    sbd_transaction_phase "$dir" recovered || return 1
    rm -f "$root/active" || return 1
    sbd_sync_directory "$root" || return 1
    sbd_transaction_prune "$dir"
    return $?
  fi
  # Prepared has no runtime mutations; staging may have created host resources.
  if [[ "$script_only" == false && "$phase" != prepared && "$phase" != staging ]]; then
    sbd_service_stop sing-box-deve-argo || return 1
    sbd_service_stop sing-box-deve || return 1
    sbd_service_stop sing-box-deve-warp-socks5 || return 1
    sbd_service_stop sing-box-deve-fw-replay || return 1
  fi
  [[ "$script_only" == true ]] || sbd_transaction_restore_firewall "$dir" || return 1
  sbd_transaction_restore_selectors "$dir" || return 1
  sbd_host_transaction_restore "$dir" || return 1
  sbd_state_restore "$dir/before" || return 1
  if [[ "$script_only" == false ]]; then
    sbd_service_daemon_reload || return 1
    sbd_web_front_restore_service "$dir" || return 1
    sbd_restore_sysctl_runtime "$dir" || return 1
  fi
  if [[ "$script_only" == false && -f "$SBD_CONFIG_DIR/runtime.env" ]]; then
    CFG_RUNTIME_LOADED=false
    provider_cfg_load_runtime_exports || return 1
    fw_replay || return 1
    if sbd_runtime_uses_retired_protocol "${protocols:-}" "${outbound_proxy_mode:-}" "${outbound_proxy_link:-}"; then
      # Script transactions never rewrote these artifacts. Keep them intact so
      # an old deployment remains recoverable without resurrecting its renderer.
      log_warn "$(msg "已恢复旧部署状态；保留旧节点产物，请先用升级前的脚本迁移已停用协议。" "Legacy runtime restored; node artifacts retained. Migrate retired protocols with the previous script first.")"
    else
      write_nodes_output "${engine:-sing-box}" "${protocols:-vless-reality}" || return 1
    fi
  fi
  if [[ "$script_only" == false && "$phase" != prepared && "$phase" != staging ]]; then
    sbd_transaction_restore_lifecycle "$dir" || { sbd_transaction_phase "$dir" recovery-failed; return 1; }
  fi
  if [[ -f "$dir/created-roots" ]]; then
    while IFS= read -r scope; do
      case "$scope" in
        config) path="$SBD_CONFIG_DIR" ;; data) path="$SBD_DATA_DIR" ;;
        bin) path="$SBD_BIN_DIR" ;; state) path="$SBD_STATE_DIR" ;;
        run) path="$SBD_RUNTIME_DIR" ;; install) path="$SBD_INSTALL_DIR" ;;
        *) return 1 ;;
      esac
      [[ "$path" == /* && "$path" != / && ! -L "$path" ]] || return 1
      rm -rf -- "$path" || return 1
    done < "$dir/created-roots"
  fi
  if [[ -f "$dir/packages.before" && -f "$dir/packages.after" ]] && ! cmp -s "$dir/packages.before" "$dir/packages.after"; then
    log_warn "Runtime restored; package changes retained and recorded in ${dir}/packages.{before,after}"
  fi
  sbd_transaction_phase "$dir" recovered || return 1
  rm -f "$root/active" || return 1
  sbd_sync_directory "$root" || return 1
  sbd_transaction_prune "$dir"
)

sbd_transaction_run() (
  local kind="$1" dir scope rc
  shift
  if [[ -n "${SBD_ACTIVE_TRANSACTION:-}" ]]; then "$@"; exit $?; fi
  sbd_transaction_recover || exit 1
  dir="$(sbd_transaction_begin "$kind")" || exit 1
  SBD_ACTIVE_TRANSACTION="$dir"
  trap 'rc=$?; trap - EXIT INT TERM HUP; if (( rc != 0 )); then sbd_transaction_recover || log_error "Recovery incomplete; run recover before further mutation"; fi; exit "$rc"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  case "$kind" in host-change) sbd_transaction_phase "$dir" staging || exit 1 ;;
    config-change) sbd_transaction_phase "$dir" committing || exit 1 ;; esac
  "$@"
  rc=$?
  (( rc == 0 )) || exit "$rc"
  for scope in "$SBD_CONFIG_DIR" "$SBD_DATA_DIR" "$SBD_BIN_DIR"; do
    [[ ! -d "$scope" ]] || sbd_sync_directory "$scope" || exit 1
  done
  sbd_transaction_phase "$dir" complete || exit 1
  if [[ "$kind" == uninstall ]]; then sbd_uninstall_finalize "$dir"; exit $?; fi
  rm -f "$(sbd_host_state_dir)/transactions/active" || exit 1
  sbd_sync_directory "$(sbd_host_state_dir)/transactions" || exit 1
  sbd_transaction_prune "$dir" || exit 1
  [[ ! -L "$SBD_INSTALL_DIR/current" ]] || sbd_release_prune || exit 1
)

sbd_transaction_prune() {
  local keep="$1" root dir phase
  root="$(sbd_host_state_dir)/transactions"
  for dir in "$root"/*; do
    [[ -d "$dir" && ! -L "$dir" && "$dir" != "$keep" && -f "$dir/phase" ]] || continue
    phase="$(<"$dir/phase")"
    [[ "$phase" == complete || "$phase" == recovered ]] || continue
    rm -rf -- "$dir" || return 1
  done
}

sbd_transaction_roots() {
  printf '%s\n' "$SBD_CONFIG_DIR" "$SBD_DATA_DIR" "$SBD_BIN_DIR" "$SBD_STATE_DIR" "$SBD_RUNTIME_DIR" "$SBD_INSTALL_DIR"
}

sbd_transaction_capture_lifecycle() {
  local dir="$1" name status cron
  cron="$(crontab -l 2>/dev/null || true)"
  printf '%s\n' "$cron" | grep -E '# sbd:sing-box-deve(-argo|-warp-socks5|-fw-replay)?$' > "$dir/managed-cron" || [[ ! -s "$dir/managed-cron" ]] || return 1
  for name in sing-box-deve sing-box-deve-argo sing-box-deve-warp-socks5 sing-box-deve-fw-replay; do
    status="$(sbd_service_probe "$name")" || return 1
    printf '%s %s\n' "$name" "$status" >> "$dir/lifecycle" || return 1
  done
}

sbd_service_probe() {
  local name="$1" output load_state active enabled pid
  detect_init_system >&2 || return 1
  case "$SBD_INIT_SYSTEM" in
    systemd)
      output="$(sbd_service_op systemctl show -p LoadState -p ActiveState -p UnitFileState "$name.service")" || return 1
      load_state="$(sed -n 's/^LoadState=//p' <<< "$output")"
      [[ "$load_state" != not-found ]] || { printf 'inactive disabled\n'; return 0; }
      [[ "$load_state" == loaded ]] || { log_error "Service is not safely loadable: $name ($load_state)"; return 1; }
      active="$(sed -n 's/^ActiveState=//p' <<< "$output")"
      case "$active" in active) ;; inactive|failed) active=inactive ;; *) return 1 ;; esac
      enabled="$(sed -n 's/^UnitFileState=//p' <<< "$output")"
      case "$enabled" in enabled) ;; disabled|static|indirect|'') enabled=disabled ;; *) return 1 ;; esac ;;
    nohup)
      active=inactive; enabled=disabled
      if [[ -f "$SBD_RUNTIME_DIR/$name.pid" ]]; then
        IFS= read -r pid < "$SBD_RUNTIME_DIR/$name.pid" || return 1
        [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
        if kill -0 "$pid" 2>/dev/null; then
          nohup_read_identity "$SBD_RUNTIME_DIR/$name.pid" >/dev/null || return 1
          active=active
        fi
      fi
      if crontab -l 2>/dev/null | grep -qE "# sbd:${name}$"; then enabled=enabled; fi ;;
    openrc)
      active=inactive; enabled=disabled
      if [[ -f "/etc/init.d/$name" ]]; then
        output="$(sbd_service_op rc-service "$name" status 2>&1)" || { [[ "$output" == *stopped* ]] || return 1; }
        [[ "$output" != *started* ]] || active=active
        if sbd_service_is_enabled "$name"; then enabled=enabled; fi
      fi ;;
    *) return 1 ;;
  esac
  printf '%s %s\n' "$active" "$enabled"
}

# Restore one previously validated service state after its files are restored.
sbd_restore_service_lifecycle() {
  local name="$1" active="$2" enabled="$3"
  if [[ "$active" == active ]]; then
    case "$name" in
      sing-box-deve) safe_service_restart || return 1 ;;
      sing-box-deve-argo) provider_restart argo || return 1 ;;
      sing-box-deve-warp-socks5)
        sbd_service_restart "$name" "$SBD_BIN_DIR/sing-box" run -c "$SBD_CONFIG_DIR/warp-socks5.json" || return 1
        sbd_service_wait_active "$name" 10 || return 1 ;;
      sing-box-deve-fw-replay) fw_replay || return 1 ;;
    esac
  fi
  if [[ "$enabled" == enabled ]]; then
    case "$SBD_INIT_SYSTEM" in
      systemd) sbd_service_op systemctl enable "$name.service" >/dev/null || return 1 ;;
      openrc) sbd_service_op rc-update add "$name" default || return 1 ;;
      nohup) : ;;
    esac
  else
    case "$SBD_INIT_SYSTEM" in
      systemd)
        [[ -f "$(sbd_state_path service "$(case "$name" in sing-box-deve) echo core ;; sing-box-deve-argo) echo argo ;; sing-box-deve-warp-socks5) echo warp ;; *) echo firewall ;; esac)")" ]] || return 0
        sbd_service_op systemctl disable "$name.service" >/dev/null || return 1 ;;
      openrc) [[ ! -f "/etc/init.d/$name" ]] || sbd_service_op rc-update del "$name" default || return 1 ;;
      nohup) nohup_remove_crontab "$name" || return 1 ;;
    esac
  fi
  return 0
}

sbd_transaction_restore_lifecycle() {
  local dir="$1" name active enabled expected=0
  [[ -f "$dir/lifecycle" ]] || return 1
  while read -r name active enabled; do
    case "$name" in sing-box-deve|sing-box-deve-argo|sing-box-deve-warp-socks5|sing-box-deve-fw-replay) ;; *) return 1 ;; esac
    case "$active:$enabled" in active:enabled|active:disabled|inactive:enabled|inactive:disabled) ;; *) return 1 ;; esac
    expected=$((expected + 1))
    sbd_restore_service_lifecycle "$name" "$active" "$enabled" || return 1
  done < "$dir/lifecycle"
  [[ "$expected" == 4 ]] || return 1
  if [[ "$SBD_INIT_SYSTEM" == nohup ]]; then
    local current
    current="$(crontab -l 2>/dev/null || true)"
    if [[ -s "$dir/managed-cron" || "$current" == *'# sbd:sing-box-deve'* ]]; then
      { printf '%s\n' "$current" | sed -E '/# sbd:sing-box-deve(-argo|-warp-socks5|-fw-replay)?$/d'; cat "$dir/managed-cron"; } | crontab - || return 1
    fi
  fi
}

sbd_transaction_capture_selectors() {
  local dir="$1" name target
  for name in current previous; do
    if [[ -L "$SBD_INSTALL_DIR/$name" ]]; then
      target="$(readlink -f "$SBD_INSTALL_DIR/$name")" || return 1
      [[ "$target" == "$SBD_INSTALL_DIR/releases/"* ]] || return 1
      printf '%s\n' "$target" > "$dir/selector-$name" || return 1
    elif [[ ! -e "$SBD_INSTALL_DIR/$name" ]]; then
      printf 'absent\n' > "$dir/selector-$name" || return 1
    else
      return 1
    fi
  done
}

sbd_transaction_restore_selectors() {
  local dir="$1" name target
  for name in current previous; do
    [[ -f "$dir/selector-$name" ]] || return 1
    target="$(cat "$dir/selector-$name")" || return 1
    if [[ "$target" == absent ]]; then
      [[ ! -e "$SBD_INSTALL_DIR/$name" || -L "$SBD_INSTALL_DIR/$name" ]] || return 1
      rm -f "$SBD_INSTALL_DIR/$name" || return 1
    else
      [[ "$target" == "$SBD_INSTALL_DIR/releases/"* && -d "$target" && ! -L "$target" ]] || return 1
      sbd_release_verify "$target" || return 1
      sbd_atomic_symlink "$target" "$SBD_INSTALL_DIR/$name" || return 1
    fi
  done
}

sbd_transaction_metadata() (
  cd "$1" || return 1
  local file
  for file in roots lifecycle managed-cron selector-current selector-previous kind; do
    [[ -f "$file" && ! -L "$file" ]] || return 1
    sha256sum "$file" || return 1
  done
  if [[ -e created-roots ]]; then
    [[ -f created-roots && ! -L created-roots ]] || return 1
    sha256sum created-roots || return 1
  fi
  if [[ "$(cat kind)" == uninstall ]]; then
    for file in uninstall-scripts uninstall-services uninstall-managed-services uninstall-legacy uninstall-payload.sha256 recover.sh; do
      [[ -f "$file" && ! -L "$file" ]] || return 1
      sha256sum "$file" || return 1
    done
  fi
)
