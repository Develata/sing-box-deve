#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAX_LINES="${SBD_MAX_MODULE_LINES:-400}"
failed=0

cd "$ROOT_DIR"

for f in sing-box-deve.sh lib/*.sh providers/*.sh scripts/*.sh; do
  lines="$(wc -l < "$f")"
  if (( lines > MAX_LINES )); then
    echo "File too long (${lines} > ${MAX_LINES}): ${f}"
    failed=1
  fi
done

exit "$failed"
