#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python3 - <<'PY'
from pathlib import Path
import re
import sys

failed = False
for path in sorted(Path('lib').glob('menu*.sh')):
    text = path.read_text()
    for match in re.finditer(r'^(menu_[A-Za-z0-9_]+)\(\) \{', text, re.M):
        name = match.group(1)
        start = match.end()
        end = text.find('\n}\n', start)
        body = text[start:end if end != -1 else len(text)]
        displayed = sorted(set(re.findall(r'echo "([0-9]+)\)', body)), key=int)
        handled = sorted(set(re.findall(r'^\s*([0-9]+)\)', body, re.M)), key=int)
        missing = [item for item in displayed if item not in handled]
        extra = [item for item in handled if item not in displayed and item != '0']
        if missing or extra:
            failed = True
            print(f'[FAIL] {path}:{name}: displayed={displayed} handled={handled} missing={missing} extra={extra}', file=sys.stderr)

if failed:
    sys.exit(1)
print('[OK] menu option consistency checks passed')
PY
