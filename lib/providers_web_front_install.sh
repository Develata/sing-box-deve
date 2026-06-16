#!/usr/bin/env bash

sbd_nginx_official_install_supported() {
  [[ "${OS_ID:-}" == "debian" || "${OS_ID:-}" == "ubuntu" ]]
}

sbd_install_official_nginx_apt() {
  ensure_root
  sbd_nginx_official_install_supported || die "Official nginx auto-install currently supports Debian/Ubuntu only; install nginx/openresty manually or set --web-front off"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y >/dev/null
  if [[ "${OS_ID:-}" == "ubuntu" ]]; then
    apt-get install -y curl gnupg2 ca-certificates lsb-release ubuntu-keyring >/dev/null
  else
    apt-get install -y curl gnupg2 ca-certificates lsb-release debian-archive-keyring >/dev/null
  fi
  mkdir -p /usr/share/keyrings /etc/apt/sources.list.d /etc/apt/preferences.d
  curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor > /usr/share/keyrings/nginx-archive-keyring.gpg
  if ! gpg --dry-run --quiet --no-keyring --import --import-options import-show /usr/share/keyrings/nginx-archive-keyring.gpg 2>/dev/null | grep -q '573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62'; then
    die "Unable to verify official nginx signing key fingerprint"
  fi
  local codename repo_os
  codename="${VERSION_CODENAME:-}"
  [[ -n "$codename" ]] || codename="$(lsb_release -cs 2>/dev/null || true)"
  [[ -n "$codename" ]] || die "Unable to detect distro codename for nginx.org repository"
  repo_os="debian"
  [[ "${OS_ID:-}" == "ubuntu" ]] && repo_os="ubuntu"
  printf 'deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] https://nginx.org/packages/%s %s nginx\n' "$repo_os" "$codename" > /etc/apt/sources.list.d/nginx.list
  cat > /etc/apt/preferences.d/99nginx <<'EOF'
Package: *
Pin: origin nginx.org
Pin: release o=nginx
Pin-Priority: 900
EOF
  apt-get update -y >/dev/null
  apt-get install -y nginx >/dev/null
  log_success "$(msg "已通过 nginx.org 官方仓库安装 nginx" "nginx installed from the official nginx.org repository")"
}

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
  if ! sbd_nginx_official_install_supported; then
    log_warn "$(msg "当前系统不支持 nginx.org 自动安装；请手动安装 OpenResty/nginx 或设置 --web-front off" "Official nginx auto-install is unsupported on this OS; install OpenResty/nginx manually or set --web-front off")"
    return 1
  fi
  if prompt_yes_no "$(msg "未检测到 OpenResty/nginx。是否按 nginx.org 官方方式安装 nginx 并启用域名静态站？" "OpenResty/nginx not found. Install official nginx from nginx.org and enable the domain static site?")" "N"; then
    sbd_install_official_nginx_apt
    return 0
  fi
  log_warn "$(msg "已跳过 nginx 安装；普通浏览器访问域名不会由脚本提供静态站" "Skipped nginx install; normal browser access to the domain will not be served by this script")"
  return 1
}
