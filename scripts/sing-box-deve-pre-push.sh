#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

log() {
  printf '[sing-box-deve-pre-push] %s\n' "$*"
}

run() {
  log "$*"
  "$@"
}

run bash -n sing-box-deve.sh lib/*.sh providers/*.sh scripts/*.sh
run node --check web-generator/app.js
run node --check web-generator/schema.js
run bash scripts/test-module-size.sh

if command -v shellcheck >/dev/null 2>&1; then
  run shellcheck sing-box-deve.sh lib/*.sh providers/*.sh scripts/*.sh
elif command -v uvx >/dev/null 2>&1; then
  run uvx --from shellcheck-py shellcheck sing-box-deve.sh lib/*.sh providers/*.sh scripts/*.sh
else
  echo "[sing-box-deve-pre-push] shellcheck not found; install shellcheck or uvx before pushing" >&2
  exit 1
fi

run node -e "const fs=require('fs'); JSON.parse(fs.readFileSync('examples/serv00-accounts.json','utf8'));"
run bash scripts/test-clash-ruleset.sh
run bash scripts/test-version-compare.sh
run bash scripts/test-update-authority.sh
run bash scripts/test-firewall-records.sh
run bash scripts/test-web-schema-sync.sh
run bash scripts/test-cli-smoke.sh

checksum_before="$(mktemp)"
cp checksums.txt "$checksum_before"
log "regenerating checksums"
./scripts/update-checksums.sh
run sha256sum -c checksums.txt

if ! cmp -s "$checksum_before" checksums.txt; then
  echo "[sing-box-deve-pre-push] checksums.txt changed after regeneration; run ./scripts/update-checksums.sh and include the result" >&2
  diff -u "$checksum_before" checksums.txt >&2 || true
  rm -f "$checksum_before"
  exit 1
fi
rm -f "$checksum_before"

run git diff --check
log "all checks passed"
