#!/usr/bin/env bash

SBD_JUMP_FILE="${SBD_STATE_DIR}/jump-ports.env"
SBD_JUMP_DB_FILE="${SBD_STATE_DIR}/jump-ports.db"

jump_store_init() {
  mkdir -p "${SBD_STATE_DIR}"
  touch "$SBD_JUMP_DB_FILE"
}

jump_store_migrate_legacy() {
  jump_store_init
  [[ -f "$SBD_JUMP_FILE" ]] || return 0
  [[ -s "$SBD_JUMP_DB_FILE" ]] && return 0
  sbd_safe_load_env_file "$SBD_JUMP_FILE"
  [[ -n "${JUMP_PROTOCOL:-}" && -n "${JUMP_MAIN_PORT:-}" ]] || return 0
  printf '%s|%s|%s\n' "${JUMP_PROTOCOL}" "${JUMP_MAIN_PORT}" "${JUMP_EXTRA_PORTS:-}" > "$SBD_JUMP_DB_FILE"
}

jump_store_records() {
  if [[ -s "$SBD_JUMP_DB_FILE" ]]; then
    awk -F'|' 'NF>=2 && $1!="" && $2!="" {print $1 "|" $2 "|" $3}' "$SBD_JUMP_DB_FILE"
    return 0
  fi
  if [[ -f "$SBD_JUMP_FILE" ]]; then
    local protocol main extras
    protocol="$(awk -F= '/^JUMP_PROTOCOL=/{print $2; exit}' "$SBD_JUMP_FILE" 2>/dev/null || true)"
    main="$(awk -F= '/^JUMP_MAIN_PORT=/{print $2; exit}' "$SBD_JUMP_FILE" 2>/dev/null || true)"
    extras="$(awk -F= '/^JUMP_EXTRA_PORTS=/{print $2; exit}' "$SBD_JUMP_FILE" 2>/dev/null || true)"
    [[ -n "$protocol" && -n "$main" ]] && printf '%s|%s|%s\n' "$protocol" "$main" "$extras"
  fi
}

jump_store_load_first() {
  local first protocol main extras
  first="$(jump_store_records | head -n1)"
  [[ -n "$first" ]] || return 1
  protocol="${first%%|*}"
  main="${first#*|}"
  main="${main%%|*}"
  extras="${first##*|}"
  JUMP_PROTOCOL="$protocol"
  JUMP_MAIN_PORT="$main"
  JUMP_EXTRA_PORTS="$extras"
  return 0
}

jump_store_set() {
  local protocol="$1" main_port="$2" extras_csv="$3"
  local tmp
  jump_store_init
  jump_store_migrate_legacy
  tmp="$(mktemp)"
  jump_store_records | awk -F'|' -v p="$protocol" -v m="$main_port" '!( $1==p && $2==m ) {print $0}' > "$tmp"
  printf '%s|%s|%s\n' "$protocol" "$main_port" "$extras_csv" >> "$tmp"
  mv "$tmp" "$SBD_JUMP_DB_FILE"
}

jump_store_remove() {
  local protocol="$1" main_port="$2"
  local tmp
  jump_store_init
  jump_store_migrate_legacy
  tmp="$(mktemp)"
  jump_store_records | awk -F'|' -v p="$protocol" -v m="$main_port" '!( $1==p && $2==m ) {print $0}' > "$tmp"
  mv "$tmp" "$SBD_JUMP_DB_FILE"
}

jump_store_clear() {
  jump_store_init
  : > "$SBD_JUMP_DB_FILE"
}

jump_store_has() {
  local protocol="$1" main_port="$2"
  jump_store_records | awk -F'|' -v p="$protocol" -v m="$main_port" '$1==p && $2==m {found=1} END{exit(found?0:1)}'
}
