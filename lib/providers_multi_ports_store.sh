#!/usr/bin/env bash

SBD_MULTI_PORTS_FILE="/var/lib/sing-box-deve/multi-ports.db"

multi_ports_store_init() {
  mkdir -p "/var/lib/sing-box-deve"
  touch "$SBD_MULTI_PORTS_FILE"
}

multi_ports_store_records() {
  [[ -f "$SBD_MULTI_PORTS_FILE" ]] || return 0
  awk -F'|' 'NF>=2 && $1!="" && $2!="" {print $1 "|" $2}' "$SBD_MULTI_PORTS_FILE"
}

multi_ports_store_ports_csv() {
  local protocol="$1"
  local out=""
  while IFS='|' read -r p port; do
    [[ "$p" == "$protocol" ]] || continue
    out+="${out:+,}${port}"
  done < <(multi_ports_store_records)
  printf '%s\n' "$out"
}

multi_ports_store_has() {
  local protocol="$1" port="$2"
  multi_ports_store_records | awk -F'|' -v p="$protocol" -v q="$port" '$1==p && $2==q {found=1} END{exit(found?0:1)}'
}

multi_ports_store_add() {
  local protocol="$1" port="$2"
  local tmp
  multi_ports_store_init
  multi_ports_store_has "$protocol" "$port" && return 0
  tmp="$(mktemp)"
  cat "$SBD_MULTI_PORTS_FILE" > "$tmp"
  printf '%s|%s\n' "$protocol" "$port" >> "$tmp"
  mv "$tmp" "$SBD_MULTI_PORTS_FILE"
}

multi_ports_store_remove() {
  local protocol="$1" port="$2"
  local tmp
  multi_ports_store_init
  tmp="$(mktemp)"
  awk -F'|' -v p="$protocol" -v q="$port" '!( $1==p && $2==q ) {print $0}' "$SBD_MULTI_PORTS_FILE" > "$tmp"
  mv "$tmp" "$SBD_MULTI_PORTS_FILE"
}

multi_ports_store_clear() {
  multi_ports_store_init
  : > "$SBD_MULTI_PORTS_FILE"
}
