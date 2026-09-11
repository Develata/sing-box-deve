#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC2034
PROJECT_NAME="sing-box-deve"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

bootstrap_remote_tree() (
  local repo="${SBD_REPO_SLUG:-Develata/sing-box-deve}" tmp archive remote_root metadata actual
  local url="${SBD_RELEASE_ARCHIVE_URL:-}" expected="${SBD_RELEASE_SHA256:-}"
  command -v python3 >/dev/null || { echo "[ERROR] python3 is required for verified runtime bootstrap" >&2; exit 127; }
  [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || exit 2
  tmp="$(mktemp -d)" || exit 1
  trap 'rm -rf "$tmp"' EXIT
  archive="$tmp/runtime.tar.gz"
  if [[ -z "$url" ]]; then
    metadata="$tmp/release.json"
    curl -fsSL --connect-timeout 5 --max-time 20 --max-filesize 2097152 \
      "https://api.github.com/repos/$repo/releases/latest" -o "$metadata" || exit 1
    python3 - "$metadata" > "$tmp/asset" <<'PY_ASSET'
import json, sys
assets = [a for a in json.load(open(sys.argv[1]))['assets'] if a['name'] == 'sing-box-deve-runtime.tar.gz']
if len(assets) != 1 or not assets[0].get('digest', '').startswith('sha256:'):
    sys.exit('A published runtime archive with a SHA256 digest is required')
print(assets[0]['browser_download_url'])
print(assets[0]['digest'][7:])
PY_ASSET
    mapfile -t metadata < "$tmp/asset"
    url="${metadata[0]:-}"; expected="${metadata[1]:-}"
  fi
  [[ "$url" == https://* && "$expected" =~ ^[a-fA-F0-9]{64}$ ]] || { echo '[ERROR] Pinned runtime URL/SHA256 required' >&2; exit 1; }
  curl -fsSL --connect-timeout 10 --max-time 120 --max-filesize 67108864 "$url" -o "$archive" || exit 1
  actual="$(sha256sum "$archive")" || exit 1
  [[ "${actual%% *}" == "${expected,,}" ]] || { echo '[ERROR] Runtime archive SHA256 mismatch' >&2; exit 1; }
  remote_root="$tmp/runtime"
  mkdir "$remote_root" || exit 1
  # Before executing the checksum-pinned verifier, constrain extraction itself.
  python3 - "$archive" "$remote_root" <<'PY_EXTRACT'
from pathlib import Path, PurePosixPath
import shutil, sys, tarfile
root = Path(sys.argv[2]); seen = set(); size = 0
with tarfile.open(sys.argv[1], 'r|gz') as archive:
    for member in archive:
        name = member.name[len('sing-box-deve-runtime/') :]
        path = PurePosixPath(name)
        size += member.size
        if (not member.name.startswith('sing-box-deve-runtime/') or not member.isfile()
                or path.is_absolute() or '..' in path.parts or str(path) != name
                or name in seen or len(seen) >= 2048 or size > 67108864):
            sys.exit('Unsafe runtime archive')
        seen.add(name)
        output = root / name
        output.parent.mkdir(parents=True, exist_ok=True)
        with archive.extractfile(member) as source, output.open('xb') as destination:
            shutil.copyfileobj(source, destination)
        output.chmod(0o755 if name.endswith(('.sh', '.py')) else 0o644)
PY_EXTRACT
  python3 "$remote_root/scripts/runtime-archive.py" verify "$remote_root" || exit 1
  bash "$remote_root/sing-box-deve.sh" "$@"
)

if [[ ! -f "${PROJECT_ROOT}/lib/common.sh" ]]; then
  bootstrap_remote_tree "$@"
  exit $?
fi

source "${PROJECT_ROOT}/lib/load.sh"
sbd_git_source_guard || exit 1

if [[ "${1:-}" == --self-test ]]; then exit 0; fi

detect_privilege_level
init_i18n
main "$@"
