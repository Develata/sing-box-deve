#!/usr/bin/env bash
set -euo pipefail

out_dir="${1:-}"
[[ -n "$out_dir" ]] || { echo "Usage: $0 OUTPUT_DIR" >&2; exit 2; }
mkdir -p "$out_dir"

case "$(uname -m)" in
  x86_64|amd64) sb_arch=amd64; xr_arch=64 ;;
  aarch64|arm64) sb_arch=arm64; xr_arch=arm64-v8a ;;
  *) echo "Unsupported test architecture: $(uname -m)" >&2; exit 1 ;;
esac

sb_release="${out_dir}/sing-box-release.json"
curl -fsSL --connect-timeout 5 --max-time 20 https://api.github.com/repos/SagerNet/sing-box/releases/latest -o "$sb_release"
sb_tag="$(jq -r .tag_name "$sb_release")"
sb_version="${sb_tag#v}"
sb_asset="sing-box-${sb_version}-linux-${sb_arch}.tar.gz"
sb_url="$(jq -r --arg name "$sb_asset" '.assets[] | select(.name==$name) | .browser_download_url' "$sb_release")"
sb_digest="$(jq -r --arg name "$sb_asset" '.assets[] | select(.name==$name) | .digest // empty' "$sb_release")"
[[ -n "$sb_url" && "$sb_digest" == sha256:* ]] || { echo "Missing sing-box asset or digest" >&2; exit 1; }
curl -fsSL --connect-timeout 10 --max-time 300 "$sb_url" -o "${out_dir}/${sb_asset}"
printf '%s  %s\n' "${sb_digest#sha256:}" "${out_dir}/${sb_asset}" | sha256sum -c -
tar -xzf "${out_dir}/${sb_asset}" -C "$out_dir"
sb_bin="${out_dir}/sing-box-${sb_version}-linux-${sb_arch}/sing-box"

xr_release="${out_dir}/xray-release.json"
curl -fsSL --connect-timeout 5 --max-time 20 https://api.github.com/repos/XTLS/Xray-core/releases/latest -o "$xr_release"
xr_asset="Xray-linux-${xr_arch}.zip"
xr_url="$(jq -r --arg name "$xr_asset" '.assets[] | select(.name==$name) | .browser_download_url' "$xr_release")"
xr_dgst_url="$(jq -r --arg name "${xr_asset}.dgst" '.assets[] | select(.name==$name) | .browser_download_url' "$xr_release")"
[[ -n "$xr_url" && -n "$xr_dgst_url" ]] || { echo "Missing Xray asset or digest" >&2; exit 1; }
curl -fsSL --connect-timeout 10 --max-time 300 "$xr_url" -o "${out_dir}/${xr_asset}"
curl -fsSL --connect-timeout 5 --max-time 20 "$xr_dgst_url" -o "${out_dir}/${xr_asset}.dgst"
xr_digest="$(awk -F'= *' '/SHA2?-?256/{print $2; exit}' "${out_dir}/${xr_asset}.dgst")"
[[ -n "$xr_digest" ]] || { echo "Unable to parse Xray digest" >&2; exit 1; }
printf '%s  %s\n' "$xr_digest" "${out_dir}/${xr_asset}" | sha256sum -c -
unzip -oq "${out_dir}/${xr_asset}" xray -d "$out_dir"
xr_bin="${out_dir}/xray"

chmod 0755 "$sb_bin" "$xr_bin"
{
  printf 'SBD_TEST_SINGBOX_BIN=%s\n' "$sb_bin"
  printf 'SBD_TEST_XRAY_BIN=%s\n' "$xr_bin"
} > "${out_dir}/core-test.env"

"$sb_bin" version | head -n 2
"$xr_bin" version | head -n 1
