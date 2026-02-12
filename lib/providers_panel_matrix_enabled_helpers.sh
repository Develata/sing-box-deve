#!/usr/bin/env bash

protocol_matrix_cap_get() {
  local caps="$1" key="$2"
  echo "$caps" | tr ';' '\n' | awk -F= -v k="$key" '$1==k{print $2; exit}'
}

protocol_matrix_enabled_ports_csv() {
  local protocol="$1" base_port="$2" out="" p port
  if [[ "$base_port" =~ ^[0-9]+$ ]]; then
    out="$base_port"
  fi
  while IFS='|' read -r p port; do
    [[ "$p" == "$protocol" && "$port" =~ ^[0-9]+$ ]] || continue
    if [[ -z "$out" ]]; then
      out="$port"
    elif ! csv_has_token "$out" "$port"; then
      out="${out},${port}"
    fi
  done < <(multi_ports_store_records)
  [[ -n "$out" ]] || {
    echo ""
    return 0
  }
  echo "$out" | tr ',' '\n' | awk '/^[0-9]+$/{print $1}' | sort -n | paste -sd, -
}

protocol_matrix_enabled_jump_csv() {
  local protocol="$1" main_port="$2" p m extras
  while IFS='|' read -r p m extras; do
    [[ "$p" == "$protocol" && "$m" == "$main_port" ]] || continue
    echo "${extras:-}"
    return 0
  done < <(jump_store_records)
  echo ""
}

protocol_matrix_enabled_port_mode() {
  local port="$1" normalized="$2" item
  IFS=',' read -r -a _items <<< "$normalized"
  for item in "${_items[@]}"; do
    [[ "${item%%:*}" == "$port" ]] || continue
    echo "${item#*:}"
    return 0
  done
  echo ""
}

protocol_matrix_enabled_outbound_desc() {
  local port="$1" map="$2" default_mode="$3" default_proxy_port="$4" warp_active="$5"
  local mode desc
  mode="$(protocol_matrix_enabled_port_mode "$port" "$map")"
  if [[ -z "$mode" ]]; then
    mode="$default_mode"
  fi
  case "$mode" in
    direct) desc="direct" ;;
    proxy)
      if [[ "$default_proxy_port" =~ ^[0-9]+$ ]]; then
        desc="proxy:${default_proxy_port}"
      else
        desc="proxy"
      fi
      ;;
    warp) desc="warp(${warp_active})" ;;
    psiphon) desc="psiphon" ;;
    *) desc="$mode" ;;
  esac
  echo "$desc"
}

protocol_matrix_flag_on() {
  case "${1,,}" in
    1|true|yes|on|enabled) return 0 ;;
    *) return 1 ;;
  esac
}

protocol_matrix_psiphon_primary_mode() {
  local enabled="$1" mode="$2"
  protocol_matrix_flag_on "$enabled" || {
    echo "off"
    return 0
  }
  case "$mode" in
    off|"") echo "off" ;;
    global|proxy) echo "psiphon" ;;
    *) echo "off" ;;
  esac
}

protocol_matrix_default_outbound_mode() {
  local engine="$1" protocols_csv="$2" warp_mode="$3" upstream_mode="$4"
  local psiphon_enable="$5" psiphon_mode="$6"
  local protocol_list=() has_warp="false" psiphon_primary mode

  protocols_to_array "$protocols_csv" protocol_list
  if protocol_enabled "warp" "${protocol_list[@]}"; then
    if [[ "$engine" == "sing-box" ]]; then
      warp_mode_targets_singbox "$warp_mode" && has_warp="true"
    else
      warp_mode_targets_xray "$warp_mode" && has_warp="true"
    fi
  fi

  mode="direct"
  if [[ "$engine" == "sing-box" ]]; then
    if [[ "$upstream_mode" != "direct" ]]; then
      mode="proxy"
    elif [[ "$has_warp" == "true" ]]; then
      mode="warp"
    fi
  else
    [[ "$has_warp" == "true" ]] && mode="warp"
    [[ "$upstream_mode" != "direct" ]] && mode="proxy"
  fi

  psiphon_primary="$(protocol_matrix_psiphon_primary_mode "$psiphon_enable" "$psiphon_mode")"
  [[ "$psiphon_primary" == "psiphon" ]] && mode="psiphon"
  echo "$mode"
}
