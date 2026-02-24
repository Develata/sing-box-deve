#!/usr/bin/env bash

provider_cfg_protocol_csv_merge() {
  local current_csv="$1" extra_csv="$2"
  local current=() extra=() merged=() p
  protocols_to_array "$current_csv" current
  protocols_to_array "$extra_csv" extra
  for p in "${current[@]}"; do merged+=("$p"); done
  for p in "${extra[@]}"; do
    protocol_enabled "$p" "${merged[@]}" || merged+=("$p")
  done
  (IFS=','; echo "${merged[*]}")
}

provider_cfg_protocol_csv_remove() {
  local current_csv="$1" drop_csv="$2"
  local current=() drop=() kept=() p
  protocols_to_array "$current_csv" current
  protocols_to_array "$drop_csv" drop
  for p in "${current[@]}"; do
    protocol_enabled "$p" "${drop[@]}" || kept+=("$p")
  done
  (IFS=','; echo "${kept[*]}")
}

provider_cfg_protocol_csv_added() {
  local old_csv="$1" new_csv="$2"
  local old=() new=() added=() p
  protocols_to_array "$old_csv" old
  protocols_to_array "$new_csv" new
  for p in "${new[@]}"; do
    protocol_enabled "$p" "${old[@]}" || added+=("$p")
  done
  (IFS=','; echo "${added[*]}")
}

provider_cfg_protocol_enabled_row_protocols() {
  local current_csv="$1" runtime_engine="${2:-${engine:-sing-box}}"
  local protocol_list=() protocol base_port ports_csv p
  protocols_to_array "$current_csv" protocol_list

  for protocol in "${protocol_list[@]}"; do
    if ! protocol_needs_local_listener "$protocol"; then
      printf '%s\n' "$protocol"
      continue
    fi

    base_port="$(resolve_protocol_port_for_engine "$runtime_engine" "$protocol" 2>/dev/null || true)"
    ports_csv="$(protocol_matrix_enabled_ports_csv "$protocol" "$base_port")"
    if [[ -z "$ports_csv" ]]; then
      printf '%s\n' "$protocol"
      continue
    fi

    IFS=',' read -r -a _ports <<< "$ports_csv"
    for p in "${_ports[@]}"; do
      [[ -n "$p" ]] || continue
      printf '%s\n' "$protocol"
    done
  done
}

provider_cfg_protocol_index_to_name() {
  local current_csv="$1" idx="$2" runtime_engine="${3:-${engine:-sing-box}}"
  local row_protocols=()
  [[ "$idx" =~ ^[0-9]+$ ]] || die "Protocol index must be numeric: ${idx}"

  mapfile -t row_protocols < <(provider_cfg_protocol_enabled_row_protocols "$current_csv" "$runtime_engine")
  (( ${#row_protocols[@]} > 0 )) || die "No enabled protocols available"
  (( idx >= 1 && idx <= ${#row_protocols[@]} )) || die "Protocol index out of range: ${idx} (1..${#row_protocols[@]})"
  printf '%s\n' "${row_protocols[$((idx - 1))]}"
}

provider_cfg_protocol_resolve_drop_csv() {
  local current_csv="$1" raw="$2" runtime_engine="${3:-${engine:-sing-box}}"
  local out="" item proto
  [[ -n "$raw" ]] || die "Usage: cfg protocol-remove <proto_csv|index_csv>"

  IFS=',' read -r -a _items <<< "$raw"
  for item in "${_items[@]}"; do
    item="$(echo "$item" | xargs)"
    [[ -n "$item" ]] || continue
    if [[ "$item" =~ ^[0-9]+$ ]]; then
      proto="$(provider_cfg_protocol_index_to_name "$current_csv" "$item" "$runtime_engine")"
    else
      proto="$item"
    fi
    if [[ -z "$out" ]]; then
      out="$proto"
    elif ! csv_has_token "$out" "$proto"; then
      out="${out},${proto}"
    fi
  done
  [[ -n "$out" ]] || die "Usage: cfg protocol-remove <proto_csv|index_csv>"
  printf '%s\n' "$out"
}

provider_cfg_protocol_sync_argo_service() {
  local protocols_csv="$1"
  local plist=()
  protocols_to_array "$protocols_csv" plist

  if ! protocol_enabled "argo" "${plist[@]}" || [[ "${ARGO_MODE:-off}" == "off" ]]; then
    systemctl disable --now sing-box-deve-argo.service >/dev/null 2>&1 || true
    rm -f "$SBD_ARGO_SERVICE_FILE" "${SBD_DATA_DIR}/argo_domain" "${SBD_DATA_DIR}/argo_mode"
    systemctl daemon-reload
    return 0
  fi

  if ! protocol_enabled "vmess-ws" "${plist[@]}" && ! protocol_enabled "vless-ws" "${plist[@]}"; then
    die "Argo protocol requires vmess-ws or vless-ws when ARGO_MODE is enabled"
  fi

  configure_argo_tunnel "$protocols_csv" "${engine:-sing-box}"
}

provider_cfg_protocol_open_firewall_for_added() {
  local added_csv="$1"
  [[ -n "$added_csv" ]] || return 0
  mkdir -p "$SBD_STATE_DIR"
  touch "$SBD_RULES_FILE"
  if ! load_install_context; then
    create_install_context "${provider:-vps}" "${profile:-lite}" "${engine:-sing-box}" "${protocols:-vless-reality}"
  fi
  fw_detect_backend

  local added=() p mapping proto port
  protocols_to_array "$added_csv" added
  for p in "${added[@]}"; do
    protocol_needs_local_listener "$p" || continue
    mapping="$(protocol_port_map "$p")"
    proto="${mapping%%:*}"
    port="$(get_protocol_port "$p")"
    fw_apply_rule "$proto" "$port"
  done
}

provider_cfg_protocol_add() {
  ensure_root
  local add_csv="$1" port_mode="${2:-random}" port_map="${3:-}"
  [[ -n "$add_csv" ]] || die "Usage: cfg protocol-add <proto_csv> [random|manual] [proto:port,...]"
  validate_protocols_csv "$add_csv"

  provider_cfg_load_runtime_exports
  local current_csv="${protocols:-vless-reality}" target_csv added_csv
  target_csv="$(provider_cfg_protocol_csv_merge "$current_csv" "$add_csv")"
  [[ "$target_csv" != "$current_csv" ]] || {
    log_info "$(msg "没有可新增的协议" "No new protocols to add")"
    return 0
  }

  validate_profile_protocols "${profile:-lite}" "$target_csv"
  assert_engine_protocol_compatibility "${engine:-sing-box}" "$target_csv"
  added_csv="$(provider_cfg_protocol_csv_added "$current_csv" "$target_csv")"
  prepare_incremental_protocol_ports "${engine:-sing-box}" "$current_csv" "$target_csv" "$port_mode" "$port_map"
  provider_cfg_protocol_open_firewall_for_added "$added_csv"

  protocols="$target_csv"
  provider_cfg_protocol_sync_argo_service "$target_csv"
  provider_cfg_rebuild_runtime "$target_csv"
  log_success "$(msg "已新增协议: ${added_csv}" "Protocols added: ${added_csv}")"
}

provider_cfg_protocol_remove() {
  ensure_root
  local drop_raw="$1"
  [[ -n "$drop_raw" ]] || die "Usage: cfg protocol-remove <proto_csv|index_csv>"

  provider_cfg_load_runtime_exports
  local drop_csv
  drop_csv="$(provider_cfg_protocol_resolve_drop_csv "${protocols:-vless-reality}" "$drop_raw" "${engine:-sing-box}")"
  validate_protocols_csv "$drop_csv"
  local current_csv="${protocols:-vless-reality}" target_csv
  target_csv="$(provider_cfg_protocol_csv_remove "$current_csv" "$drop_csv")"
  [[ "$target_csv" != "$current_csv" ]] || {
    log_info "$(msg "没有协议被移除" "No protocols removed")"
    return 0
  }
  [[ -n "$target_csv" ]] || die "At least one protocol must remain enabled"

  validate_profile_protocols "${profile:-lite}" "$target_csv"
  assert_engine_protocol_compatibility "${engine:-sing-box}" "$target_csv"
  protocols="$target_csv"
  provider_cfg_protocol_sync_argo_service "$target_csv"
  provider_cfg_rebuild_runtime "$target_csv"
  log_success "$(msg "已移除协议: ${drop_csv}" "Protocols removed: ${drop_csv}")"
}
