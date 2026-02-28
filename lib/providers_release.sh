#!/usr/bin/env bash

sbd_offline_mode_enabled() {
  [[ "${SBD_OFFLINE_MODE:-false}" == "true" ]]
}

fetch_latest_release_tag() {
  local repo="$1"
  curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" | jq -r '.tag_name'
}

fetch_release_asset_url() {
  local repo="$1"
  local tag="$2"
  local asset_name="$3"
  curl -fsSL "https://api.github.com/repos/${repo}/releases/tags/${tag}" | jq -r \
    --arg name "$asset_name" '.assets[] | select(.name==$name) | .browser_download_url' | head -n1
}

fetch_release_asset_digest() {
  local repo="$1"
  local tag="$2"
  local asset_name="$3"
  curl -fsSL "https://api.github.com/repos/${repo}/releases/tags/${tag}" | jq -r \
    --arg name "$asset_name" '.assets[] | select(.name==$name) | .digest // empty' | head -n1
}

verify_sha256_from_checksums_file() {
  local archive="$1"
  local checksums_file="$2"
  local filename
  filename="$(basename "$archive")"

  local expected
  expected="$(grep -F "${filename}" "$checksums_file" | awk '{print $1}' | head -n1)"
  [[ -n "$expected" ]] || die "Missing checksum entry for ${filename}"

  local actual
  actual="$(sha256sum "$archive" | awk '{print $1}')"
  [[ "$expected" == "$actual" ]] || die "Checksum mismatch for ${filename}"
}

verify_sha256_from_xray_dgst() {
  local archive="$1"
  local dgst_file="$2"
  local expected
  expected="$(awk '/SHA256/{print $NF}' "$dgst_file" | head -n1)"
  [[ -n "$expected" ]] || die "Unable to parse SHA256 from xray dgst"

  local actual
  actual="$(sha256sum "$archive" | awk '{print $1}')"
  [[ "$expected" == "$actual" ]] || die "Checksum mismatch for $(basename "$archive")"
}

verify_sha256_expected() {
  local archive="$1"
  local expected_sha256="$2"
  [[ -n "$expected_sha256" ]] || die "Missing expected sha256 for $(basename "$archive")"
  local actual
  actual="$(sha256sum "$archive" | awk '{print $1}')"
  [[ "$expected_sha256" == "$actual" ]] || die "Checksum mismatch for $(basename "$archive")"
}

install_sing_box_binary() {
  local input_tag="${1:-latest}"
  local arch
  arch="$(get_arch)"
  if sbd_offline_mode_enabled; then
    if [[ -x "${SBD_BIN_DIR}/sing-box" ]]; then
      log_warn "$(msg "SBD_OFFLINE_MODE=true；使用本地已有 sing-box 二进制" "SBD_OFFLINE_MODE=true; using existing local sing-box binary")"
      return 0
    fi
    die "$(msg "SBD_OFFLINE_MODE=true，但未找到本地 sing-box 二进制" "SBD_OFFLINE_MODE=true but local sing-box binary not found")"
  fi
  local tag
  if [[ "$input_tag" == "latest" ]]; then
    tag="$(fetch_latest_release_tag "SagerNet/sing-box")"
  else
    tag="$input_tag"
    [[ "$tag" == v* ]] || tag="v${tag}"
  fi
  [[ -n "$tag" && "$tag" != "null" ]] || die "$(msg "无法获取最新 sing-box 发布版本" "Unable to fetch latest sing-box release")"

  local version="${tag#v}"
  local filename="sing-box-${version}-linux-${arch}.tar.gz"
  local url digest expected
  url="$(fetch_release_asset_url "SagerNet/sing-box" "$tag" "$filename")"
  digest="$(fetch_release_asset_digest "SagerNet/sing-box" "$tag" "$filename")"
  [[ -n "$url" ]] || die "$(msg "找不到 sing-box 资产文件: ${filename}" "Unable to locate sing-box asset: ${filename}")"
  expected=""
  if [[ "$digest" == sha256:* ]]; then
    expected="${digest#sha256:}"
  fi
  local cache_dir="${SBD_CACHE_DIR:-${SBD_INSTALL_DIR}/cache}"
  mkdir -p "$cache_dir"
  local archive="${cache_dir}/${filename}"
  local sums_file="${cache_dir}/sing-box-${version}-checksums.txt"

  log_info "$(msg "正在安装 sing-box ${tag}" "Installing sing-box ${tag}")"
  if download_file "$url" "$archive"; then
    if [[ -n "$expected" ]]; then
      verify_sha256_expected "$archive" "$expected"
    else
      log_warn "$(msg "发布摘要缺失，回退到 checksums 文件校验" "Release digest metadata missing; fallback to checksums file")"
      download_file "https://github.com/SagerNet/sing-box/releases/download/${tag}/sing-box-${version}-checksums.txt" "$sums_file"
      verify_sha256_from_checksums_file "$archive" "$sums_file"
    fi
    tar -xzf "$archive" -C "$cache_dir"
    install -m 0755 "${cache_dir}/sing-box-${version}-linux-${arch}/sing-box" "${SBD_BIN_DIR}/sing-box"
    rm -rf "${cache_dir}/sing-box-${version}-linux-${arch}" "$archive" "$sums_file" 2>/dev/null || true
  else
    if [[ -x "${SBD_BIN_DIR}/sing-box" ]]; then
      log_warn "$(msg "下载 sing-box ${tag} 失败，复用本地已有二进制" "Failed to download sing-box ${tag}; reusing existing local binary")"
      return 0
    fi
    die "$(msg "无法下载 sing-box，且本地不存在可用二进制" "Unable to download sing-box and no local binary available")"
  fi

  echo "$tag" > "${SBD_DATA_DIR}/engine-version"
}

install_xray_binary() {
  local input_tag="${1:-latest}"
  local arch
  arch="$(get_arch)"
  if sbd_offline_mode_enabled; then
    if [[ -x "${SBD_BIN_DIR}/xray" ]]; then
      log_warn "$(msg "SBD_OFFLINE_MODE=true；使用本地已有 xray 二进制" "SBD_OFFLINE_MODE=true; using existing local xray binary")"
      return 0
    fi
    die "$(msg "SBD_OFFLINE_MODE=true，但未找到本地 xray 二进制" "SBD_OFFLINE_MODE=true but local xray binary not found")"
  fi
  local x_arch="64"
  [[ "$arch" == "arm64" ]] && x_arch="arm64-v8a"

  local tag
  if [[ "$input_tag" == "latest" ]]; then
    tag="$(fetch_latest_release_tag "XTLS/Xray-core")"
  else
    tag="$input_tag"
    [[ "$tag" == v* ]] || tag="v${tag}"
  fi
  [[ -n "$tag" && "$tag" != "null" ]] || die "$(msg "无法获取最新 xray 发布版本" "Unable to fetch latest xray release")"

  local filename="Xray-linux-${x_arch}.zip"
  local url="https://github.com/XTLS/Xray-core/releases/download/${tag}/${filename}"
  local cache_dir="${SBD_CACHE_DIR:-${SBD_INSTALL_DIR}/cache}"
  mkdir -p "$cache_dir"
  local archive="${cache_dir}/${filename}"
  local dgst="${cache_dir}/${filename}.dgst"

  log_info "$(msg "正在安装 xray ${tag}" "Installing xray ${tag}")"
  if download_file "$url" "$archive"; then
    download_file "https://github.com/XTLS/Xray-core/releases/download/${tag}/${filename}.dgst" "$dgst"
    verify_sha256_from_xray_dgst "$archive" "$dgst"
    if ! command -v unzip >/dev/null 2>&1; then
      apt-get install -y unzip >/dev/null
    fi
    unzip -o "$archive" xray -d "$cache_dir" >/dev/null
    install -m 0755 "${cache_dir}/xray" "${SBD_BIN_DIR}/xray"
    rm -f "${cache_dir}/xray" "$archive" "$dgst" 2>/dev/null || true
  else
    if [[ -x "${SBD_BIN_DIR}/xray" ]]; then
      log_warn "$(msg "下载 xray ${tag} 失败，复用本地已有二进制" "Failed to download xray ${tag}; reusing existing local binary")"
      return 0
    fi
    die "$(msg "无法下载 xray，且本地不存在可用二进制" "Unable to download xray and no local binary available")"
  fi

  echo "$tag" > "${SBD_DATA_DIR}/engine-version"
}

install_engine_binary() {
  local engine="$1"
  local tag="${2:-latest}"
  case "$engine" in
    sing-box) install_sing_box_binary "$tag" ;;
    xray) install_xray_binary "$tag" ;;
    *) die "$(msg "不支持的内核: $engine" "Unsupported engine: $engine")" ;;
  esac
}
