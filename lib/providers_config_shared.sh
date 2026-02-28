#!/usr/bin/env bash

sbd_is_valid_reality_key() {
  local key="${1:-}"
  # sing-box reality keys are base64-like single-line tokens.
  [[ -n "$key" ]] && [[ "$key" =~ ^[A-Za-z0-9+/_=-]{20,128}$ ]]
}

sbd_is_valid_reality_short_id() {
  local sid="${1:-}"
  [[ -n "$sid" ]] && [[ "$sid" =~ ^[0-9a-fA-F]{2,32}$ ]]
}

sbd_parse_reality_keypair_output() {
  local out="$1" want="$2" value=""
  case "$want" in
    private)
      value="$(printf '%s\n' "$out" | sed -nE 's/^[[:space:]]*Private[[:space:]]*Key[[:space:]]*:[[:space:]]*([^[:space:]]+).*/\1/p' | head -n1)"
      ;;
    public)
      value="$(printf '%s\n' "$out" | sed -nE 's/^[[:space:]]*Public[[:space:]]*Key[[:space:]]*:[[:space:]]*([^[:space:]]+).*/\1/p' | head -n1)"
      ;;
  esac
  printf '%s' "$value"
}

generate_reality_keys() {
  local private_key_file="${SBD_DATA_DIR}/reality_private.key"
  local public_key_file="${SBD_DATA_DIR}/reality_public.key"
  local short_id_file="${SBD_DATA_DIR}/reality_short_id"
  local private_key public_key short_id out

  if [[ -f "$private_key_file" && -f "$public_key_file" && -f "$short_id_file" ]]; then
    private_key="$(tr -d '\r\n' < "$private_key_file" 2>/dev/null || true)"
    public_key="$(tr -d '\r\n' < "$public_key_file" 2>/dev/null || true)"
    short_id="$(tr -d '\r\n' < "$short_id_file" 2>/dev/null || true)"
    if sbd_is_valid_reality_key "$private_key" && sbd_is_valid_reality_key "$public_key" && sbd_is_valid_reality_short_id "$short_id"; then
      # Ensure existing files have correct permissions
      chmod 600 "$private_key_file" "$short_id_file" 2>/dev/null || true
      chmod 644 "$public_key_file" 2>/dev/null || true
      return 0
    fi
    log_warn "$(msg "检测到损坏的 Reality 密钥，正在自动重建" "Detected invalid Reality keys; regenerating")"
    rm -f "$private_key_file" "$public_key_file" "$short_id_file"
  fi

  out="$("${SBD_BIN_DIR}/sing-box" generate reality-keypair 2>/dev/null || true)"
  private_key="$(sbd_parse_reality_keypair_output "$out" private)"
  public_key="$(sbd_parse_reality_keypair_output "$out" public)"
  sbd_is_valid_reality_key "$private_key" || die "Failed to generate valid reality private key"
  sbd_is_valid_reality_key "$public_key" || die "Failed to generate valid reality public key"
  printf '%s\n' "$private_key" > "$private_key_file"
  printf '%s\n' "$public_key" > "$public_key_file"
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 4 > "$short_id_file"
  else
    rand_hex_8 > "$short_id_file"
  fi
  short_id="$(tr -d '\r\n' < "$short_id_file" 2>/dev/null || true)"
  sbd_is_valid_reality_short_id "$short_id" || die "Failed to generate valid reality short id"

  # Set restrictive permissions on sensitive key files
  # Private key and short_id should only be readable by root
  chmod 600 "$private_key_file" "$short_id_file"
  # Public key can be world-readable
  chmod 644 "$public_key_file"
}
