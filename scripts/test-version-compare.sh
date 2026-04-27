#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=lib/cli_commands_misc.sh
source "${ROOT_DIR}/lib/cli_commands_misc.sh"

assert_lt() {
  local left="$1" right="$2"
  if ! version_lt "$left" "$right"; then
    echo "[FAIL] expected ${left} < ${right}" >&2
    exit 1
  fi
}

assert_not_lt() {
  local left="$1" right="$2"
  if version_lt "$left" "$right"; then
    echo "[FAIL] expected ${left} >= ${right}" >&2
    exit 1
  fi
}

assert_eq() {
  local left="$1" right="$2"
  if ! version_eq "$left" "$right"; then
    echo "[FAIL] expected ${left} == ${right}" >&2
    exit 1
  fi
}

assert_lt "1.0.0" "1.0.1"
assert_lt "1.0.9" "1.0.10"
assert_lt "1.9.9" "1.10.0"
assert_lt "v1.0.0-dev.6" "1.0.1"
assert_not_lt "1.0.1" "v1.0.0-dev.6"
assert_not_lt "1.0.10" "1.0.9"
assert_eq "v1.0.1" "1.0.1"
assert_eq "1.0" "1.0.0"

echo "[OK] version comparison checks passed"
