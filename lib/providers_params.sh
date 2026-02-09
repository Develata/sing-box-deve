#!/usr/bin/env bash

param_get() {
  local upper="$1" lower="$2" def="${3:-}" val=""
  val="${!upper:-}"
  [[ -n "$val" ]] || val="${!lower:-}"
  [[ -n "$val" ]] || val="$def"
  printf '%s' "$val"
}

normalize_path() {
  local p="$1" def="$2"
  [[ -n "$p" ]] || p="$def"
  [[ "$p" == /* ]] || p="/$p"
  printf '%s' "$p"
}

uri_encode() {
  local input="$1"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -sRr @uri
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$input" <<'PY'
import sys
from urllib.parse import quote
print(quote(sys.argv[1], safe=''))
PY
    return 0
  fi

  local out="" i ch code
  LC_ALL=C
  for (( i=0; i<${#input}; i++ )); do
    ch="${input:i:1}"
    case "$ch" in
      [a-zA-Z0-9.~_-])
        out+="$ch"
        ;;
      *)
        code="$(printf '%s' "$ch" | od -An -tx1 | tr -d ' \n' | tr '[:lower:]' '[:upper:]')"
        out+="%${code}"
        ;;
    esac
  done
  printf '%s\n' "$out"
}

sbd_reality_server_name() {
  param_get "REALITY_SERVER_NAME" "reality_server_name" "apple.com"
}

sbd_reality_fingerprint() {
  param_get "REALITY_FINGERPRINT" "reality_fingerprint" "chrome"
}

sbd_reality_handshake_port() {
  param_get "REALITY_HANDSHAKE_PORT" "reality_handshake_port" "443"
}

sbd_tls_server_name() {
  param_get "TLS_SERVER_NAME" "tls_server_name" "www.bing.com"
}

sbd_vmess_ws_path() {
  normalize_path "$(param_get "VMESS_WS_PATH" "vmess_ws_path" "/vmess")" "/vmess"
}

sbd_vless_ws_path() {
  normalize_path "$(param_get "VLESS_WS_PATH" "vless_ws_path" "/vless")" "/vless"
}

sbd_vless_xhttp_path() {
  local uuid="$1"
  local fallback="/${uuid}-xh"
  normalize_path "$(param_get "VLESS_XHTTP_PATH" "vless_xhttp_path" "$fallback")" "$fallback"
}

sbd_vless_xhttp_mode() {
  param_get "VLESS_XHTTP_MODE" "vless_xhttp_mode" "auto"
}

sbd_cdn_host_vmess() {
  local host
  host="$(param_get "CDN_HOST_VMESS" "cdn_host_vmess" "")"
  [[ -n "$host" ]] || host="$(param_get "CDN_TEMPLATE_HOST" "cdn_template_host" "")"
  printf '%s' "$host"
}

sbd_cdn_host_vless_ws() {
  local host
  host="$(param_get "CDN_HOST_VLESS_WS" "cdn_host_vless_ws" "")"
  [[ -n "$host" ]] || host="$(param_get "CDN_TEMPLATE_HOST" "cdn_template_host" "")"
  printf '%s' "$host"
}

sbd_cdn_host_vless_xhttp() {
  local host
  host="$(param_get "CDN_HOST_VLESS_XHTTP" "cdn_host_vless_xhttp" "")"
  [[ -n "$host" ]] || host="$(param_get "CDN_TEMPLATE_HOST" "cdn_template_host" "")"
  printf '%s' "$host"
}

sbd_proxyip_vmess() {
  local fallback="$1"
  param_get "PROXYIP_VMESS" "proxyip_vmess" "$fallback"
}

sbd_proxyip_vless_ws() {
  local fallback="$1"
  param_get "PROXYIP_VLESS_WS" "proxyip_vless_ws" "$fallback"
}

sbd_proxyip_vless_xhttp() {
  local fallback="$1"
  param_get "PROXYIP_VLESS_XHTTP" "proxyip_vless_xhttp" "$fallback"
}

sbd_xray_vless_enc_enabled() {
  local mode
  mode="$(param_get "XRAY_VLESS_ENC" "xray_vless_enc" "false")"
  [[ "$mode" == "true" ]]
}

sbd_xhttp_use_reality() {
  if [[ "${SBD_XHTTP_REALITY_ENC:-}" == "true" ]]; then
    return 0
  fi
  local mode
  mode="$(param_get "XRAY_XHTTP_REALITY" "xray_xhttp_reality" "false")"
  [[ "$mode" == "true" ]]
}

ensure_xray_vless_enc_keys() {
  sbd_xray_vless_enc_enabled || return 0
  local dec_file="${SBD_DATA_DIR}/xray_vless_decryption.key"
  local enc_file="${SBD_DATA_DIR}/xray_vless_encryption.key"
  if [[ -s "$dec_file" && -s "$enc_file" ]]; then
    return 0
  fi
  [[ -x "${SBD_BIN_DIR}/xray" ]] || die "xray binary not found for XRAY_VLESS_ENC=true"

  local out dec enc
  out="$("${SBD_BIN_DIR}/xray" vlessenc 2>/dev/null || true)"
  [[ -n "$out" ]] || die "XRAY_VLESS_ENC=true but failed to run: xray vlessenc"

  dec="$(printf '%s\n' "$out" | jq -r '..|objects|.decryption? // empty' 2>/dev/null | head -n1 || true)"
  enc="$(printf '%s\n' "$out" | jq -r '..|objects|.encryption? // empty' 2>/dev/null | head -n1 || true)"
  if [[ -z "$dec" || -z "$enc" ]]; then
    dec="$(printf '%s\n' "$out" | sed -n 's/.*"decryption"[[:space:]]*:[[:space:]]*"\([^"]\+\)".*/\1/p' | head -n1)"
    enc="$(printf '%s\n' "$out" | sed -n 's/.*"encryption"[[:space:]]*:[[:space:]]*"\([^"]\+\)".*/\1/p' | head -n1)"
  fi
  [[ -n "$dec" && -n "$enc" ]] || die "Unable to parse xray vlessenc output"

  printf '%s\n' "$dec" > "$dec_file"
  printf '%s\n' "$enc" > "$enc_file"
}

sbd_xray_vless_decryption_key() {
  cat "${SBD_DATA_DIR}/xray_vless_decryption.key" 2>/dev/null || true
}

sbd_xray_vless_encryption_key() {
  cat "${SBD_DATA_DIR}/xray_vless_encryption.key" 2>/dev/null || true
}
