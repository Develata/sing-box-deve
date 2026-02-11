#!/usr/bin/env bash

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

append_jump_variants() {
  local base_file="$1" out_file="$2"
  load_jump_ports || return 0
  [[ -n "${JUMP_PROTOCOL:-}" && -n "${JUMP_MAIN_PORT:-}" && -n "${JUMP_EXTRA_PORTS:-}" ]] || return 0

  local marker
  case "$JUMP_PROTOCOL" in
    vless-reality) marker="#sbd-vless-reality" ;;
    vmess-ws) marker="sbd-vmess-ws" ;;
    vless-ws) marker="#sbd-vless-ws" ;;
    vless-xhttp) marker="#sbd-vless-xhttp" ;;
    shadowsocks-2022) marker="#sbd-shadowsocks-2022" ;;
    hysteria2) marker="#sbd-hysteria2" ;;
    tuic) marker="#sbd-tuic" ;;
    trojan) marker="#sbd-trojan" ;;
    anytls) marker="#sbd-anytls" ;;
    any-reality) marker="#sbd-any-reality" ;;
    socks5) marker="#sbd-socks5" ;;
    wireguard) marker="#sbd-wireguard-server" ;;
    *) return 0 ;;
  esac

  local line p rewritten host
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    [[ "$line" == *"$marker"* ]] || continue
    host="$(extract_link_host "$line")"
    [[ -n "$host" ]] || continue
    IFS=',' read -r -a _extras <<< "$JUMP_EXTRA_PORTS"
    for p in "${_extras[@]}"; do
      p="$(echo "$p" | xargs)"
      [[ "$p" =~ ^[0-9]+$ ]] || continue
      (( p == JUMP_MAIN_PORT )) && continue
      rewritten="$(rewrite_link_with_endpoint "$line" "${host}:${p}" "jump" 2>/dev/null || true)"
      [[ -n "$rewritten" ]] && echo "$rewritten" >> "$out_file"
    done
  done < "$base_file"
}
