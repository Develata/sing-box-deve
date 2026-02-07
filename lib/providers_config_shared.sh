#!/usr/bin/env bash

generate_reality_keys() {
  local private_key_file="${SBD_DATA_DIR}/reality_private.key"
  local public_key_file="${SBD_DATA_DIR}/reality_public.key"
  local short_id_file="${SBD_DATA_DIR}/reality_short_id"

  if [[ -f "$private_key_file" && -f "$public_key_file" && -f "$short_id_file" ]]; then
    return 0
  fi

  local out
  out="$("${SBD_BIN_DIR}/sing-box" generate reality-keypair)"
  echo "$out" | awk -F': ' '/PrivateKey/{print $2}' > "$private_key_file"
  echo "$out" | awk -F': ' '/PublicKey/{print $2}' > "$public_key_file"
  openssl rand -hex 4 > "$short_id_file"
}
