#!/usr/bin/env bash

normalize_port_egress_map() {
  local raw="${1:-}" item pair port mode out=""
  [[ -n "${raw//[[:space:],]/}" ]] || {
    echo ""
    return 0
  }
  local -A mode_by_port=()
  local -a order=()
  IFS=',' read -r -a _items <<< "$raw"
  for item in "${_items[@]}"; do
    pair="${item//[[:space:]]/}"
    [[ -n "$pair" ]] || continue
    [[ "$pair" == *:* ]] || die "Invalid PORT_EGRESS_MAP item: ${pair} (expected port:direct|proxy|warp|psiphon)"
    port="${pair%%:*}"
    mode="${pair#*:}"
    mode="${mode,,}"
    [[ "$port" =~ ^[0-9]+$ ]] || die "Invalid PORT_EGRESS_MAP port: ${port}"
    (( port >= 1 && port <= 65535 )) || die "PORT_EGRESS_MAP port out of range: ${port}"
    case "$mode" in
      direct|proxy|warp|psiphon) ;;
      *) die "Invalid PORT_EGRESS_MAP mode for ${port}: ${mode} (expected direct|proxy|warp|psiphon)" ;;
    esac
    if [[ -z "${mode_by_port[$port]+x}" ]]; then
      order+=("$port")
    fi
    mode_by_port["$port"]="$mode"
  done
  for port in "${order[@]}"; do
    out+="${out:+,}${port}:${mode_by_port[$port]}"
  done
  echo "$out"
}

port_egress_mode_to_outbound() {
  case "$1" in
    direct) echo "direct" ;;
    proxy) echo "proxy-out" ;;
    warp) echo "warp-out" ;;
    psiphon) echo "psiphon-out" ;;
    *) return 1 ;;
  esac
}

csv_has_token() {
  local csv="$1" token="$2"
  [[ ",${csv}," == *",${token},"* ]]
}

build_port_egress_rules_singbox() {
  local map="$1" inbound_map="$2" available_outbounds="$3"
  local normalized rules="" item pair port mode target tag inbound_port found
  normalized="$(normalize_port_egress_map "$map")"
  [[ -n "$normalized" ]] || return 0
  IFS=',' read -r -a _items <<< "$normalized"
  IFS=',' read -r -a _pairs <<< "$inbound_map"
  for item in "${_items[@]}"; do
    port="${item%%:*}"
    mode="${item#*:}"
    target="$(port_egress_mode_to_outbound "$mode")" || continue
    if ! csv_has_token "$available_outbounds" "$target"; then
      log_warn "$(msg "端口出站映射跳过: ${port}:${mode}（出站 ${target} 不可用）" "Skip port egress mapping ${port}:${mode} (outbound ${target} unavailable)")" >&2
      continue
    fi
    found="false"
    for pair in "${_pairs[@]}"; do
      tag="${pair%%:*}"
      inbound_port="${pair##*:}"
      [[ "$inbound_port" == "$port" ]] || continue
      rules+="${rules:+,}{\"inbound\":[\"${tag}\"],\"outbound\":\"${target}\"}"
      found="true"
    done
    [[ "$found" == "true" ]] || log_warn "$(msg "端口出站映射未命中入站端口: ${port}" "Port egress mapping did not match inbound port: ${port}")" >&2
  done
  echo "$rules"
}

build_port_egress_rules_xray() {
  local map="$1" inbound_map="$2" available_outbounds="$3"
  local normalized rules="" item pair port mode target tag inbound_port found
  normalized="$(normalize_port_egress_map "$map")"
  [[ -n "$normalized" ]] || return 0
  IFS=',' read -r -a _items <<< "$normalized"
  IFS=',' read -r -a _pairs <<< "$inbound_map"
  for item in "${_items[@]}"; do
    port="${item%%:*}"
    mode="${item#*:}"
    target="$(port_egress_mode_to_outbound "$mode")" || continue
    if ! csv_has_token "$available_outbounds" "$target"; then
      log_warn "$(msg "端口出站映射跳过: ${port}:${mode}（出站 ${target} 不可用）" "Skip port egress mapping ${port}:${mode} (outbound ${target} unavailable)")" >&2
      continue
    fi
    found="false"
    for pair in "${_pairs[@]}"; do
      tag="${pair%%:*}"
      inbound_port="${pair##*:}"
      [[ "$inbound_port" == "$port" ]] || continue
      rules+="${rules:+,}{\"type\":\"field\",\"inboundTag\":[\"${tag}\"],\"outboundTag\":\"${target}\"}"
      found="true"
    done
    [[ "$found" == "true" ]] || log_warn "$(msg "端口出站映射未命中入站端口: ${port}" "Port egress mapping did not match inbound port: ${port}")" >&2
  done
  echo "$rules"
}
