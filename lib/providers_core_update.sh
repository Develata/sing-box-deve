#!/usr/bin/env bash
# shellcheck disable=SC2030,SC2031

provider_core_candidate_build() {
  local target_engine="$1" protocols_csv="$2" candidate_root="$3"
  (
    local live_data="$SBD_DATA_DIR" scope name
    mkdir -p "$candidate_root/data" "$candidate_root/config" || exit 1
    while IFS='|' read -r scope name; do
      [[ "$scope" == data && -f "$live_data/$name" ]] || continue
      [[ "$name" != engine-version || ! -f "$candidate_root/data/engine-version" ]] || continue
      cp -p "$live_data/$name" "$candidate_root/data/$name" || exit 1
    done < <(sbd_state_inventory false)
    for name in sing-ruleset clash-ruleset; do
      [[ ! -d "$live_data/$name" ]] || cp -a "$live_data/$name" "$candidate_root/data/" || exit 1
    done
    for name in config.json xray-config.json; do
      [[ ! -f "$SBD_CONFIG_DIR/$name" ]] || cp -p "$SBD_CONFIG_DIR/$name" "$candidate_root/config/" || exit 1
    done
    SBD_CONFIG_DIR="$candidate_root/config"
    SBD_BIN_DIR="$candidate_root/bin"
    SBD_DATA_DIR="$candidate_root/data"
    case "$target_engine" in
      sing-box) build_sing_box_config "$protocols_csv" || exit 1 ;;
      xray) build_xray_config "$protocols_csv" || exit 1 ;;
      *) exit 1 ;;
    esac
    validate_generated_config "$target_engine" false || exit 1
  )
}

provider_core_candidate_data_commit() {
  local candidate_root="$1" scope name source target tmp
  while IFS='|' read -r scope name; do
    [[ "$scope" == data ]] || continue
    source="$candidate_root/data/$name"; target="$SBD_DATA_DIR/$name"
    [[ -f "$source" ]] || continue
    tmp="$(mktemp "${target}.candidate.XXXXXX")" || return 1
    cp -p "$source" "$tmp" || { rm -f "$tmp"; return 1; }
    mv -f "$tmp" "$target" || { rm -f "$tmp"; return 1; }
  done < <(sbd_state_inventory false)
  for name in sing-ruleset clash-ruleset; do
    [[ ! -d "$candidate_root/data/$name" ]] || cp -a "$candidate_root/data/$name" "$SBD_DATA_DIR/" || return 1
  done
}

provider_core_candidate_install() {
  local target_engine="$1" candidate_root="$2" target_tag="${3:-latest}"
  (
    SBD_BIN_DIR="${candidate_root}/bin"
    SBD_DATA_DIR="${candidate_root}/data"
    SBD_CACHE_DIR="${candidate_root}/cache"
    mkdir -p "$SBD_BIN_DIR" "$SBD_DATA_DIR" "$SBD_CACHE_DIR" || exit 1
    install_engine_binary "$target_engine" "$target_tag" || exit 1
    [[ -x "${SBD_BIN_DIR}/${target_engine}" ]]
  )
}

provider_core_candidate_binary_commit() {
  local target_engine="$1" candidate_root="$2" candidate live tmp asset
  candidate="${candidate_root}/bin/${target_engine}"
  live="${SBD_BIN_DIR}/${target_engine}"
  [[ -x "$candidate" ]] || return 1
  # The purego Naive client needs its matching shared library beside the core.
  # Both files belong to the binary snapshot and recover as one transaction.
  if [[ "$target_engine" == sing-box ]]; then
    if [[ -f "$candidate_root/bin/libcronet.so" ]]; then
      tmp="$(mktemp "$SBD_BIN_DIR/libcronet.so.candidate.XXXXXX")" || return 1
      cp -p "$candidate_root/bin/libcronet.so" "$tmp" || { rm -f "$tmp"; return 1; }
      mv -f "$tmp" "$SBD_BIN_DIR/libcronet.so" || { rm -f "$tmp"; return 1; }
    else
      rm -f -- "$SBD_BIN_DIR/libcronet.so" || return 1
    fi
  fi
  if [[ "$target_engine" == xray ]]; then
    for asset in geoip.dat geosite.dat; do
      [[ -s "$candidate_root/bin/$asset" ]] || { log_error "Xray release missing $asset"; return 1; }
      tmp="$(mktemp "$SBD_BIN_DIR/$asset.candidate.XXXXXX")" || return 1
      cp -p "$candidate_root/bin/$asset" "$tmp" || { rm -f "$tmp"; return 1; }
      mv -f "$tmp" "$SBD_BIN_DIR/$asset" || { rm -f "$tmp"; return 1; }
    done
  fi
  tmp="$(mktemp "${live}.candidate.XXXXXX")" || return 1
  cp -p "$candidate" "$tmp" || { rm -f "$tmp"; return 1; }
  chmod 0755 "$tmp" || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$live" || { rm -f "$tmp"; return 1; }
  if [[ -s "${candidate_root}/data/engine-version" ]]; then
    tmp="$(mktemp "${SBD_DATA_DIR}/engine-version.candidate.XXXXXX")" || return 1
    cp -p "${candidate_root}/data/engine-version" "$tmp" || { rm -f "$tmp"; return 1; }
    sbd_commit_file_with_backups "${SBD_DATA_DIR}/engine-version" "$tmp" 0644 || { rm -f "$tmp"; return 1; }
  fi
}

provider_core_candidate_commit() {
  local target_engine="$1" candidate_root="$2" name live candidate tmp
  case "$target_engine" in
    sing-box) name="config.json" ;;
    xray) name="xray-config.json" ;;
    *) return 1 ;;
  esac
  candidate="${candidate_root}/config/${name}"
  live="${SBD_CONFIG_DIR}/${name}"
  [[ -s "$candidate" ]] || return 1
  tmp="$(mktemp "${live}.candidate.XXXXXX")" || return 1
  jq --arg staged "$candidate_root/data/" --arg live "$SBD_DATA_DIR/"     'walk(if type == "string" and startswith($staged) then $live + .[($staged|length):] else . end)'     "$candidate" > "$tmp" || { rm -f "$tmp"; return 1; }
  sbd_commit_file_with_backups "$live" "$tmp" 600
}

sbd_service_main_pid() {
  local svc_name="$1" pid_file pid=""
  detect_init_system >&2
  case "$SBD_INIT_SYSTEM" in
    systemd) pid="$(sbd_service_op systemctl show -p MainPID --value "${svc_name}.service" 2>/dev/null || true)" ;;
    openrc)
      pid_file="/run/${svc_name}.pid"
      if [[ -r "$pid_file" ]]; then read -r pid < "$pid_file" || true; fi
      ;;
    nohup)
      pid_file="${SBD_RUNTIME_DIR}/${svc_name}.pid"
      if [[ -r "$pid_file" ]]; then read -r pid < "$pid_file" || true; fi
      ;;
  esac
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] && printf '%s\n' "$pid"
}

provider_core_health_check() {
  local target_engine="$1" old_pid="${2:-}" new_pid binary_path process_exe
  sbd_service_wait_active "sing-box-deve" 15 || return 1
  new_pid="$(sbd_service_main_pid "sing-box-deve")"
  [[ -n "$new_pid" ]] || { log_error "Unable to resolve core service PID"; return 1; }
  if [[ -n "$old_pid" && "$new_pid" == "$old_pid" ]]; then
    log_error "Core service PID did not change after restart: ${new_pid}"
    return 1
  fi
  binary_path="$(readlink -f "${SBD_BIN_DIR}/${target_engine}" 2>/dev/null || true)"
  if [[ -e "/proc/${new_pid}/exe" ]]; then
    process_exe="$(readlink -f "/proc/${new_pid}/exe" 2>/dev/null || true)"
    [[ "$process_exe" == "$binary_path" ]] || {
      log_error "Running core does not match installed binary: ${process_exe:-unknown}"
      return 1
    }
  fi
  return 0
}

provider_update() {
  sbd_with_mutation_lock sbd_transaction_run core-update provider_update_unlocked "$@"
}

provider_update_unlocked() {
  ensure_root
  provider_cfg_load_runtime_exports || return 1
  validate_feature_modes || return 1
  local target_engine="${engine:-sing-box}" runtime_protocols="${protocols:-vless-reality}"
  local candidate_root="$SBD_ACTIVE_TRANSACTION/candidate" old_pid
  old_pid="$(sbd_service_main_pid sing-box-deve)" || return 1
  provider_core_candidate_install "$target_engine" "$candidate_root" latest || return 1
  provider_core_candidate_build "$target_engine" "$runtime_protocols" "$candidate_root" || return 1
  sbd_transaction_phase "$SBD_ACTIVE_TRANSACTION" committing || return 1
  provider_core_candidate_binary_commit "$target_engine" "$candidate_root" || return 1
  provider_core_candidate_data_commit "$candidate_root" || return 1
  provider_core_candidate_commit "$target_engine" "$candidate_root" || return 1
  safe_service_restart || return 1
  provider_core_health_check "$target_engine" "$old_pid" || return 1
  if [[ "${ARGO_MODE:-off}" != off ]]; then provider_restart argo || return 1; fi
  write_nodes_output "$target_engine" "$runtime_protocols" || return 1
  log_success "Engine and config updated transactionally"
}
