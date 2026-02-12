#!/usr/bin/env bash

multi_ports_runtime_append_singbox() {
  local protocols_csv="$1"
  local cfg="${SBD_CONFIG_DIR}/config.json"
  local tmp protocol tag ports_csv port new_tag
  local enabled=()

  [[ -f "$cfg" ]] || return 0
  protocols_to_array "$protocols_csv" enabled

  for protocol in "${enabled[@]}"; do
    tag="$(protocol_inbound_tag "$protocol" || true)"
    [[ -n "$tag" ]] || continue
    ports_csv="$(multi_ports_store_ports_csv "$protocol")"
    [[ -n "$ports_csv" ]] || continue
    IFS=',' read -r -a _ports <<< "$ports_csv"
    for port in "${_ports[@]}"; do
      [[ "$port" =~ ^[0-9]+$ ]] || continue
      new_tag="${tag}-mp-${port}"
      tmp="$(mktemp)"
      if jq --arg src "$tag" --arg nt "$new_tag" --argjson p "$port" \
        '.inbounds += [(.inbounds[] | select(.tag==$src) | .tag=$nt | .listen_port=$p | del(.port))]' \
        "$cfg" > "$tmp"; then
        mv "$tmp" "$cfg"
      else
        rm -f "$tmp"
        die "Failed to append multi-port sing-box inbound: ${protocol}:${port}"
      fi
    done
  done
}

multi_ports_runtime_append_xray() {
  local protocols_csv="$1"
  local cfg="${SBD_CONFIG_DIR}/xray-config.json"
  local tmp protocol tag ports_csv port new_tag
  local enabled=()

  [[ -f "$cfg" ]] || return 0
  protocols_to_array "$protocols_csv" enabled

  for protocol in "${enabled[@]}"; do
    tag="$(protocol_inbound_tag "$protocol" || true)"
    [[ -n "$tag" ]] || continue
    ports_csv="$(multi_ports_store_ports_csv "$protocol")"
    [[ -n "$ports_csv" ]] || continue
    IFS=',' read -r -a _ports <<< "$ports_csv"
    for port in "${_ports[@]}"; do
      [[ "$port" =~ ^[0-9]+$ ]] || continue
      new_tag="${tag}-mp-${port}"
      tmp="$(mktemp)"
      if jq --arg src "$tag" --arg nt "$new_tag" --argjson p "$port" \
        '.inbounds += [(.inbounds[] | select(.tag==$src) | .tag=$nt | .port=$p)]' \
        "$cfg" > "$tmp"; then
        mv "$tmp" "$cfg"
      else
        rm -f "$tmp"
        die "Failed to append multi-port xray inbound: ${protocol}:${port}"
      fi
    done
  done
}
