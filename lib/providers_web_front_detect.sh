#!/usr/bin/env bash

sbd_web_front_required() { protocols_require_domain_cert "${1:-vless-reality}"; }

sbd_web_front_mode() { param_get "WEB_FRONT_MODE" "web_front_mode" "auto"; }

sbd_find_openresty_bin() {
  if command -v openresty >/dev/null 2>&1; then
    command -v openresty
    return 0
  fi
  if [[ -x /usr/local/openresty/nginx/sbin/nginx ]]; then
    printf '%s\n' /usr/local/openresty/nginx/sbin/nginx
    return 0
  fi
  return 1
}

sbd_find_web_front() {
  local mode openresty_bin nginx_bin
  mode="$(sbd_web_front_mode)"
  case "$mode" in
    off) return 1 ;;
    openresty)
      openresty_bin="$(sbd_find_openresty_bin 2>/dev/null || true)"
      [[ -n "$openresty_bin" ]] || return 1
      printf '%s\n' "openresty|${openresty_bin}"
      return 0
      ;;
    nginx)
      openresty_bin="$(sbd_find_openresty_bin 2>/dev/null || true)"
      if [[ -n "$openresty_bin" ]]; then
        printf '%s\n' "openresty|${openresty_bin}"
        return 0
      fi
      nginx_bin="$(command -v nginx 2>/dev/null || true)"
      [[ -n "$nginx_bin" ]] || return 1
      printf '%s\n' "nginx|${nginx_bin}"
      return 0
      ;;
    auto)
      openresty_bin="$(sbd_find_openresty_bin 2>/dev/null || true)"
      if [[ -n "$openresty_bin" ]]; then
        printf '%s\n' "openresty|${openresty_bin}"
        return 0
      fi
      nginx_bin="$(command -v nginx 2>/dev/null || true)"
      if [[ -n "$nginx_bin" ]]; then
        printf '%s\n' "nginx|${nginx_bin}"
        return 0
      fi
      return 1
      ;;
    *) die "WEB_FRONT_MODE must be auto|off|nginx|openresty" ;;
  esac
}

sbd_web_front_assert_tcp443_available() {
  local protocols_csv="${1:-vless-reality}" p mapping proto port conflicts="" engine_name
  local protocols=()
  engine_name="${ENGINE:-${engine:-sing-box}}"
  protocols_to_array "$protocols_csv" protocols
  for p in "${protocols[@]}"; do
    protocol_needs_local_listener "$p" || continue
    mapping="$(protocol_port_map "$p")"
    proto="${mapping%%:*}"
    [[ "$proto" == "tcp" ]] || continue
    port="$(resolve_protocol_port_for_engine "$engine_name" "$p" 2>/dev/null || get_protocol_port "$p")"
    if [[ "$port" == "443" ]]; then
      conflicts="${conflicts:+${conflicts},}${p}"
    fi
  done
  [[ -z "$conflicts" ]] || die "Web front uses TCP 443; move selected TCP protocol(s) off 443 first: ${conflicts}"
}

sbd_web_front_preflight() {
  local protocols_csv="${1:-vless-reality}"
  sbd_web_front_required "$protocols_csv" || return 0
  [[ "$(sbd_web_front_mode)" != "off" ]] || return 0
  sbd_web_front_assert_tcp443_available "$protocols_csv"
}

sbd_openresty_conf_root() {
  local bin conf_path prefix conf_dir
  if [[ -n "${SBD_OPENRESTY_CONF_ROOT:-}" ]]; then
    printf '%s\n' "$SBD_OPENRESTY_CONF_ROOT"
    return 0
  fi
  if [[ "${SBD_USER_MODE:-false}" == "true" ]]; then
    printf '%s\n' "${SBD_CONFIG_DIR}/web-front/openresty"
    return 0
  fi
  if [[ -d /usr/local/openresty/nginx/conf ]]; then
    printf '%s\n' /usr/local/openresty/nginx/conf
    return 0
  fi
  bin="$(sbd_find_openresty_bin 2>/dev/null || true)"
  if [[ -n "$bin" ]]; then
    local version_out
    version_out="$($bin -V 2>&1 || true)"
    conf_path="$(printf '%s\n' "$version_out" | sed -nE 's/.*--conf-path=([^[:space:]]+).*/\1/p' | head -n1)"
    prefix="$(printf '%s\n' "$version_out" | sed -nE 's/.*--prefix=([^[:space:]]+).*/\1/p' | head -n1)"
    if [[ -n "$conf_path" ]]; then
      if [[ "$conf_path" == /* ]]; then
        printf '%s\n' "$(dirname "$conf_path")"
        return 0
      fi
      if [[ -n "$prefix" ]]; then
        conf_dir="$(dirname "${prefix%/}/$conf_path")"
        printf '%s\n' "$conf_dir"
        return 0
      fi
    fi
  fi
  printf '%s\n' /etc/nginx
}

sbd_nginx_conf_dir() {
  if [[ -n "${SBD_NGINX_CONF_DIR:-}" ]]; then
    printf '%s\n' "$SBD_NGINX_CONF_DIR"
  elif [[ "${SBD_USER_MODE:-false}" == "true" ]]; then
    printf '%s\n' "${SBD_CONFIG_DIR}/web-front/nginx/conf.d"
  else
    printf '%s\n' /etc/nginx/conf.d
  fi
}

sbd_nginx_safe_server_name() {
  local value="$1"
  [[ -n "$value" ]] || die "Web front requires TLS domain"
  sbd_valid_domain_name "$value" || die "nginx server_name contains unsupported characters: ${value}"
  ! sbd_is_ip_literal "$value" || die "nginx server_name must not be an IP literal: ${value}"
  printf '%s\n' "$value"
}

sbd_nginx_safe_path() {
  local label="$1" value="$2"
  [[ -n "$value" ]] || die "Missing nginx path for ${label}"
  [[ "$value" == /* ]] || die "nginx ${label} path must be absolute: ${value}"
  [[ "$value" =~ ^[-_./A-Za-z0-9:@=+*]+$ ]] || die "nginx ${label} path contains unsupported characters: ${value}"
  printf '%s\n' "$value"
}

sbd_web_front_conf_paths() {
  local engine="$1" conf_root conf_dir conf_file service bin
  if [[ "$engine" == "openresty" ]]; then
    conf_root="$(sbd_openresty_conf_root)"
    conf_dir="${conf_root}/conf.d"
    conf_file="${conf_dir}/sing-box-deve-archive.conf"
    bin="$(sbd_find_openresty_bin)"
    service="openresty"
  else
    conf_dir="$(sbd_nginx_conf_dir)"
    conf_file="${conf_dir}/sing-box-deve-archive.conf"
    bin="$(command -v nginx)"
    service="nginx"
  fi
  printf '%s|%s|%s\n' "$conf_file" "$bin" "$service"
}
