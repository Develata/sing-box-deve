#!/usr/bin/env bash

sbd_nginx_official_install_supported() {
  [[ "${OS_ID:-}" == "debian" || "${OS_ID:-}" == "ubuntu" ]]
}

sbd_install_official_nginx_apt() (
  ensure_root
  sbd_nginx_official_install_supported || return 1
  local work key_fprs codename repo_os
  work="$(mktemp -d)" || return 1
  trap 'rm -rf "$work"' EXIT
  sbd_apt_get update -y >/dev/null || return 1
  if [[ "${OS_ID:-}" == ubuntu ]]; then
    sbd_apt_get install -y curl gnupg2 ca-certificates lsb-release ubuntu-keyring >/dev/null || return 1
  else
    sbd_apt_get install -y curl gnupg2 ca-certificates lsb-release debian-archive-keyring >/dev/null || return 1
  fi
  sbd_http_small https://nginx.org/keys/nginx_signing.key -o "$work/signing.key" || return 1
  sbd_run_deadline 30 gpg --batch --dearmor --output "$work/keyring.gpg" "$work/signing.key" || return 1
  key_fprs="$(sbd_run_deadline 30 gpg --show-keys --with-colons --fingerprint "$work/keyring.gpg" 2>/dev/null | awk -F: '$1 == "fpr" {print $10}')" || return 1
  grep -qx '573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62' <<< "$key_fprs" || { log_error "Unexpected nginx signing key"; return 1; }
  codename="${VERSION_CODENAME:-}"
  [[ -n "$codename" ]] || codename="$(lsb_release -cs)" || return 1
  [[ "$codename" =~ ^[a-zA-Z0-9_-]+$ ]] || return 1
  repo_os=debian; [[ "${OS_ID:-}" != ubuntu ]] || repo_os=ubuntu
  printf 'deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] https://nginx.org/packages/%s %s nginx\n' "$repo_os" "$codename" > "$work/nginx.list" || return 1
  printf 'Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n' > "$work/99nginx" || return 1
  mkdir -p /usr/share/keyrings /etc/apt/sources.list.d /etc/apt/preferences.d || return 1
  sbd_host_file_publish /usr/share/keyrings/nginx-archive-keyring.gpg "$work/keyring.gpg" || return 1
  sbd_host_file_publish /etc/apt/sources.list.d/nginx.list "$work/nginx.list" || return 1
  sbd_host_file_publish /etc/apt/preferences.d/99nginx "$work/99nginx" || return 1
  sbd_apt_get update -y >/dev/null || return 1
  sbd_apt_get install -y nginx >/dev/null || return 1
  log_success "nginx installed from the official nginx.org repository"
)

sbd_web_front_install_if_needed() {
  local mode
  mode="$(sbd_web_front_mode)"
  [[ "$mode" != "off" ]] || return 1
  if sbd_find_web_front >/dev/null; then
    return 0
  fi
  if [[ "$mode" == "openresty" || "$mode" == "nginx" ]]; then
    sbd_find_web_front >/dev/null || die "WEB_FRONT_MODE=${mode} requested but no usable ${mode}/OpenResty web front was found"
    return 0
  fi
  if [[ "${SBD_USER_MODE:-false}" == "true" ]]; then
    log_warn "$(msg "用户模式下跳过 nginx 自动安装；archive-gateway 仅写入文件与 Hysteria2 masquerade" "User mode: skip nginx auto-install; archive-gateway is only written to files and Hysteria2 masquerade")"
    return 1
  fi
  [[ -n "${OS_ID:-}" ]] || detect_os
  if ! sbd_nginx_official_install_supported; then
    log_warn "$(msg "当前系统不支持 nginx.org 自动安装；请手动安装 OpenResty/nginx 或设置 --web-front off" "Official nginx auto-install is unsupported on this OS; install OpenResty/nginx manually or set --web-front off")"
    return 1
  fi
  if prompt_yes_no "$(msg "未检测到 OpenResty/nginx。是否按 nginx.org 官方方式安装 nginx 并启用域名静态站？" "OpenResty/nginx not found. Install official nginx from nginx.org and enable the domain static site?")" "N"; then
    sbd_install_official_nginx_apt || return 1
    return 0
  fi
  log_warn "$(msg "已跳过 nginx 安装；普通浏览器访问域名不会由脚本提供静态站" "Skipped nginx install; normal browser access to the domain will not be served by this script")"
  return 1
}
