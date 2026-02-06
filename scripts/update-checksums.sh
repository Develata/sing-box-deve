#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_FILE="${ROOT_DIR}/checksums.txt"

files=(
  "sing-box-deve.sh"
  "version"
  "README.md"
  "CHANGELOG.md"
  "CONTRIBUTING.md"
  "LICENSE"
  "config.env.example"
  "lib/common.sh"
  "lib/protocols.sh"
  "lib/security.sh"
  "lib/providers.sh"
  "lib/output.sh"
  "docs/README.md"
  "docs/V1-SPEC.md"
  "docs/CONVENTIONS.md"
  "docs/ACCEPTANCE-MATRIX.md"
  "docs/Serv00.md"
  "docs/SAP.md"
  "docs/Docker.md"
  "examples/vps-lite.env"
  "examples/vps-full-argo.env"
  "examples/docker.env"
  "examples/settings.conf"
  "examples/serv00-accounts.json"
  "examples/sap-accounts.json"
  "web-generator/index.html"
  "scripts/acceptance-matrix.sh"
  "scripts/update-checksums.sh"
  ".github/workflows/main.yml"
  ".github/workflows/mainh.yml"
  ".github/workflows/ci.yml"
  "workers/_worker.js"
  "workers/workers_keep.js"
)

tmp="$(mktemp)"
for rel in "${files[@]}"; do
  sha256sum "${ROOT_DIR}/${rel}" | awk -v r="$rel" '{print $1 "  " r}' >> "$tmp"
done
mv "$tmp" "$OUT_FILE"
echo "Generated ${OUT_FILE}"
