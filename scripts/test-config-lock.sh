#!/usr/bin/env bash
# shellcheck disable=SC2034
set -euo pipefail
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$root_dir/lib/common_base.sh"
source "$root_dir/lib/providers_config_lock.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
SBD_STATE_DIR="$tmp_dir/state"
SBD_INSTALL_DIR="$tmp_dir/install"
SBD_LOCK_TIMEOUT=1
hold_lock() { touch "$tmp_dir/locked"; sleep 3; }
provider_cfg_with_lock hold_lock &
owner=$!
for ((i=0; i<100; i++)); do [[ ! -e "$tmp_dir/locked" ]] || break; sleep 0.02; done
[[ -e "$tmp_dir/locked" ]] || exit 1
if provider_cfg_with_lock touch "$tmp_dir/overlap"; then
  echo '[FAIL] concurrent mutation was allowed' >&2; exit 1
fi
[[ ! -e "$tmp_dir/overlap" ]]
wait "$owner"
provider_cfg_with_lock touch "$tmp_dir/after"
[[ -e "$tmp_dir/after" ]]
if provider_cfg_with_lock false; then exit 1; fi
provider_cfg_with_lock provider_cfg_with_lock touch "$tmp_dir/nested"
[[ -e "$tmp_dir/nested" ]]
echo '[OK] mutation serialization, failure propagation and nesting checks passed'
