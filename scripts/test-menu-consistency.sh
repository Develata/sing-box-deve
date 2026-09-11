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

# Exercise the nested input flow: importing keeps routing, and choosing direct
# reaches set-route without clearing the saved node through set-egress.
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/menu_sections_view.sh"
msg() { printf '%s' "$1"; }
menu_title() { :; }
menu_status_header() { :; }
menu_pause() { :; }
menu_invalid() { echo '[FAIL] unexpected menu input' >&2; exit 1; }
calls=''
# shellcheck disable=SC2034
sbd_egress_prompt_link() { OUTBOUND_PROXY_LINK=test-node; OUTBOUND_PROXY_UDP_MODE=proxy; }
provider_set_egress() { calls+="egress:${1}:${6}:${7:-};"; }
provider_set_route() { calls+="route:$1;"; }
prompt_yes_no() { return 1; }
menu_egress <<< $'2\n1\n1\n2\n1\n1\n0' >/dev/null
[[ "$calls" == 'egress:direct:proxy:test-node;route:global-proxy;route:direct;' ]]
calls=''
menu_egress <<< $'2\n2\nhttp\n192.0.2.10\n8080\n\n\n\n0' >/dev/null
[[ "$calls" == 'egress:http:direct:;' ]]
calls=''
menu_egress <<< $'2\n3\n2\n0\n1\n0\n0' >/dev/null
[[ -z "$calls" ]]
printf '[OK] nested egress menus preserve route/node boundaries and cancellation\n'
