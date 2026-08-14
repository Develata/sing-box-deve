#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

before="$(mktemp)"
trap 'rm -f "$before"' EXIT INT TERM HUP
cp web-generator/schema.js "$before"
python3 scripts/generate-web-schema.py >/tmp/sbd-web-schema-sync.out
if ! cmp -s "$before" web-generator/schema.js; then
  echo "[FAIL] web-generator/schema.js is out of sync; run scripts/generate-web-schema.py" >&2
  diff -u "$before" web-generator/schema.js >&2 || true
  exit 1
fi

node --check web-generator/schema.js
node --check web-generator/app.js

echo "[OK] web schema sync checks passed"
