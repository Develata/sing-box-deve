#!/usr/bin/env bash

generate_reality_keys() {
  local private_key_file="${SBD_DATA_DIR}/reality_private.key"
  local public_key_file="${SBD_DATA_DIR}/reality_public.key"
  local short_id_file="${SBD_DATA_DIR}/reality_short_id"

  if [[ -f "$private_key_file" && -f "$public_key_file" && -f "$short_id_file" ]]; then
    # Ensure existing files have correct permissions
    chmod 600 "$private_key_file" "$short_id_file" 2>/dev/null || true
    chmod 644 "$public_key_file" 2>/dev/null || true
    return 0
  fi

  local out
  out="$("${SBD_BIN_DIR}/sing-box" generate reality-keypair)"
  echo "$out" | awk -F': ' '/PrivateKey/{print $2}' > "$private_key_file"
  echo "$out" | awk -F': ' '/PublicKey/{print $2}' > "$public_key_file"
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 4 > "$short_id_file"
  else
    rand_hex_8 > "$short_id_file"
  fi

  # Set restrictive permissions on sensitive key files
  # Private key and short_id should only be readable by root
  chmod 600 "$private_key_file" "$short_id_file"
  # Public key can be world-readable
  chmod 644 "$public_key_file"
}
