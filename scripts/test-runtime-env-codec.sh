#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="$root_dir"
source "${PROJECT_ROOT}/lib/load.sh"

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT INT TERM HUP
env_file="${tmp_dir}/runtime.env"

values=(
  'plain'
  'with space'
  'hash # value'
  'equals=a=b'
  'double " quote'
  "single ' quote"
  'backslash \\ value'
  'dollar $HOME $(no-exec)'
  'semicolon ; and `backtick`'
  '组合 Unicode 密码 🔒'
  'abc" xyz #123'
  '\\"# mixed'
)

: > "$env_file"
for i in "${!values[@]}"; do
  sbd_write_env_kv "codec_${i}" "${values[$i]}" >> "$env_file"
done
printf 'commented="keep # inside" # discard this\n' >> "$env_file"

commented=""
sbd_safe_load_env_file "$env_file"
for i in "${!values[@]}"; do
  printf -v codec_var 'codec_%s' "$i"
  actual="${!codec_var}"
  [[ "$actual" == "${values[$i]}" ]] || \
    die "round-trip mismatch at ${i}: expected=$(printf %q "${values[$i]}") actual=$(printf %q "$actual")"
done
[[ "$commented" == 'keep # inside' ]] || die "inline comment parsing failed"

printf '[OK] runtime.env codec round-trip checks passed\n'
