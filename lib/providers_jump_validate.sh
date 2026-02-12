#!/usr/bin/env bash

jump_normalize_extra_ports() {
  local raw_csv="$1" main_port="$2"
  local out="" token p
  IFS=',' read -r -a _items <<< "$raw_csv"
  for token in "${_items[@]}"; do
    p="${token//[[:space:]]/}"
    [[ -n "$p" ]] || continue
    [[ "$p" =~ ^[0-9]+$ ]] || die "Invalid jump extra port: ${p}"
    (( p >= 1 && p <= 65535 )) || die "Jump extra port out of range: ${p}"
    (( p == main_port )) && continue
    if [[ -z "$out" ]]; then
      out="$p"
    elif ! csv_has_token "$out" "$p"; then
      out="${out},${p}"
    fi
  done
  [[ -n "$out" ]] || die "No valid jump extra ports after normalization"
  echo "$out"
}

jump_runtime_inbounds_ports_csv() {
  local cfg query
  case "${engine:-sing-box}" in
    sing-box)
      cfg="${SBD_CONFIG_DIR}/config.json"
      query='.inbounds[] | (.listen_port // .port // empty)'
      ;;
    xray)
      cfg="${SBD_CONFIG_DIR}/xray-config.json"
      query='.inbounds[] | (.port // empty)'
      ;;
    *)
      echo ""
      return 0
      ;;
  esac
  [[ -f "$cfg" ]] || {
    echo ""
    return 0
  }
  jq -r "$query" "$cfg" 2>/dev/null | awk '/^[0-9]+$/{print $1}' | tr '\n' ','
}

provider_jump_validate_target() {
  local protocol="$1" main_port="$2" extra_ports="$3"
  local runtime_protocols=() base_port="" extras_csv map proto p runtime_ports
  [[ -n "$protocol" && -n "$main_port" && -n "$extra_ports" ]] || die "Usage: jump set <protocol> <main_port> <extra_csv>"
  contains_protocol "$protocol" || die "Unsupported protocol: ${protocol}"
  protocol_needs_local_listener "$protocol" || die "Protocol does not support local listener: ${protocol}"
  protocol_inbound_tag "$protocol" >/dev/null 2>&1 || die "Protocol has no inbound tag: ${protocol}"
  [[ "$main_port" =~ ^[0-9]+$ ]] || die "$(msg "主端口必须为数字" "main port must be numeric")"
  (( main_port >= 1 && main_port <= 65535 )) || die "$(msg "主端口超出范围" "main port out of range")"
  extras_csv="$(jump_normalize_extra_ports "$extra_ports" "$main_port")"

  protocols_to_array "${protocols:-}" runtime_protocols
  protocol_enabled "$protocol" "${runtime_protocols[@]}" || die "Protocol is not enabled in runtime: ${protocol}"
  base_port="$(resolve_protocol_port_for_engine "${engine:-sing-box}" "$protocol" 2>/dev/null || true)"
  if [[ "$main_port" != "$base_port" ]] && ! multi_ports_store_has "$protocol" "$main_port"; then
    die "Main port is not active for protocol ${protocol}: ${main_port}"
  fi

  map="$(protocol_port_map "$protocol")"
  proto="${map%%:*}"
  runtime_ports="$(jump_runtime_inbounds_ports_csv)"
  IFS=',' read -r -a _extras <<< "$extras_csv"
  for p in "${_extras[@]}"; do
    [[ "$p" =~ ^[0-9]+$ ]] || continue
    if sbd_port_is_in_use "$proto" "$p"; then
      die "Jump extra port already in use (${proto}): ${p}"
    fi
    [[ ",${runtime_ports}," != *",${p},"* ]] || die "Jump extra port conflicts with active inbound: ${p}"
  done
  echo "$extras_csv"
}
