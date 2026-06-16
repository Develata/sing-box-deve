#!/usr/bin/env bash

protocol_link_marker_by_protocol() {
  case "$1" in
    vless-reality) echo "#sbd-vless-reality" ;;
    vless-ws) echo "#sbd-vless-ws" ;;
    vless-xhttp) echo "#sbd-vless-xhttp" ;;
    shadowsocks-2022) echo "#sbd-shadowsocks-2022" ;;
    naive) echo "#sbd-naive" ;;
    hysteria2) echo "#sbd-hysteria2" ;;
    tuic) echo "#sbd-tuic" ;;
    *) echo "" ;;
  esac
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
