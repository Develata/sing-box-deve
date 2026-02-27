#!/usr/bin/env bash

provider_multi_ports_list() {
  ensure_root
  local count=0 protocol port
  log_info "$(msg "多真实端口列表:" "Multi real-port records:")"
  while IFS='|' read -r protocol port; do
    [[ -n "$protocol" && -n "$port" ]] || continue
    printf '  - %s:%s\n' "$protocol" "$port"
    count=$((count + 1))
  done < <(multi_ports_store_records)
  (( count > 0 )) || log_info "$(msg "无" "none")"
}

provider_multi_ports_validate_target() {
  local protocol="$1" port="$2" require_enabled="${3:-true}"
  local runtime_protocols=()
  [[ "$port" =~ ^[0-9]+$ ]] || die "Port must be numeric"
  (( port >= 1 && port <= 65535 )) || die "Port must be between 1 and 65535"
  contains_protocol "$protocol" || die "Unsupported protocol: $protocol"
  protocol_needs_local_listener "$protocol" || die "Protocol does not support local listener: $protocol"
  protocol_inbound_tag "$protocol" >/dev/null 2>&1 || die "Protocol has no inbound tag: $protocol"
  if [[ "$require_enabled" == "true" ]]; then
    protocols_to_array "${protocols:-vless-reality}" runtime_protocols
    protocol_enabled "$protocol" "${runtime_protocols[@]}" || die "Protocol is not enabled in runtime: $protocol"
  fi
}

multi_ports_port_used_by_jump_extra() {
  local target_port="$1" protocol main_port extras p
  while IFS='|' read -r protocol main_port extras; do
    [[ -n "$protocol" && -n "$main_port" && -n "$extras" ]] || continue
    IFS=',' read -r -a _extras <<< "$extras"
    for p in "${_extras[@]}"; do
      p="${p//[[:space:]]/}"
      [[ "$p" == "$target_port" ]] && return 0
    done
  done < <(jump_store_records)
  return 1
}

provider_multi_ports_reject_conflict() {
  local protocol="$1" port="$2" transport cfg all_ports
  transport="$(protocol_port_map "$protocol")"
  transport="${transport%%:*}"
  if sbd_port_is_in_use "$transport" "$port"; then
    die "Port already in use (${transport}): ${port}"
  fi
  case "${engine:-sing-box}" in
    sing-box) cfg="${SBD_CONFIG_DIR}/config.json" ;;
    xray) cfg="${SBD_CONFIG_DIR}/xray-config.json" ;;
    *) cfg="" ;;
  esac
  if [[ -n "$cfg" && -f "$cfg" ]]; then
    all_ports="$(jq -r '.inbounds[] | (.listen_port // .port // empty)' "$cfg" 2>/dev/null | tr '\n' ',' || true)"
    [[ ",${all_ports}," != *",${port},"* ]] || die "Port already exists in current runtime inbounds: ${port}"
  fi
  if multi_ports_port_used_by_jump_extra "$port"; then
    die "Port is already used in jump extra ports: ${port}"
  fi
}

provider_multi_ports_add() {
  ensure_root
  local protocol="$1" port="$2" mapping proto
  local runtime_provider runtime_profile runtime_engine runtime_protocols
  provider_cfg_load_runtime_exports
  runtime_provider="${provider:-vps}"
  runtime_profile="${profile:-lite}"
  runtime_engine="${engine:-sing-box}"
  runtime_protocols="${protocols:-vless-reality}"
  provider_multi_ports_validate_target "$protocol" "$port"
  provider_multi_ports_reject_conflict "$protocol" "$port"
  multi_ports_store_has "$protocol" "$port" && {
    log_info "$(msg "多真实端口已存在，无需重复添加" "Multi real-port already exists, skipping")"
    return 0
  }
  multi_ports_store_add "$protocol" "$port"
  mapping="$(protocol_port_map "$protocol")"
  proto="${mapping%%:*}"
  fw_detect_backend
  load_install_context || create_install_context "$runtime_provider" "$runtime_profile" "$runtime_engine" "$runtime_protocols"
  provider="$runtime_provider"
  profile="$runtime_profile"
  engine="$runtime_engine"
  protocols="$runtime_protocols"
  if ! ( fw_apply_rule "$proto" "$port" ); then
    multi_ports_store_remove "$protocol" "$port"
    die "Failed to apply firewall rule for multi real-port: ${protocol}:${port}"
  fi
  if ! ( provider_cfg_rebuild_runtime ); then
    provider_multi_ports_remove_firewall "$protocol" "$port" || true
    multi_ports_store_remove "$protocol" "$port"
    die "Failed to rebuild runtime after adding multi real-port: ${protocol}:${port}"
  fi
  log_success "$(msg "已新增多真实端口: ${protocol}:${port}" "Added multi real-port: ${protocol}:${port}")"
}

provider_multi_ports_remove_firewall() {
  local protocol="$1" port="$2" mapping proto tag tmp_file backend p t created
  local runtime_provider runtime_profile runtime_engine runtime_protocols
  runtime_provider="${provider:-vps}"
  runtime_profile="${profile:-lite}"
  runtime_engine="${engine:-sing-box}"
  runtime_protocols="${protocols:-vless-reality}"
  mapping="$(protocol_port_map "$protocol")"
  proto="${mapping%%:*}"
  load_install_context || create_install_context "$runtime_provider" "$runtime_profile" "$runtime_engine" "$runtime_protocols"
  provider="$runtime_provider"
  profile="$runtime_profile"
  engine="$runtime_engine"
  protocols="$runtime_protocols"
  tag="$(fw_tag "core" "$proto" "$port")"
  [[ -f "$SBD_RULES_FILE" ]] || return 0
  tmp_file="$(mktemp)"
  while IFS='|' read -r backend p _port t created; do
    if [[ "$t" == "$tag" && "$_port" == "$port" ]]; then
      fw_remove_rule_by_record "$backend" "$p" "$_port" "$t"
      continue
    fi
    printf '%s|%s|%s|%s|%s\n' "$backend" "$p" "$_port" "$t" "$created" >> "$tmp_file"
  done < "$SBD_RULES_FILE"
  mv "$tmp_file" "$SBD_RULES_FILE"
}

provider_multi_ports_remove() {
  ensure_root
  local protocol="$1" port="$2"
  local runtime_provider runtime_profile runtime_engine runtime_protocols
  provider_cfg_load_runtime_exports
  runtime_provider="${provider:-vps}"
  runtime_profile="${profile:-lite}"
  runtime_engine="${engine:-sing-box}"
  runtime_protocols="${protocols:-vless-reality}"
  provider_multi_ports_validate_target "$protocol" "$port" "false"
  if ! multi_ports_store_has "$protocol" "$port"; then
    log_warn "$(msg "该多真实端口不存在" "Multi real-port does not exist")"
    return 0
  fi
  multi_ports_store_remove "$protocol" "$port"
  provider_jump_clear_target "$protocol" "$port"
  if [[ -n "$(jump_store_records)" ]]; then
    provider_jump_replay
  else
    clear_jump_rules
    disable_jump_replay_service
  fi
  provider_multi_ports_remove_firewall "$protocol" "$port"
  provider="$runtime_provider"
  profile="$runtime_profile"
  engine="$runtime_engine"
  protocols="$runtime_protocols"
  provider_cfg_rebuild_runtime
  log_success "$(msg "已移除多真实端口: ${protocol}:${port}" "Removed multi real-port: ${protocol}:${port}")"
}

provider_multi_ports_clear() {
  ensure_root
  local runtime_provider runtime_profile runtime_engine runtime_protocols
  provider_cfg_load_runtime_exports
  runtime_provider="${provider:-vps}"
  runtime_profile="${profile:-lite}"
  runtime_engine="${engine:-sing-box}"
  runtime_protocols="${protocols:-vless-reality}"
  while IFS='|' read -r protocol port; do
    [[ -n "$protocol" && -n "$port" ]] || continue
    provider_jump_clear_target "$protocol" "$port"
    provider_multi_ports_remove_firewall "$protocol" "$port"
  done < <(multi_ports_store_records)
  if [[ -n "$(jump_store_records)" ]]; then
    provider_jump_replay
  else
    clear_jump_rules
    disable_jump_replay_service
  fi
  multi_ports_store_clear
  provider="$runtime_provider"
  profile="$runtime_profile"
  engine="$runtime_engine"
  protocols="$runtime_protocols"
  provider_cfg_rebuild_runtime
  log_success "$(msg "多真实端口已清空" "Multi real-ports cleared")"
}

provider_multi_ports_command() {
  case "${1:-list}" in
    list|show) provider_multi_ports_list ;;
    add)
      [[ -n "${2:-}" && -n "${3:-}" ]] || die "Usage: mport add <protocol> <port>"
      provider_multi_ports_add "${2:-}" "${3:-}"
      ;;
    remove|del|rm)
      [[ -n "${2:-}" && -n "${3:-}" ]] || die "Usage: mport remove <protocol> <port>"
      provider_multi_ports_remove "${2:-}" "${3:-}"
      ;;
    clear) provider_multi_ports_clear ;;
    *)
      die "Usage: mport [list|add <protocol> <port>|remove <protocol> <port>|clear]"
      ;;
  esac
}
