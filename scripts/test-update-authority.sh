#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

export HOME="${TMP_DIR}/home"
mkdir -p "${HOME}/sing-box-deve/config"

PROJECT_ROOT="$ROOT_DIR"

# shellcheck source=lib/common_base.sh
source "${ROOT_DIR}/lib/common_base.sh"
# shellcheck source=lib/common_file_helpers.sh
source "${ROOT_DIR}/lib/common_file_helpers.sh"
# shellcheck source=lib/common_launcher.sh
source "${ROOT_DIR}/lib/common_launcher.sh"

SBD_INSTALL_DIR="${TMP_DIR}/install"

runtime_file="${HOME}/sing-box-deve/config/runtime.env"
cat > "$runtime_file" <<EOF
provider=vps
profile=lite
engine=sing-box
protocols=vless-reality
script_root=/opt/sing-box-deve/script
installed_at=2026-04-30T00:00:00Z
EOF

auth_root="$(sbd_choose_authoritative_script_root "$ROOT_DIR")"
[[ "$auth_root" == "$ROOT_DIR" ]] || {
  echo "[FAIL] expected checkout authority ${ROOT_DIR}, got ${auth_root}" >&2
  exit 1
}
sbd_update_runtime_script_root "$auth_root"
grep -qx "script_root=${ROOT_DIR}" "$runtime_file" || {
  echo "[FAIL] runtime.env did not switch to checkout root" >&2
  exit 1
}

ephemeral_root="${TMP_DIR}/src"
mkdir -p "$ephemeral_root"
tar -C "$ROOT_DIR" \
  --exclude=.git \
  --exclude=.codex \
  -cf - . | tar -C "$ephemeral_root" -xf -
chmod +x "${ephemeral_root}/sing-box-deve.sh"

PROJECT_ROOT="$ephemeral_root"
sbd_persist_script_root_if_needed "$PROJECT_ROOT"
expected_persist="${SBD_INSTALL_DIR}/script"
[[ "$PROJECT_ROOT" == "$expected_persist" ]] || {
  echo "[FAIL] expected persisted root ${expected_persist}, got ${PROJECT_ROOT}" >&2
  exit 1
}
[[ -x "${expected_persist}/sing-box-deve.sh" && -f "${expected_persist}/lib/common.sh" ]] || {
  echo "[FAIL] persisted script root is incomplete" >&2
  exit 1
}
grep -qx "script_root=${expected_persist}" "$runtime_file" || {
  echo "[FAIL] runtime.env did not switch to persisted temp root" >&2
  exit 1
}

launcher="${TMP_DIR}/sb"
write_sb_launcher "$launcher"
launcher_root="$(cd "$TMP_DIR" && "$launcher" --print-root)"
[[ "$launcher_root" == "$expected_persist" ]] || {
  echo "[FAIL] launcher root mismatch: expected ${expected_persist}, got ${launcher_root}" >&2
  exit 1
}
launcher_version="$(cd "$TMP_DIR" && "$launcher" --print-version)"
expected_version="$(tr -d '[:space:]' < "${expected_persist}/version")"
[[ "$launcher_version" == "$expected_version" ]] || {
  echo "[FAIL] launcher version mismatch: expected ${expected_version}, got ${launcher_version}" >&2
  exit 1
}
checkout_root="$(cd "$ROOT_DIR" && "$launcher" --print-root)"
[[ "$checkout_root" == "$ROOT_DIR" ]] || {
  echo "[FAIL] launcher did not prefer checkout cwd: expected ${ROOT_DIR}, got ${checkout_root}" >&2
  exit 1
}

echo "[OK] update authority checks passed"
