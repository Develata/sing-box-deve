#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -d .git ]]; then
  echo "[ERROR] Not a Git checkout: $ROOT_DIR" >&2
  exit 1
fi

mkdir -p .git/hooks
cat > .git/hooks/pre-push <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${SBD_SKIP_PRE_PUSH:-}" == "1" ]]; then
  echo "[pre-push] SBD_SKIP_PRE_PUSH=1; skipping local CI" >&2
  exit 0
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"
exec bash scripts/sing-box-deve-pre-push.sh
HOOK
chmod +x .git/hooks/pre-push

echo "[OK] Installed pre-push hook: .git/hooks/pre-push"
