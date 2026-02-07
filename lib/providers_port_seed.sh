#!/usr/bin/env bash

sbd_port_env_key() {
  local protocol="$1"
  echo "SBD_PORT_$(echo "$protocol" | tr '[:lower:]-' '[:upper:]_')"
}

sbd_port_map_get() {
  local map_csv="$1" protocol="$2" item key val
  [[ -n "$map_csv" ]] || return 1
  IFS=',' read -r -a _map_items <<< "$map_csv"
  for item in "${_map_items[@]}"; do
    item="$(echo "$item" | xargs)"
    [[ "$item" == *:* ]] || continue
    key="${item%%:*}"
    val="${item#*:}"
    [[ "$key" == "$protocol" ]] || continue
    echo "$val"
    return 0
  done
  return 1
}

sbd_port_used_in_list() {
  local port="$1" used_csv="$2"
  [[ ",${used_csv}," == *",${port},"* ]]
}

sbd_port_is_in_use() {
  local proto="$1" port="$2"
  case "$proto" in
    tcp)
      command -v ss >/dev/null 2>&1 || return 1
      ss -H -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "(^|[^0-9])${port}$"
      ;;
    udp)
      command -v ss >/dev/null 2>&1 || return 1
      ss -H -lnu 2>/dev/null | awk '{print $5}' | grep -Eq "(^|[^0-9])${port}$"
      ;;
    *)
      return 1
      ;;
  esac
}

sbd_validate_port_candidate() {
  local proto="$1" port="$2" used_csv="${3:-}" protocol_name="${4:-unknown}"
  [[ "$port" =~ ^[0-9]+$ ]] || die "Invalid port for ${protocol_name}: ${port}"
  (( port >= 1 && port <= 65535 )) || die "Port out of range for ${protocol_name}: ${port}"
  if sbd_port_used_in_list "$port" "$used_csv"; then
    die "Port conflict in selected protocols: ${port}"
  fi
  if sbd_port_is_in_use "$proto" "$port"; then
    die "Port already in use (${proto}): ${port}"
  fi
  return 0
}

sbd_random_free_port() {
  local proto="$1" used_csv="${2:-}" attempt=0 port
  while (( attempt < 120 )); do
    port="$((RANDOM % 45535 + 20000))"
    if ! sbd_port_used_in_list "$port" "$used_csv" && ! sbd_port_is_in_use "$proto" "$port"; then
      echo "$port"
      return 0
    fi
    attempt=$((attempt + 1))
  done
  die "Failed to allocate free random port for protocol ${proto}"
}

prepare_initial_install_ports() {
  local protocols_csv="$1"
  [[ -f /etc/sing-box-deve/runtime.env ]] && return 0

  local mode="${PORT_MODE:-random}"
  local map_csv="${MANUAL_PORT_MAP:-}"
  [[ "$mode" == "random" || "$mode" == "manual" ]] || die "PORT_MODE must be random or manual"

  if [[ -n "${INSTALL_MAIN_PORT:-}" ]]; then
    if [[ -z "$map_csv" ]]; then
      map_csv="vless-reality:${INSTALL_MAIN_PORT}"
    else
      map_csv+=",vless-reality:${INSTALL_MAIN_PORT}"
    fi
    mode="manual"
  fi
  if [[ "${RANDOM_MAIN_PORT:-false}" == "true" ]]; then
    mode="random"
  fi

  local protocols=()
  protocols_to_array "$protocols_csv" protocols
  local used_ports="" p mapping proto chosen env_key
  for p in "${protocols[@]}"; do
    protocol_needs_local_listener "$p" || continue
    mapping="$(protocol_port_map "$p")"
    proto="${mapping%%:*}"
    if [[ "$mode" == "manual" ]]; then
      chosen="$(sbd_port_map_get "$map_csv" "$p" 2>/dev/null || true)"
      [[ -n "$chosen" ]] || die "PORT_MODE=manual requires port-map entry: ${p}:<port>"
      sbd_validate_port_candidate "$proto" "$chosen" "$used_ports" "$p"
    else
      chosen="$(sbd_random_free_port "$proto" "$used_ports")"
    fi

    env_key="$(sbd_port_env_key "$p")"
    printf -v "$env_key" '%s' "$chosen"
    export "${env_key}=${chosen}"
    used_ports="${used_ports:+${used_ports},}${chosen}"
    log_info "$(msg "端口分配: ${p}=${chosen}" "Port assigned: ${p}=${chosen}")"
  done
}

prepare_incremental_protocol_ports() {
  local engine="$1" current_csv="$2" target_csv="$3" mode="${4:-random}" map_csv="${5:-}"
  [[ "$mode" == "random" || "$mode" == "manual" ]] || die "Port mode must be random or manual"
  [[ "$mode" == "manual" && -n "$map_csv" ]] || [[ "$mode" == "random" ]] || die "Manual port mode requires port map: proto:port,..."

  local current=() target=()
  protocols_to_array "$current_csv" current
  protocols_to_array "$target_csv" target

  local used_ports="" p current_port mapping proto chosen env_key
  for p in "${current[@]}"; do
    protocol_needs_local_listener "$p" || continue
    current_port="$(resolve_protocol_port_for_engine "$engine" "$p" 2>/dev/null || true)"
    [[ "$current_port" =~ ^[0-9]+$ ]] || continue
    used_ports="${used_ports:+${used_ports},}${current_port}"
  done

  for p in "${target[@]}"; do
    protocol_enabled "$p" "${current[@]}" && continue
    protocol_needs_local_listener "$p" || continue
    mapping="$(protocol_port_map "$p")"
    proto="${mapping%%:*}"

    if [[ "$mode" == "manual" ]]; then
      chosen="$(sbd_port_map_get "$map_csv" "$p" 2>/dev/null || true)"
      [[ -n "$chosen" ]] || die "Manual mode requires port-map entry: ${p}:<port>"
      sbd_validate_port_candidate "$proto" "$chosen" "$used_ports" "$p"
    else
      chosen="$(sbd_random_free_port "$proto" "$used_ports")"
    fi

    env_key="$(sbd_port_env_key "$p")"
    printf -v "$env_key" '%s' "$chosen"
    export "${env_key}=${chosen}"
    used_ports="${used_ports:+${used_ports},}${chosen}"
    log_info "$(msg "新增协议端口分配: ${p}=${chosen}" "Port assigned for added protocol: ${p}=${chosen}")"
  done
}
