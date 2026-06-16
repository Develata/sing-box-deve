#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/sing-box-deve.sh"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

assert_success() {
  local name="$1"
  shift
  if ! "$@" >"${TMP_DIR}/${name}.out" 2>"${TMP_DIR}/${name}.err"; then
    echo "[FAIL] expected success: ${name}" >&2
    cat "${TMP_DIR}/${name}.out" >&2 || true
    cat "${TMP_DIR}/${name}.err" >&2 || true
    exit 1
  fi
}

assert_failure() {
  local name="$1"
  shift
  if "$@" >"${TMP_DIR}/${name}.out" 2>"${TMP_DIR}/${name}.err"; then
    echo "[FAIL] expected failure: ${name}" >&2
    cat "${TMP_DIR}/${name}.out" >&2 || true
    cat "${TMP_DIR}/${name}.err" >&2 || true
    exit 1
  fi
}

export HOME="${TMP_DIR}/home"
mkdir -p "$HOME"

remote_root="${TMP_DIR}/remote"
mkdir -p "$remote_root"
printf '%s\n' 'v9.9.9' > "${remote_root}/version"

assert_success help "$SCRIPT" help

assert_success version env SBD_UPDATE_BASE_URL="file://${remote_root}" "$SCRIPT" version
grep -q "Current script version" "${TMP_DIR}/version.out" || fail "version output missing local version"
grep -q "Remote latest version" "${TMP_DIR}/version.out" || fail "version output missing remote version"

assert_success dry-run env HOME="$HOME" "$SCRIPT" install --dry-run \
  --provider vps \
  --profile lite \
  --engine sing-box \
  --protocols vless-reality \
  --uuid 11111111-1111-4111-8111-111111111111 \
  --yes
[[ ! -e "${HOME}/sing-box-deve" ]] || fail "dry-run created persistent state under HOME"

assert_failure unknown-command "$SCRIPT" __definitely_unknown_command__

assert_failure integration-smoke-missing-value "${ROOT_DIR}/scripts/integration-smoke.sh" --script
grep -q "requires a value" "${TMP_DIR}/integration-smoke-missing-value.err" || fail "integration-smoke missing-value error is not explicit"

assert_failure sfw-missing-value "${ROOT_DIR}/scripts/sfw-package.sh" --tag
grep -q "requires a value" "${TMP_DIR}/sfw-missing-value.out" || fail "sfw missing-value error is not explicit"

assert_failure sfw-unknown-arg "${ROOT_DIR}/scripts/sfw-package.sh" --bogus
grep -q "Unknown argument" "${TMP_DIR}/sfw-unknown-arg.out" || fail "sfw unknown-argument error is not explicit"

echo "[OK] CLI smoke checks passed"
