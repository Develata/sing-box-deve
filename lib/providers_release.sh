#!/usr/bin/env bash

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
  local arch
  arch="$(get_arch)"
  local tag
  tag="$(fetch_latest_release_tag "SagerNet/sing-box")"
  [[ -n "$tag" && "$tag" != "null" ]] || die "Unable to fetch latest sing-box release"

  local version="${tag#v}"
  local filename="sing-box-${version}-linux-${arch}.tar.gz"
  local url digest expected
  url="$(fetch_release_asset_url "SagerNet/sing-box" "$tag" "$filename")"
  digest="$(fetch_release_asset_digest "SagerNet/sing-box" "$tag" "$filename")"
  [[ -n "$url" ]] || die "Unable to locate sing-box asset: ${filename}"
  expected=""
  if [[ "$digest" == sha256:* ]]; then
    expected="${digest#sha256:}"
  fi
  local archive="${SBD_RUNTIME_DIR}/${filename}"
  local sums_file="${SBD_RUNTIME_DIR}/sing-box-${version}-checksums.txt"

  log_info "Installing sing-box ${tag}"
  download_file "$url" "$archive"
  if [[ -n "$expected" ]]; then
    verify_sha256_expected "$archive" "$expected"
  else
    log_warn "Release digest metadata missing; fallback to checksums file"
    download_file "https://github.com/SagerNet/sing-box/releases/download/${tag}/sing-box-${version}-checksums.txt" "$sums_file"
    verify_sha256_from_checksums_file "$archive" "$sums_file"
  fi
  tar -xzf "$archive" -C "$SBD_RUNTIME_DIR"
  install -m 0755 "${SBD_RUNTIME_DIR}/sing-box-${version}-linux-${arch}/sing-box" "${SBD_BIN_DIR}/sing-box"

  echo "$tag" > "${SBD_DATA_DIR}/engine-version"
}

install_xray_binary() {
  local arch
  arch="$(get_arch)"
  local x_arch="64"
  [[ "$arch" == "arm64" ]] && x_arch="arm64-v8a"

  local tag
  tag="$(fetch_latest_release_tag "XTLS/Xray-core")"
  [[ -n "$tag" && "$tag" != "null" ]] || die "Unable to fetch latest xray release"

  local filename="Xray-linux-${x_arch}.zip"
  local url="https://github.com/XTLS/Xray-core/releases/download/${tag}/${filename}"
  local archive="${SBD_RUNTIME_DIR}/${filename}"
  local dgst="${SBD_RUNTIME_DIR}/${filename}.dgst"

  log_info "Installing xray ${tag}"
  download_file "$url" "$archive"
  download_file "https://github.com/XTLS/Xray-core/releases/download/${tag}/${filename}.dgst" "$dgst"
  verify_sha256_from_xray_dgst "$archive" "$dgst"
  if ! command -v unzip >/dev/null 2>&1; then
    apt-get install -y unzip >/dev/null
  fi
  unzip -o "$archive" xray -d "$SBD_RUNTIME_DIR" >/dev/null
  install -m 0755 "${SBD_RUNTIME_DIR}/xray" "${SBD_BIN_DIR}/xray"

  echo "$tag" > "${SBD_DATA_DIR}/engine-version"
}

install_engine_binary() {
  local engine="$1"
  case "$engine" in
    sing-box) install_sing_box_binary ;;
    xray) install_xray_binary ;;
    *) die "Unsupported engine: $engine" ;;
  esac
}
