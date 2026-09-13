#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

stage="${1:-all}"
if (( $# > 1 )) || [[ "$stage" != all && "$stage" != lint && "$stage" != regression ]]; then
  echo 'Usage: bash scripts/sing-box-deve-pre-push.sh [all|lint|regression]' >&2
  exit 2
fi

log() {
  printf '[sing-box-deve-pre-push] %s\n' "$*"
}

run() {
  local started=$SECONDS status=0
  log "$*"
  [[ "${GITHUB_ACTIONS:-}" != true ]] || printf '::group::%s\n' "$*"
  "$@" || status=$?
  log "finished in $((SECONDS - started))s (exit $status)"
  [[ "${GITHUB_ACTIONS:-}" != true ]] || printf '::endgroup::\n'
  return "$status"
}

if [[ "$stage" == all || "$stage" == lint ]]; then
  for shell_file in sing-box-deve.sh lib/*.sh providers/*.sh scripts/*.sh; do bash -n "$shell_file"; done
  log "all shell files parsed"
  run node --check web-generator/app.js
  run node --check web-generator/schema.js
  run bash scripts/test-module-size.sh

  # Keep rule versions identical locally and in CI; do not silently use an old
  # distro package or download a floating uvx tool during a Git hook.
  required_shellcheck="$(sed -nE 's/^shellcheck-py==([0-9]+\.[0-9]+\.[0-9]+)(\.[0-9]+)?$/\1/p' scripts/requirements-ci.txt)"
  installed_shellcheck="$(shellcheck --version 2>/dev/null | sed -n 's/^version: //p')" || installed_shellcheck=missing
  if [[ -z "$required_shellcheck" || "$installed_shellcheck" != "$required_shellcheck" ]]; then
    log "ShellCheck $required_shellcheck required, found $installed_shellcheck; install scripts/requirements-ci.txt in a venv and activate it"
    exit 1
  fi
  run shellcheck sing-box-deve.sh lib/*.sh providers/*.sh scripts/*.sh
  run python3 scripts/test-ci-config.py
  run python3 scripts/test-source-graph-checker.py
  run bash scripts/test-source-graph.sh
fi

if [[ "$stage" == all || "$stage" == regression ]]; then
  run node -e "const fs=require('fs'); JSON.parse(fs.readFileSync('examples/serv00-accounts.json','utf8'));"
  run bash scripts/test-clash-ruleset.sh
  run bash scripts/test-version-compare.sh
  run bash scripts/test-update-authority.sh
  run bash scripts/test-firewall-records.sh
  run bash scripts/test-web-schema-sync.sh
  run bash scripts/test-menu-consistency.sh
  run bash scripts/test-cli-smoke.sh
  run bash scripts/test-egress-udp.sh
  run python3 scripts/test-egress-link.py
  run bash scripts/test-egress-protocols.sh
  run bash scripts/test-retired-protocols.sh
  run bash scripts/test-client-artifacts.sh
  run bash scripts/test-runtime-env-codec.sh
  run bash scripts/test-config-lock.sh
  run bash scripts/test-argo-token-file.sh
  run bash scripts/test-service-restart.sh
  run bash scripts/test-core-update-transaction.sh
  run bash scripts/test-web-front-smoke.sh
  run bash scripts/test-reliability.sh
  run bash scripts/test-review-recovery.sh
  run bash scripts/test-review-fixes.sh
  run bash scripts/test-firewall-failures.sh
  run node scripts/test-serv00-app.cjs
  run node scripts/test-web-generator.cjs
  run bash scripts/test-install-recovery.sh
  run bash scripts/test-io-deadlines.sh
  run bash scripts/test-package-recovery.sh
  run bash scripts/test-nohup-argv.sh
  run bash scripts/test-uninstall-transaction.sh
  run python3 scripts/test-runtime-archive.py
  run python3 scripts/test-release-receipt.py
  run bash scripts/test-runtime-release.sh
  run bash scripts/test-git-source.sh
  run python3 scripts/test-bounded-log.py
  run python3 scripts/test-core-download.py
  run bash scripts/test-current-core-suite.sh
fi

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
log "$stage checks passed"
