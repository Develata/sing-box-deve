#!/usr/bin/env bash

sbd_systemd_unit_exists() {
  local service="$1"
  command -v systemctl >/dev/null 2>&1 || return 1
  systemctl list-unit-files --type=service --no-legend "${service}.service" 2>/dev/null | awk -v svc="${service}.service" '$1 == svc { found = 1 } END { exit(found ? 0 : 1) }'
}

sbd_web_front_reload() {
  local engine="$1" bin="$2" service="$3"
  if [[ "${SBD_USER_MODE:-false}" == "true" ]]; then
    log_warn "$(msg "用户模式下跳过 web front reload" "User mode: skip web front reload")"
    return 0
  fi
  "$bin" -t >/dev/null
  if sbd_systemd_unit_exists "$service"; then
    systemctl enable "$service" >/dev/null 2>&1 || true
    systemctl reload "$service" >/dev/null 2>&1 || systemctl restart "$service" >/dev/null || die "Failed to reload/restart ${service} via systemd"
  else
    "$bin" -s reload >/dev/null 2>&1 || die "Failed to reload ${engine}; no systemd unit found and binary reload failed"
  fi
  log_success "$(msg "Web front 已启用: ${engine}" "Web front enabled: ${engine}")"
}

sbd_web_front_open_firewall() {
  [[ "${SBD_USER_MODE:-false}" != "true" ]] || return 0
  if [[ -z "${FW_BACKEND:-}" ]]; then
    if ! fw_detect_backend_optional >/dev/null 2>&1; then
      log_warn "$(msg "未检测到防火墙后端；请确认 TCP 80/443 已开放" "Firewall backend not detected; ensure TCP 80/443 are open")"
      return 0
    fi
  fi
  fw_apply_rule tcp 80 web-front
  fw_apply_rule tcp 443 web-front
}

sbd_write_web_front_conf_staged() {
  local conf_file="$1" bin="$2" domain="$3" cert="$4" key="$5" site_dir="$6"
  local conf_dir tmp_conf backup=""
  conf_dir="$(dirname "$conf_file")"
  mkdir -p "$conf_dir"
  tmp_conf="$(mktemp "${conf_file}.tmp.XXXXXX")"
  cat > "$tmp_conf" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${domain};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${domain};

    ssl_certificate ${cert};
    ssl_certificate_key ${key};
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;

    root ${site_dir};
    index index.html;

    location / {
        try_files \$uri \$uri/ /404.html;
    }
}
EOF

  if [[ -f "$conf_file" ]]; then
    backup="$(mktemp "${conf_file}.bak.XXXXXX")"
    cp -f "$conf_file" "$backup"
  fi
  mv -f "$tmp_conf" "$conf_file"
  if ! "$bin" -t >/dev/null; then
    if [[ -n "$backup" ]]; then
      mv -f "$backup" "$conf_file"
    else
      rm -f "$conf_file"
    fi
    die "Web front generated config failed syntax test: ${conf_file}"
  fi
  if [[ "${SBD_USER_MODE:-false}" != "true" ]] && ! "$bin" -T 2>&1 | grep -Fq "$conf_file"; then
    if [[ -n "$backup" ]]; then
      mv -f "$backup" "$conf_file"
    else
      rm -f "$conf_file"
    fi
    die "Web front managed config is not included by nginx/OpenResty: ${conf_file}"
  fi
  [[ -z "$backup" ]] || rm -f "$backup"
}
