#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAX_LINES="${SBD_MAX_MODULE_LINES:-600}"
[[ "$MAX_LINES" =~ ^[1-9][0-9]*$ ]] || MAX_LINES=600

cd "$ROOT_DIR"

for f in sing-box-deve.sh lib/*.sh providers/*.sh scripts/*.sh; do
  lines="$(wc -l < "$f")"
  if (( lines > MAX_LINES )); then
    echo "[WARN] Maintenance reminder (${lines} > ${MAX_LINES} lines): ${f}; review cohesion, not length alone"
  fi
done

exit 0
