#!/usr/bin/env bash

# Also embedded verbatim in the installed launcher: validation must not depend
# on code in the mutable checkout that is about to be validated.
sbd_git_source_verify() {
  python3 - "$@" <<'PY'
import hashlib
import os
from pathlib import Path, PurePosixPath
import re
import signal
import stat
import subprocess
import sys

try:
    def timed_out(_signum, _frame):
        raise TimeoutError('Git source validation exceeded 30 seconds')
    signal.signal(signal.SIGALRM, timed_out)
    signal.alarm(30)
    root = Path(sys.argv[1])
    owner = int(sys.argv[2])
    if not root.is_absolute() or root.resolve(strict=True) != root:
        raise ValueError('Git source must be a fixed physical absolute directory')
    if any(c in str(root) for c in '\n\r\t'):
        raise ValueError('Git source path contains control characters')
    if root.stat().st_uid != owner:
        raise ValueError('Git source directory owner changed')

    checked = set()
    def secure(path, regular=False):
        if path not in checked:
            info = path.lstat()
            if (stat.S_ISLNK(info.st_mode) or info.st_uid not in {0, owner}
                    or info.st_mode & 0o022):
                raise ValueError(f'Unsafe Git source ownership/permissions: {path}')
            checked.add(path)
        if regular and not stat.S_ISREG(path.lstat().st_mode):
            raise ValueError(f'Git source is not a regular file: {path}')
        if path != path.parent:
            secure(path.parent)

    secure(root)
    def git(*args):
        env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
        env['GIT_OPTIONAL_LOCKS'] = '0'
        return subprocess.check_output(
            ['git', '-c', f'safe.directory={root}', '-c', 'core.fsmonitor=false',
             '-C', str(root), *args], env=env, text=True, stderr=subprocess.DEVNULL,
            timeout=10).strip()

    if Path(git('rev-parse', '--show-toplevel')).resolve() != root:
        raise ValueError('Binding requires the Git worktree root')
    head = git('rev-parse', '--verify', 'HEAD')
    secure(root / 'checksums.txt', True)
    sums_data = (root / 'checksums.txt').read_bytes()
    if len(sums_data) > 1024 * 1024:
        raise ValueError('Source checksum inventory is too large')
    sums = {}
    for line in sums_data.decode().splitlines():
        checksum, name = line.split('  ', 1)
        path = PurePosixPath(name)
        if (not re.fullmatch('[a-f0-9]{64}', checksum) or name in sums
                or path.is_absolute() or str(path) != name or '..' in path.parts
                or '\\' in name or any(c.isspace() for c in name)):
            raise ValueError('Invalid source checksum inventory')
        sums[name] = checksum
    required = {'sing-box-deve.sh', 'version', 'lib/load.sh', 'lib/common.sh',
                'lib/common_git_source.sh', 'lib/common_source_binding.sh',
                'lib/update_manifest.sh', 'scripts/runtime-archive.py',
                'scripts/nohup-run.sh', 'scripts/bounded-log.py', 'scripts/egress-link.py'}
    if not required <= sums.keys() or len(sums) > 2048:
        raise ValueError('Incomplete or unsupported Git source inventory')
    total = 0
    for name, checksum in sums.items():
        path = root / name
        secure(path, True)
        total += path.stat().st_size
        if total > 64 * 1024 * 1024:
            raise ValueError('Source inventory exceeds size limit')
        if hashlib.sha256(path.read_bytes()).hexdigest() != checksum:
            raise ValueError(f'Git source checksum mismatch: {name}')
    for directory in ('lib', 'providers', 'rulesets'):
        for path in (root / directory).rglob('*'):
            secure(path)
            if path.is_file() and path.relative_to(root).as_posix() not in sums:
                raise ValueError(f'Unlisted runtime source file: {path}')
    version = (root / 'version').read_text().strip()
    if not re.fullmatch(r'v?[0-9]+\.[0-9]+\.[0-9]+([-+][A-Za-z0-9.-]+)?', version):
        raise ValueError('Invalid Git source version')
    if not os.access(root / 'sing-box-deve.sh', os.X_OK):
        raise ValueError('Git source entrypoint is not executable')
    dirty = bool(git('status', '--porcelain', '--untracked-files=no'))
    if head != git('rev-parse', '--verify', 'HEAD') or sums_data != (root / 'checksums.txt').read_bytes():
        raise ValueError('Git source changed during validation; exit menus and retry')
    print(f'{head}:{hashlib.sha256(sums_data).hexdigest()}:{"modified" if dirty else "clean"}')
except (OSError, ValueError, IndexError, subprocess.SubprocessError) as error:
    print(f'[ERROR] {error}', file=sys.stderr)
    sys.exit(1)
PY
}

sbd_git_source_validate() {
  local root="$1" owner="$2" before after file deadline=$((SECONDS + 60))
  before="$(sbd_git_source_verify "$root" "$owner")" || return 1
  while read -r _ file; do
    (( SECONDS < deadline )) || { log_error "Git source validation deadline exceeded"; return 1; }
    [[ "$file" != *.sh ]] || sbd_run_deadline 10 bash -n "$root/$file" || return 1
  done < "$root/checksums.txt"
  sbd_run_deadline 30 env -u SBD_GIT_SOURCE_STAMP -u SBD_GIT_SOURCE_UID bash "$root/sing-box-deve.sh" --self-test || return 1
  after="$(sbd_git_source_verify "$root" "$owner")" || return 1
  [[ "$before" == "$after" ]] || { log_error "Git source changed during validation"; return 1; }
}

sbd_git_source_guard() {
  [[ -n "${SBD_GIT_SOURCE_STAMP:-}" ]] || return 0
  local now
  now="$(sbd_git_source_verify "$PROJECT_ROOT" "${SBD_GIT_SOURCE_UID:?}")" || return 1
  [[ "$now" == "$SBD_GIT_SOURCE_STAMP" ]] || {
    log_error "$(msg "源码已变化，请退出旧菜单后重新运行 sb；不要并发执行 git pull 和管理命令。" "Source changed; exit this menu and run sb again. Do not run git pull concurrently with management commands.")"
    return 1
  }
}
