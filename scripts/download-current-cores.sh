#!/usr/bin/env bash
set -euo pipefail

download_current_core_asset() (
  local url="$1" target="$2" digest="$3" cache="$4" attempt status=1 staged=""
  [[ "$digest" =~ ^[a-fA-F0-9]{64}$ ]] || return 2
  trap '[[ -z "$staged" ]] || rm -f -- "$staged"' EXIT
  if [[ -f "$cache" && ! -L "$cache" ]]; then
    if printf '%s  %s\n' "$digest" "$cache" | sha256sum -c --status; then
      cp -- "$cache" "$target" || return 1
      printf '%s  %s\n' "$digest" "$target" | sha256sum -c -
      return "$?"
    fi
    printf '[WARN] Core cache digest changed; fetching the selected stable asset\n' >&2
  fi
  # Only resume bytes downloaded by this invocation, never an older asset left
  # in a reused output directory (Xray asset filenames do not carry a version).
  : > "$target" || return 1
  for attempt in 1 2 3; do
    # Release asset URLs stay fixed across these attempts; verification below
    # rejects a changed asset or an inconsistent partial/range response.
    if curl -fsSL --connect-timeout 10 --max-time 300 --continue-at - "$url" -o "$target"; then
      status=0; break
    else status=$?; fi
    case "$status" in 6|7|18|28|52|55|56) ;; *) return "$status" ;; esac
    (( attempt == 3 )) || printf '[WARN] Interrupted core download (%s); resuming attempt %s/3\n' "$status" "$((attempt + 1))" >&2
  done
  (( status == 0 )) || return "$status"
  printf '%s  %s\n' "$digest" "$target" | sha256sum -c - || return 1
  mkdir -p -- "$(dirname "$cache")" || return 1
  staged="$(mktemp "${cache}.XXXXXX")" || return 1
  cp -- "$target" "$staged" && mv -f -- "$staged" "$cache"
)

# Tests source only the transport helper; the normal CLI always selects latest.
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

out_dir="${1:-}"
[[ -n "$out_dir" ]] || { echo "Usage: $0 OUTPUT_DIR" >&2; exit 2; }
mkdir -p "$out_dir"
script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
core_cache="${SBD_TEST_CORE_CACHE_DIR:-$script_root/.tools/ci-cores}"

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
download_current_core_asset "$sb_url" "${out_dir}/${sb_asset}" "${sb_digest#sha256:}" "$core_cache/sing-box-${sb_arch}.tar.gz"
tar -xzf "${out_dir}/${sb_asset}" -C "$out_dir"
sb_bin="${out_dir}/sing-box-${sb_version}-linux-${sb_arch}/sing-box"

xr_release="${out_dir}/xray-release.json"
curl -fsSL --connect-timeout 5 --max-time 20 https://api.github.com/repos/XTLS/Xray-core/releases/latest -o "$xr_release"
xr_asset="Xray-linux-${xr_arch}.zip"
xr_url="$(jq -r --arg name "$xr_asset" '.assets[] | select(.name==$name) | .browser_download_url' "$xr_release")"
xr_dgst_url="$(jq -r --arg name "${xr_asset}.dgst" '.assets[] | select(.name==$name) | .browser_download_url' "$xr_release")"
[[ -n "$xr_url" && -n "$xr_dgst_url" ]] || { echo "Missing Xray asset or digest" >&2; exit 1; }
curl -fsSL --connect-timeout 5 --max-time 20 "$xr_dgst_url" -o "${out_dir}/${xr_asset}.dgst"
xr_digest="$(awk -F'= *' '/SHA2?-?256/{print $2; exit}' "${out_dir}/${xr_asset}.dgst")"
[[ -n "$xr_digest" ]] || { echo "Unable to parse Xray digest" >&2; exit 1; }
download_current_core_asset "$xr_url" "${out_dir}/${xr_asset}" "$xr_digest" "$core_cache/xray-${xr_arch}.zip"
unzip -oq "${out_dir}/${xr_asset}" xray geoip.dat geosite.dat -d "$out_dir"
xr_bin="${out_dir}/xray"

chmod 0755 "$sb_bin" "$xr_bin"
{
  printf 'SBD_TEST_SINGBOX_BIN=%s\n' "$sb_bin"
  printf 'SBD_TEST_XRAY_BIN=%s\n' "$xr_bin"
} > "${out_dir}/core-test.env"

"$sb_bin" version | head -n 2
"$xr_bin" version | head -n 1
