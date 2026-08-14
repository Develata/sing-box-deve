#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${root_dir}/lib/common_base.sh"
source "${root_dir}/lib/providers_config_lock.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT INT TERM HUP
SBD_STATE_DIR="${tmp_dir}/state"
SBD_CFG_LOCK_FILE="${SBD_STATE_DIR}/cfg.lock"
SBD_FORCE_MKDIR_LOCK=true
mkdir -p "${SBD_CFG_LOCK_FILE}.d"
printf '99999999\n' > "${SBD_CFG_LOCK_FILE}.d/pid"

marker="${tmp_dir}/ran"
provider_cfg_with_lock touch "$marker"
[[ -f "$marker" ]] || die "fallback lock did not run protected command"
[[ ! -e "${SBD_CFG_LOCK_FILE}.d" ]] || die "fallback lock was not cleaned"

if provider_cfg_with_lock false; then
  die "protected command failure was swallowed"
fi
[[ ! -e "${SBD_CFG_LOCK_FILE}.d" ]] || die "failed command left stale lock"

printf '[OK] fallback config lock checks passed\n'
