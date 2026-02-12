#!/usr/bin/env bash

protocol_link_marker_by_protocol() {
  case "$1" in
    vless-reality) echo "#sbd-vless-reality" ;;
    vmess-ws) echo "sbd-vmess-ws" ;;
    vless-ws) echo "#sbd-vless-ws" ;;
    vless-xhttp) echo "#sbd-vless-xhttp" ;;
    shadowsocks-2022) echo "#sbd-shadowsocks-2022" ;;
    hysteria2) echo "#sbd-hysteria2" ;;
    tuic) echo "#sbd-tuic" ;;
    trojan) echo "#sbd-trojan" ;;
    anytls) echo "#sbd-anytls" ;;
    any-reality) echo "#sbd-any-reality" ;;
    socks5) echo "#sbd-socks5" ;;
    wireguard) echo "#sbd-wireguard-server" ;;
    *) echo "" ;;
  esac
}

append_share_variants() {
  local base_file="$1" out_file="$2"; shift 2
  local group entry line rewritten
  for group in "$@"; do
    [[ -n "$group" ]] || continue
    IFS=',' read -r -a _entries <<< "$group"
    for entry in "${_entries[@]}"; do
      entry="$(echo "$entry" | xargs)"
      [[ "$entry" == *:* ]] || continue
      while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        rewritten="$(rewrite_link_with_endpoint "$line" "$entry" "share" 2>/dev/null || true)"
        [[ -n "$rewritten" ]] && echo "$rewritten" >> "$out_file"
      done < "$base_file"
    done
  done
}

append_multi_real_port_variants() {
  local base_file="$1" out_file="$2" input_file
  local protocol port marker line rewritten host

  if [[ "$base_file" == "$out_file" ]]; then
    input_file="$(mktemp)"
    cp "$base_file" "$input_file"
  else
    input_file="$base_file"
  fi

  while IFS='|' read -r protocol port; do
    [[ -n "$protocol" && -n "$port" ]] || continue
    marker="$(protocol_link_marker_by_protocol "$protocol")"
    [[ -n "$marker" ]] || continue
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      [[ "$line" == *"$marker"* ]] || continue
      host="$(extract_link_host "$line")"
      [[ -n "$host" ]] || continue
      rewritten="$(rewrite_link_with_endpoint "$line" "${host}:${port}" "mport" 2>/dev/null || true)"
      [[ -n "$rewritten" ]] && echo "$rewritten" >> "$out_file"
    done < "$input_file"
  done < <(multi_ports_store_records)

  if [[ "$input_file" != "$base_file" ]]; then
    rm -f "$input_file"
  fi
}

append_jump_variants() {
  local base_file="$1" out_file="$2" input_file
  local protocol main_port extras_csv marker line host rewritten base_port p

  if [[ "$base_file" == "$out_file" ]]; then
    input_file="$(mktemp)"
    cp "$base_file" "$input_file"
  else
    input_file="$base_file"
  fi

  while IFS='|' read -r protocol main_port extras_csv; do
    [[ -n "$protocol" && -n "$main_port" && -n "$extras_csv" ]] || continue
    marker="$(protocol_link_marker_by_protocol "$protocol")"
    [[ -n "$marker" ]] || continue
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      [[ "$line" == *"$marker"* ]] || continue
      base_port="$(extract_link_port "$line")"
      [[ "$base_port" == "$main_port" ]] || continue
      host="$(extract_link_host "$line")"
      [[ -n "$host" ]] || continue
      IFS=',' read -r -a _extras <<< "$extras_csv"
      for p in "${_extras[@]}"; do
        p="$(echo "$p" | xargs)"
        [[ "$p" =~ ^[0-9]+$ ]] || continue
        (( p == main_port )) && continue
        rewritten="$(rewrite_link_with_endpoint "$line" "${host}:${p}" "jump" 2>/dev/null || true)"
        [[ -n "$rewritten" ]] && echo "$rewritten" >> "$out_file"
      done
    done < "$input_file"
  done < <(jump_store_records)

  if [[ "$input_file" != "$base_file" ]]; then
    rm -f "$input_file"
  fi
}
