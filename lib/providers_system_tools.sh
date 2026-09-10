#!/usr/bin/env bash
# shellcheck disable=SC2016
# shellcheck disable=SC2034

SBD_LAST_ACME_CERT_PATH=""
SBD_LAST_ACME_KEY_PATH=""

sbd_valid_domain_name() {
  local domain="${1:-}" label
  local -a labels
  [[ "$domain" == "*."* ]] && domain="${domain#*.}"
  [[ -n "$domain" && ${#domain} -le 253 ]] || return 1
  [[ "$domain" == *.* ]] || return 1
  [[ "$domain" =~ ^[A-Za-z0-9.-]+$ ]] || return 1
  [[ "$domain" != .* && "$domain" != *. && "$domain" != *..* ]] || return 1

  local IFS='.'
  read -r -a labels <<< "$domain"
  for label in "${labels[@]}"; do
    [[ -n "$label" && ${#label} -le 63 ]] || return 1
    [[ "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
  done
}

acme_base_domain() {
  local domain="${1:-}"
  if [[ "$domain" == "*."* ]]; then
    domain="${domain#*.}"
  fi
  printf '%s' "$domain"
}

acme_resolve_existing_cert() {
  local domain="${1:-}" out_cert_var="${2:-}" out_key_var="${3:-}"
  local base dir candidate_cert candidate_key
  [[ -n "$domain" && -n "$out_cert_var" && -n "$out_key_var" ]] || return 1
  base="$(acme_base_domain "$domain")"

  local dirs=(
    "/root/.acme.sh/${base}_ecc"
    "/root/.acme.sh/${base}"
  )

  for dir in "${dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    for candidate_cert in "$dir/fullchain.cer" "$dir/${base}.cer"; do
      [[ -f "$candidate_cert" ]] || continue
      for candidate_key in "$dir/${base}.key" "$dir/private.key"; do
        [[ -f "$candidate_key" ]] || continue
        sbd_check_domain_cert_pair "$domain" "$candidate_cert" "$candidate_key" || continue
        printf -v "$out_cert_var" '%s' "$candidate_cert"
        printf -v "$out_key_var" '%s' "$candidate_key"
        return 0
      done
    done
  done
  return 1
}

provider_sys_bbr_status() {
  local qdisc cc
  qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null || true)"
  cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"
  log_info "$(msg "BBR 状态: qdisc=${qdisc:-unknown} cc=${cc:-unknown}" "BBR status: qdisc=${qdisc:-unknown} cc=${cc:-unknown}")"
}

provider_sys_bbr_enable() {
  ensure_root
  local conf="/etc/sysctl.d/99-sing-box-deve-bbr.conf" candidate
  sbd_capture_sysctl_runtime || return 1
  candidate="$(mktemp "${conf}.tmp.XXXXXX")" || return 1
  cat > "$candidate" <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
  sbd_host_file_publish "$conf" "$candidate" || return 1
  sbd_run_deadline 30 sysctl --system >/dev/null || return 1
  provider_sys_bbr_status
  log_success "$(msg "已启用 BBR+FQ" "BBR+FQ enabled")"
}

provider_sys_acme_install() {
  ensure_root
  if [[ ! -x /root/.acme.sh/acme.sh ]]; then
    local installer url="${SBD_ACME_INSTALLER_URL:-}" expected="${SBD_ACME_INSTALLER_SHA256:-}"
    [[ "$url" == https://* && "$expected" =~ ^[a-fA-F0-9]{64}$ ]] || {
      log_error "ACME installation requires a reviewed SBD_ACME_INSTALLER_URL and SBD_ACME_INSTALLER_SHA256, or an existing acme.sh installation"
      return 1
    }
    installer="$(mktemp)" || return 1
    if ! download_file "$url" "$installer" || ! verify_sha256_expected "$installer" "${expected,,}"; then
      rm -f "$installer"; return 1
    fi
    if ! sbd_run_deadline 180 sh "$installer" --install --home /root/.acme.sh; then rm -f "$installer"; return 1; fi
    rm -f "$installer"
  fi
  [[ -x /root/.acme.sh/acme.sh ]] || return 1
  log_success "acme.sh installed"
}

provider_sys_acme_issue() {
  ensure_root
  local domain="${1:-}" email="${2:-}" webroot="${3:-}"
  [[ -n "$domain" && -n "$email" ]] || die "$(msg "用法: sys acme-issue <domain> <email> [webroot]" "Usage: sys acme-issue <domain> <email> [webroot]")"
  sbd_valid_domain_name "$domain" || die "Invalid ACME domain: ${domain}"
  [[ "$domain" != "*."* ]] || die "Wildcard certificates are not supported by acme-auto; provide certificate paths manually"
  [[ "$webroot" != dns_* ]] || die "DNS ACME providers are no longer accepted by sys acme-issue; use nginx/OpenResty webroot or provide certificate paths"
  [[ "$email" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] || die "Invalid ACME account email: ${email}"
  SBD_LAST_ACME_CERT_PATH=""
  SBD_LAST_ACME_KEY_PATH=""

  local existing_cert existing_key
  if acme_resolve_existing_cert "$domain" existing_cert existing_key; then
    provider_sys_acme_deploy "$domain" || return 1
    log_info "$(msg "检测到已存在证书，直接复用: cert=${existing_cert} key=${existing_key}" "Existing certificate detected, reusing: cert=${existing_cert} key=${existing_key}")"
    return 0
  fi

  provider_sys_acme_install || return 1
  sbd_run_deadline 60 /root/.acme.sh/acme.sh --register-account -m "$email" >/dev/null 2>&1 || return 1

  if [[ -z "$webroot" ]]; then
    sbd_write_archive_gateway_site >/dev/null
    sbd_configure_web_front_http_challenge "$domain" >/dev/null
    webroot="$(sbd_archive_site_dir)"
  fi
  [[ -d "$webroot" ]] || die "ACME webroot directory not found: ${webroot}"
  sbd_run_deadline "${SBD_ACME_TIMEOUT:-300}" /root/.acme.sh/acme.sh --issue --keylength ec-256 -d "$domain" --webroot "$webroot" || return 1

  local cert="" key=""
  acme_resolve_existing_cert "$domain" cert key || true
  [[ -n "$cert" && -n "$key" ]] || {
    cert="/root/.acme.sh/${domain}_ecc/fullchain.cer"
    key="/root/.acme.sh/${domain}_ecc/${domain}.key"
  }
  [[ -f "$cert" && -f "$key" ]] || die "$(msg "ACME 签发成功但证书文件缺失" "ACME issue succeeded but cert files missing")"
  sbd_validate_domain_cert_pair "$domain" "$cert" "$key" || return 1
  provider_sys_acme_deploy "$domain" || return 1
  log_success "$(msg "ACME webroot 证书签发完成: cert=${cert} key=${key}" "ACME webroot cert issued: cert=${cert} key=${key}")"
}

provider_sys_acme_apply() {
  ensure_root
  local cert="${1:-}" key="${2:-}"
  [[ -f "$cert" && -f "$key" ]] || die "$(msg "用法: sys acme-apply <cert_path> <key_path>" "Usage: sys acme-apply <cert_path> <key_path>")"
  provider_cfg_command tls acme "$cert" "$key"
}

provider_sys_command() {
  if [[ "${1:-status}" == bbr-status || "${1:-status}" == status ]]; then provider_sys_command_unlocked "$@"; return $?; fi
  sbd_with_mutation_lock sbd_transaction_run host-change provider_sys_command_unlocked "$@"
}

provider_sys_command_unlocked() {
  local action="${1:-status}"
  shift || true
  case "$action" in
    bbr-status) provider_sys_bbr_status ;;
    bbr-enable) provider_sys_bbr_enable ;;
    acme-install) provider_sys_acme_install ;;
    acme-issue) provider_sys_acme_issue "$@" ;;
    acme-apply) provider_sys_acme_apply "$@" ;;
    *)
      die "$(msg "用法: sys [bbr-status|bbr-enable|acme-install|acme-issue <domain> <email> [webroot]|acme-apply <cert> <key>]" "Usage: sys [bbr-status|bbr-enable|acme-install|acme-issue <domain> <email> [webroot]|acme-apply <cert> <key>]")"
      ;;
  esac
}

# acme.sh retains renewal configuration and copies certificates to managed paths.
provider_sys_acme_deploy() {
  local domain="$1" hook
  printf -v hook 'if [ "${SBD_CERT_DEPLOY_PARENT:-0}" != 1 ] && [ -f %q ]; then %q cfg rebuild; fi' "$SBD_CONFIG_DIR/runtime.env" "${SBD_LAUNCHER_PATH:-/usr/local/bin/sb}"
  SBD_CERT_DEPLOY_PARENT=1 sbd_run_deadline "${SBD_ACME_TIMEOUT:-300}" /root/.acme.sh/acme.sh --install-cert -d "$domain" --ecc \
    --key-file "$SBD_DATA_DIR/acme-key.pem" --fullchain-file "$SBD_DATA_DIR/acme-cert.pem" --reloadcmd "$hook" || return 1
  sbd_validate_domain_cert_pair "$domain" "$SBD_DATA_DIR/acme-cert.pem" "$SBD_DATA_DIR/acme-key.pem" || return 1
  SBD_LAST_ACME_CERT_PATH="$SBD_DATA_DIR/acme-cert.pem"
  SBD_LAST_ACME_KEY_PATH="$SBD_DATA_DIR/acme-key.pem"
}

sbd_capture_sysctl_runtime() {
  local file name
  [[ -n "${SBD_ACTIVE_TRANSACTION:-}" ]] || return 1
  file="$SBD_ACTIVE_TRANSACTION/sysctl.before"
  [[ ! -f "$file" ]] || return 0
  for name in net.core.default_qdisc net.ipv4.tcp_congestion_control; do
    sbd_run_deadline 10 sysctl -n "$name" >> "$file" || return 1
  done
  sha256sum "$file" > "$file.sha256" || return 1
  sbd_sync_directory "$SBD_ACTIVE_TRANSACTION"
}

sbd_restore_sysctl_runtime() {
  local file="$1/sysctl.before" name current old expected i=0
  local -a values names=(net.core.default_qdisc net.ipv4.tcp_congestion_control) managed=(fq bbr)
  [[ -f "$file" ]] || return 0
  [[ "$(sha256sum "$file")" == "$(cat "$file.sha256")" ]] || return 1
  mapfile -t values < "$file"
  [[ "${#values[@]}" == 2 ]] || return 1
  for name in "${names[@]}"; do
    old="${values[i]}"; expected="${managed[i]}"; i=$((i + 1))
    [[ "$old" =~ ^[a-zA-Z0-9_-]+$ ]] || return 1
    current="$(sbd_run_deadline 10 sysctl -n "$name")" || return 1
    [[ "$current" == "$old" ]] && continue
    [[ "$current" == "$expected" ]] || { log_error "Keeping externally changed sysctl: $name"; return 1; }
    sbd_run_deadline 10 sysctl -w "$name=$old" >/dev/null || return 1
  done
}
