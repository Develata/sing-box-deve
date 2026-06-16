#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python3 scripts/generate-web-schema.py >/tmp/sbd-web-schema-sync.out
if ! git diff --quiet -- web-generator/schema.js; then
  echo "[FAIL] web-generator/schema.js is out of sync; run scripts/generate-web-schema.py" >&2
  git diff -- web-generator/schema.js >&2
  exit 1
fi

node --check web-generator/schema.js
node --check web-generator/app.js

echo "[OK] web schema sync checks passed"
