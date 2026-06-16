#!/usr/bin/env bash

sbd_configure_web_front() {
  local protocols_csv="${1:-vless-reality}" domain cert key found engine bin paths conf_file service site_dir
  sbd_web_front_required "$protocols_csv" || return 0
  [[ "$(sbd_web_front_mode)" != "off" ]] || return 0
  sbd_web_front_assert_tcp443_available "$protocols_csv"
  sbd_web_front_install_if_needed || return 0
  found="$(sbd_find_web_front)" || return 0
  engine="${found%%|*}"
  bin="${found#*|}"
  domain="$(sbd_nginx_safe_server_name "$(sbd_tls_server_name)")"
  cert="$(sbd_nginx_safe_path certificate "${ACME_CERT_PATH:-}")"
  key="$(sbd_nginx_safe_path certificate-key "${ACME_KEY_PATH:-}")"
  site_dir="$(sbd_nginx_safe_path site-root "$(sbd_archive_site_dir)")"
  [[ -n "$domain" ]] || die "Web front requires TLS domain"
  [[ -d "$site_dir" ]] || die "Archive site directory not found: ${site_dir}"

  if [[ "$engine" == "openresty" ]]; then
    sbd_ensure_openresty_confd_include "$(sbd_openresty_conf_root)" "$bin"
  fi
  paths="$(sbd_web_front_conf_paths "$engine")"
  conf_file="${paths%%|*}"
  paths="${paths#*|}"
  bin="${paths%%|*}"
  service="${paths#*|}"

  sbd_write_web_front_conf_staged "$conf_file" "$bin" "$domain" "$cert" "$key" "$site_dir"
  sbd_web_front_open_firewall
  sbd_web_front_reload "$engine" "$bin" "$service"
  WEB_FRONT_ENGINE="$engine"
  WEB_FRONT_CONF="$conf_file"
  WEB_FRONT_DOMAIN="$domain"
  export WEB_FRONT_ENGINE WEB_FRONT_CONF WEB_FRONT_DOMAIN
  printf 'WEB_FRONT_ENGINE=%s\nWEB_FRONT_CONF=%s\nWEB_FRONT_DOMAIN=%s\n' "$engine" "$conf_file" "$domain" > "${SBD_DATA_DIR}/web_front.env"
}
