#!/usr/bin/env bash

provider_sys_bbr_status() {
  local qdisc cc
  qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null || true)"
  cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"
  log_info "$(msg "BBR 状态: qdisc=${qdisc:-unknown} cc=${cc:-unknown}" "BBR status: qdisc=${qdisc:-unknown} cc=${cc:-unknown}")"
}

provider_sys_bbr_enable() {
  ensure_root
  local conf="/etc/sysctl.d/99-sing-box-deve-bbr.conf"
  cat > "$conf" <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
  sysctl --system >/dev/null
  provider_sys_bbr_status
  log_success "$(msg "已启用 BBR+FQ" "BBR+FQ enabled")"
}

provider_sys_acme_install() {
  ensure_root
  if [[ ! -d /root/.acme.sh ]]; then
    curl -fsSL https://get.acme.sh | sh
  fi
  log_success "$(msg "acme.sh 已安装" "acme.sh installed")"
}

provider_sys_acme_issue() {
  ensure_root
  local domain="$1" email="$2" dns_provider="${3:-${ACME_DNS_PROVIDER:-}}"
  [[ -n "$domain" && -n "$email" ]] || die "$(msg "用法: sys acme-issue <domain> <email> [dns_provider]" "Usage: sys acme-issue <domain> <email> [dns_provider]")"
  provider_sys_acme_install
  /root/.acme.sh/acme.sh --register-account -m "$email" >/dev/null 2>&1 || true

  local cert_domain="$domain"
  if [[ "$domain" == "*."* ]]; then
    cert_domain="${domain#*.}"
    if [[ -z "$dns_provider" ]]; then
      if [[ -n "${CF_Token:-}" || -n "${CF_Key:-}" ]]; then
        dns_provider="dns_cf"
      fi
    fi
    [[ -n "$dns_provider" ]] || die "$(msg "泛域名证书需要 DNS 验证，请设置 ACME_DNS_PROVIDER（如 dns_cf）及对应凭据" "Wildcard cert requires DNS challenge. Set ACME_DNS_PROVIDER (e.g. dns_cf) and provider credentials.")"
    /root/.acme.sh/acme.sh --issue --dns "$dns_provider" -d "$cert_domain" -d "*.${cert_domain}"
    log_info "$(msg "已使用 DNS 验证签发泛域名证书: provider=${dns_provider}" "Issued wildcard cert via DNS challenge: provider=${dns_provider}")"
  else
    /root/.acme.sh/acme.sh --issue -d "$domain" --standalone
  fi

  local cert="/root/.acme.sh/${cert_domain}_ecc/fullchain.cer"
  local key="/root/.acme.sh/${cert_domain}_ecc/${cert_domain}.key"
  [[ -f "$cert" && -f "$key" ]] || die "$(msg "ACME 签发成功但证书文件缺失" "ACME issue succeeded but cert files missing")"
  log_success "$(msg "ACME 证书签发完成: cert=${cert} key=${key}" "ACME cert issued: cert=${cert} key=${key}")"
}

provider_sys_acme_apply() {
  ensure_root
  local cert="$1" key="$2"
  [[ -f "$cert" && -f "$key" ]] || die "$(msg "用法: sys acme-apply <cert_path> <key_path>" "Usage: sys acme-apply <cert_path> <key_path>")"
  provider_cfg_command tls acme "$cert" "$key"
}

provider_sys_command() {
  local action="${1:-status}"
  shift || true
  case "$action" in
    bbr-status) provider_sys_bbr_status ;;
    bbr-enable) provider_sys_bbr_enable ;;
    acme-install) provider_sys_acme_install ;;
    acme-issue) provider_sys_acme_issue "$@" ;;
    acme-apply) provider_sys_acme_apply "$@" ;;
    *)
      die "$(msg "用法: sys [bbr-status|bbr-enable|acme-install|acme-issue <domain> <email> [dns_provider]|acme-apply <cert> <key>]" "Usage: sys [bbr-status|bbr-enable|acme-install|acme-issue <domain> <email> [dns_provider]|acme-apply <cert> <key>]")"
      ;;
  esac
}
