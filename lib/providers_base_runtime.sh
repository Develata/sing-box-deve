#!/usr/bin/env bash

validate_feature_modes() {
  case "${ARGO_MODE:-off}" in
    off|temp|fixed) ;;
    *) die "Invalid ARGO_MODE: ${ARGO_MODE}" ;;
  esac

  validate_warp_mode_extended

  case "${OUTBOUND_PROXY_MODE:-direct}" in
    direct|socks|http|https) ;;
    *) die "Invalid OUTBOUND_PROXY_MODE: ${OUTBOUND_PROXY_MODE}" ;;
  esac

  validate_route_mode

  case "${IP_PREFERENCE:-auto}" in
    auto|v4|v6) ;;
    *) die "Invalid IP_PREFERENCE: ${IP_PREFERENCE}" ;;
  esac

  case "${PSIPHON_ENABLE:-off}" in
    on|off|true|false|yes|no|1|0|enabled|disabled) ;;
    *) die "Invalid PSIPHON_ENABLE: ${PSIPHON_ENABLE}" ;;
  esac

  case "${PSIPHON_MODE:-off}" in
    off|proxy|global) ;;
    *) die "Invalid PSIPHON_MODE: ${PSIPHON_MODE}" ;;
  esac

  case "${PSIPHON_REGION:-auto}" in
    auto) ;;
    [a-z][a-z]|[A-Z][A-Z]) ;;
    *) die "Invalid PSIPHON_REGION: ${PSIPHON_REGION} (expected auto or 2-letter code)" ;;
  esac

  case "${TLS_MODE:-self-signed}" in
    self-signed|acme) ;;
    *) die "Invalid TLS_MODE: ${TLS_MODE}" ;;
  esac

  case "${XRAY_VLESS_ENC:-${xray_vless_enc:-false}}" in
    true|false) ;;
    *) die "Invalid XRAY_VLESS_ENC: ${XRAY_VLESS_ENC:-${xray_vless_enc:-}}" ;;
  esac

  case "${XRAY_XHTTP_REALITY:-${xray_xhttp_reality:-false}}" in
    true|false) ;;
    *) die "Invalid XRAY_XHTTP_REALITY: ${XRAY_XHTTP_REALITY:-${xray_xhttp_reality:-}}" ;;
  esac

  local reality_port
  reality_port="${REALITY_HANDSHAKE_PORT:-${reality_handshake_port:-443}}"
  [[ "$reality_port" =~ ^[0-9]+$ ]] || die "REALITY_HANDSHAKE_PORT must be numeric"
  (( reality_port >= 1 && reality_port <= 65535 )) || die "REALITY_HANDSHAKE_PORT must be between 1 and 65535"

  if [[ "${OUTBOUND_PROXY_MODE:-direct}" != "direct" ]]; then
    [[ -n "${OUTBOUND_PROXY_HOST:-}" ]] || die "OUTBOUND_PROXY_HOST is required when outbound proxy mode is not direct"
    [[ -n "${OUTBOUND_PROXY_PORT:-}" ]] || die "OUTBOUND_PROXY_PORT is required when outbound proxy mode is not direct"
    [[ "${OUTBOUND_PROXY_PORT}" =~ ^[0-9]+$ ]] || die "OUTBOUND_PROXY_PORT must be numeric"
    (( OUTBOUND_PROXY_PORT >= 1 && OUTBOUND_PROXY_PORT <= 65535 )) || die "OUTBOUND_PROXY_PORT must be between 1 and 65535"
  fi

  if [[ "${OUTBOUND_PROXY_MODE:-direct}" != "direct" && "${WARP_MODE:-off}" == "global" ]]; then
    die "WARP_MODE=global conflicts with OUTBOUND_PROXY_MODE!=direct; choose one outbound strategy"
  fi

  if [[ -n "${PORT_EGRESS_MAP:-}" ]] && declare -F normalize_port_egress_map >/dev/null 2>&1; then
    PORT_EGRESS_MAP="$(normalize_port_egress_map "${PORT_EGRESS_MAP}")"
  fi
}

get_tls_cert_path() {
  if [[ "${TLS_MODE:-self-signed}" == "acme" ]]; then
    [[ -n "${ACME_CERT_PATH:-}" && -f "${ACME_CERT_PATH}" ]] || die "ACME_CERT_PATH missing or not found"
    echo "${ACME_CERT_PATH}"
  else
    ensure_self_signed_cert
    echo "${SBD_DATA_DIR}/cert.pem"
  fi
}

get_tls_key_path() {
  if [[ "${TLS_MODE:-self-signed}" == "acme" ]]; then
    [[ -n "${ACME_KEY_PATH:-}" && -f "${ACME_KEY_PATH}" ]] || die "ACME_KEY_PATH missing or not found"
    echo "${ACME_KEY_PATH}"
  else
    ensure_self_signed_cert
    echo "${SBD_DATA_DIR}/private.key"
  fi
}

detect_public_ip() {
  local ip
  ip="$(curl -fsS4 --max-time 5 https://icanhazip.com 2>/dev/null || true)"
  ip="${ip//$'\n'/}"
  if [[ -z "$ip" ]]; then
    ip="$(curl -fsS6 --max-time 5 https://icanhazip.com 2>/dev/null || true)"
    ip="${ip//$'\n'/}"
  fi
  [[ -n "$ip" ]] || ip="YOUR_SERVER_IP"
  echo "$ip"
}

ensure_uuid() {
  local uuid_file="${SBD_DATA_DIR}/uuid"
  if [[ ! -f "$uuid_file" ]]; then
    if command -v uuidgen >/dev/null 2>&1; then
      uuidgen > "$uuid_file"
    elif [[ -r /proc/sys/kernel/random/uuid ]]; then
      cat /proc/sys/kernel/random/uuid > "$uuid_file"
    elif command -v openssl >/dev/null 2>&1; then
      openssl rand -hex 16 | sed -E 's/^(.{8})(.{4})(.{4})(.{4})(.{12}).*$/\1-\2-\3-\4-\5/' > "$uuid_file"
    else
      die "$(msg "缺少 uuid 生成依赖（uuidgen/openssl）" "Missing UUID generator dependency (uuidgen/openssl)")"
    fi
    secure_file "$uuid_file"
  fi
  cat "$uuid_file"
}

ensure_self_signed_cert() {
  local cert_file="${SBD_DATA_DIR}/cert.pem"
  local key_file="${SBD_DATA_DIR}/private.key"
  if [[ ! -f "$cert_file" || ! -f "$key_file" ]]; then
    if ! command -v openssl >/dev/null 2>&1; then
      log_warn "$(msg "缺少 openssl，跳过自签名证书生成" "openssl missing, skip self-signed certificate generation")"
      return 0
    fi
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
      -keyout "$key_file" -out "$cert_file" -subj "/CN=www.bing.com" >/dev/null 2>&1
    secure_file "$key_file"
    secure_file "$cert_file"
  fi
}

secure_file() {
  local file="$1"
  [[ -f "$file" ]] && chmod 600 "$file"
}

secure_directory() {
  local dir="$1"
  [[ -d "$dir" ]] && chmod 700 "$dir"
}
