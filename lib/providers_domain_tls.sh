#!/usr/bin/env bash

protocol_requires_domain_cert() {
  case "$1" in
    hysteria2|tuic|naive) return 0 ;;
    *) return 1 ;;
  esac
}

protocols_require_domain_cert() {
  local protocols_csv="$1" p
  local protocols=()
  protocols_to_array "$protocols_csv" protocols
  for p in "${protocols[@]}"; do
    protocol_requires_domain_cert "$p" && return 0
  done
  return 1
}

protocols_domain_cert_reasons() {
  local protocols_csv="$1" p out=""
  local protocols=()
  protocols_to_array "$protocols_csv" protocols
  for p in "${protocols[@]}"; do
    if protocol_requires_domain_cert "$p"; then
      out="${out:+${out},}${p}"
    fi
  done
  printf '%s\n' "$out"
}

sbd_is_ip_literal() {
  local host="${1:-}"
  [[ "$host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && return 0
  [[ "$host" == *:* ]] && return 0
  return 1
}

sbd_cert_matches_domain() {
  local cert="$1" domain="$2"
  openssl x509 -in "$cert" -noout -checkhost "$domain" >/dev/null 2>&1
}

sbd_cert_not_expired() {
  local cert="$1"
  openssl x509 -in "$cert" -noout -checkend 86400 >/dev/null 2>&1
}

sbd_cert_key_match() {
  local cert="$1" key="$2" cert_pub key_pub
  cert_pub="$(openssl x509 -in "$cert" -pubkey -noout 2>/dev/null | openssl pkey -pubin -outform DER 2>/dev/null | sha256sum | awk '{print $1}')"
  key_pub="$(openssl pkey -in "$key" -pubout -outform DER 2>/dev/null | sha256sum | awk '{print $1}')"
  [[ -n "$cert_pub" && "$cert_pub" == "$key_pub" ]]
}

sbd_check_domain_cert_pair() {
  local domain="$1" cert="$2" key="$3"
  [[ -n "$domain" ]] || return 1
  sbd_valid_domain_name "$domain" || return 1
  ! sbd_is_ip_literal "$domain" || return 1
  [[ -f "$cert" && -f "$key" ]] || return 1
  command -v openssl >/dev/null 2>&1 || return 1
  sbd_cert_not_expired "$cert" || return 1
  sbd_cert_matches_domain "$cert" "$domain" || return 1
  sbd_cert_key_match "$cert" "$key" || return 1
}

sbd_validate_domain_cert_pair() {
  local domain="$1" cert="$2" key="$3"
  [[ -n "$domain" ]] || die "Domain certificate mode requires TLS_SERVER_NAME or ACME_DOMAIN"
  sbd_valid_domain_name "$domain" || die "Invalid domain for TLS certificate: ${domain}"
  ! sbd_is_ip_literal "$domain" || die "TLS certificate domain must not be an IP literal: ${domain}"
  [[ -f "$cert" ]] || die "Certificate file not found: ${cert}"
  [[ -f "$key" ]] || die "Private key file not found: ${key}"
  command -v openssl >/dev/null 2>&1 || die "openssl is required to validate domain certificates"
  sbd_cert_not_expired "$cert" || die "Certificate is expired or expires within 24h: ${cert}"
  sbd_cert_matches_domain "$cert" "$domain" || die "Certificate SAN does not match domain ${domain}: ${cert}"
  sbd_cert_key_match "$cert" "$key" || die "Certificate and key do not match: ${cert} / ${key}"
}

sbd_candidate_cert_pairs_for_domain() {
  local domain="$1" base="$1"
  [[ "$base" == "*."* ]] && base="${base#*.}"
  cat <<EOF
/etc/letsencrypt/live/${base}/fullchain.pem|/etc/letsencrypt/live/${base}/privkey.pem
/root/.acme.sh/${base}_ecc/fullchain.cer|/root/.acme.sh/${base}_ecc/${base}.key
/root/.acme.sh/${base}/fullchain.cer|/root/.acme.sh/${base}/${base}.key
EOF
}

sbd_detect_existing_domain_cert() {
  local domain="$1" out_cert_var="$2" out_key_var="$3" cert key
  while IFS='|' read -r cert key; do
    [[ -n "$cert" && -n "$key" ]] || continue
    [[ -f "$cert" && -f "$key" ]] || continue
    if sbd_check_domain_cert_pair "$domain" "$cert" "$key" >/dev/null 2>&1; then
      printf -v "$out_cert_var" '%s' "$cert"
      printf -v "$out_key_var" '%s' "$key"
      return 0
    fi
  done < <(sbd_candidate_cert_pairs_for_domain "$domain")
  return 1
}

prepare_domain_cert_for_protocols() {
  local protocols_csv="$1" reasons domain cert key
  protocols_require_domain_cert "$protocols_csv" || return 0
  reasons="$(protocols_domain_cert_reasons "$protocols_csv")"
  domain="${TLS_SERVER_NAME:-${ACME_DOMAIN:-}}"
  [[ -n "$domain" ]] || die "Protocols require a trusted domain certificate (${reasons}); set --tls-sni/--acme-domain and provide cert paths or use --tls-mode acme-auto"
  sbd_valid_domain_name "$domain" || die "Invalid TLS domain for protocols (${reasons}): ${domain}"
  ! sbd_is_ip_literal "$domain" || die "TLS domain for protocols (${reasons}) must not be an IP literal: ${domain}"

  if [[ "${TLS_MODE:-self-signed}" == "acme" ]]; then
    sbd_validate_domain_cert_pair "$domain" "${ACME_CERT_PATH:-}" "${ACME_KEY_PATH:-}"
    TLS_SERVER_NAME="$domain"
    ACME_DOMAIN="${ACME_DOMAIN:-$domain}"
    return 0
  fi

  if [[ -n "${ACME_CERT_PATH:-}" || -n "${ACME_KEY_PATH:-}" ]]; then
    sbd_validate_domain_cert_pair "$domain" "${ACME_CERT_PATH:-}" "${ACME_KEY_PATH:-}"
    TLS_MODE="acme"
    TLS_SERVER_NAME="$domain"
    ACME_DOMAIN="${ACME_DOMAIN:-$domain}"
    return 0
  fi

  if sbd_detect_existing_domain_cert "$domain" cert key; then
    TLS_MODE="acme"
    TLS_SERVER_NAME="$domain"
    ACME_DOMAIN="${ACME_DOMAIN:-$domain}"
    ACME_CERT_PATH="$cert"
    ACME_KEY_PATH="$key"
    log_info "$(msg "已复用本机证书: ${domain}" "Reusing local certificate for ${domain}")"
    return 0
  fi

  if [[ "${TLS_MODE:-self-signed}" == "acme-auto" ]]; then
    [[ -n "${ACME_EMAIL:-}" ]] || die "TLS_MODE=acme-auto requires --acme-email for domain ${domain}"
    [[ "$(sbd_web_front_mode)" != "off" ]] || die "TLS_MODE=acme-auto uses nginx/OpenResty webroot and requires WEB_FRONT_MODE!=off"
    sbd_write_archive_gateway_site >/dev/null
    sbd_configure_web_front_http_challenge "$domain" >/dev/null
    provider_sys_acme_issue "$domain" "$ACME_EMAIL" "$(sbd_archive_site_dir)"
    cert="${SBD_LAST_ACME_CERT_PATH:-}"
    key="${SBD_LAST_ACME_KEY_PATH:-}"
    sbd_validate_domain_cert_pair "$domain" "$cert" "$key"
    TLS_MODE="acme"
    TLS_SERVER_NAME="$domain"
    ACME_DOMAIN="$domain"
    ACME_CERT_PATH="$cert"
    ACME_KEY_PATH="$key"
    return 0
  fi

  die "Protocols require a trusted certificate (${reasons}) for ${domain}; provide --tls-mode acme --acme-cert-path --acme-key-path or use --tls-mode acme-auto --acme-email"
}

provider_prepare_domain_runtime_artifacts() {
  local protocols_csv="${1:-vless-reality}"
  prepare_domain_cert_for_protocols "$protocols_csv"
  if protocols_require_domain_cert "$protocols_csv"; then
    sbd_write_archive_gateway_site
  fi
}

provider_commit_domain_web_front() {
  local protocols_csv="${1:-vless-reality}"
  protocols_require_domain_cert "$protocols_csv" || return 0
  sbd_configure_web_front "$protocols_csv"
}
