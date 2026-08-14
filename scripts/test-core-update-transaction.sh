#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${root_dir}/lib/common_base.sh"
source "${root_dir}/lib/common_file_helpers.sh"
source "${root_dir}/lib/providers_core_update.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT INT TERM HUP
SBD_STATE_DIR="${tmp_dir}/state"
SBD_CONFIG_DIR="${tmp_dir}/config"
SBD_BIN_DIR="${tmp_dir}/bin"
SBD_DATA_DIR="${tmp_dir}/data"
mkdir -p "$SBD_STATE_DIR" "$SBD_CONFIG_DIR" "$SBD_BIN_DIR" "$SBD_DATA_DIR"
printf 'runtime\n' > "${SBD_CONFIG_DIR}/runtime.env"

ensure_root() { return 0; }
provider_cfg_load_runtime_exports() { engine=sing-box; protocols=vless-reality; }
validate_feature_modes() { return 0; }
sbd_service_main_pid() { printf '100\n'; }
safe_service_restart() { return 0; }
provider_panel() { return 0; }
provider_restart() { return 0; }

provider_core_candidate_install() {
  local target_engine="$1" candidate_root="$2"
  mkdir -p "${candidate_root}/bin" "${candidate_root}/data"
  printf 'new-binary\n' > "${candidate_root}/bin/${target_engine}"
  chmod 0755 "${candidate_root}/bin/${target_engine}"
  printf 'v-new\n' > "${candidate_root}/data/engine-version"
}

candidate_mode="success"
provider_core_candidate_build() {
  local target_engine="$1" protocols_csv="$2" candidate_root="$3"
  [[ "$target_engine" == "sing-box" && "$protocols_csv" == "vless-reality" ]] || return 1
  [[ "$candidate_mode" == "success" ]] || return 1
  mkdir -p "${candidate_root}/config"
  printf 'new-config\n' > "${candidate_root}/config/config.json"
}

health_calls=0
health_mode="success"
provider_core_health_check() {
  health_calls=$((health_calls + 1))
  if [[ "$health_mode" == "fail-first" && "$health_calls" -eq 1 ]]; then
    return 1
  fi
  return 0
}

seed_old_state() {
  printf 'old-binary\n' > "${SBD_BIN_DIR}/sing-box"
  chmod 0755 "${SBD_BIN_DIR}/sing-box"
  printf 'old-config\n' > "${SBD_CONFIG_DIR}/config.json"
  printf 'v-old\n' > "${SBD_DATA_DIR}/engine-version"
}

seed_old_state
candidate_mode="failure"
if (provider_update >/dev/null 2>&1); then
  die "candidate validation failure was reported as success"
fi
[[ "$(<"${SBD_BIN_DIR}/sing-box")" == "old-binary" ]] || die "binary not restored after candidate failure"
[[ "$(<"${SBD_CONFIG_DIR}/config.json")" == "old-config" ]] || die "config not restored after candidate failure"

seed_old_state
candidate_mode="success"
health_mode="fail-first"
health_calls=0
if (provider_update >/dev/null 2>&1); then
  die "runtime health failure was reported as success"
fi
[[ "$(<"${SBD_BIN_DIR}/sing-box")" == "old-binary" ]] || die "binary not restored after health failure"
[[ "$(<"${SBD_CONFIG_DIR}/config.json")" == "old-config" ]] || die "config not restored after health failure"

seed_old_state
health_mode="success"
health_calls=0
provider_update >/dev/null
[[ "$(<"${SBD_BIN_DIR}/sing-box")" == "new-binary" ]] || die "new binary was not committed"
[[ "$(<"${SBD_CONFIG_DIR}/config.json")" == "new-config" ]] || die "candidate config was not committed"

printf '[OK] core update transaction checks passed\n'
