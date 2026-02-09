#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_FILE="${ROOT_DIR}/checksums.txt"

# Source the unified file manifest
# shellcheck source=lib/update_manifest.sh
source "${ROOT_DIR}/lib/update_manifest.sh"

tmp="$(mktemp)"
for rel in "${UPDATE_MANIFEST_FILES[@]}"; do
  if [[ ! -f "${ROOT_DIR}/${rel}" ]]; then
    echo "[ERROR] File not found: ${rel}" >&2
    rm -f "$tmp"
    exit 1
  fi
  sha256sum "${ROOT_DIR}/${rel}" | awk -v r="$rel" '{print $1 "  " r}' >> "$tmp"
done
mv "$tmp" "$OUT_FILE"
echo "Generated ${OUT_FILE} with ${#UPDATE_MANIFEST_FILES[@]} files"
