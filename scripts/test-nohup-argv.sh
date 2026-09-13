#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034,SC2016
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$PROJECT_ROOT/lib/load.sh"
argv_test="$(mktemp -d)"
SBD_DATA_DIR="$argv_test/data"
SBD_RUNTIME_DIR="$argv_test/run"
SBD_INSTALL_DIR="$argv_test/install"
SBD_HOST_STATE_DIR="$argv_test/control"
SBD_INIT_SYSTEM="nohup"
cron_file="$argv_test/cron"
crontab() { case "$1" in -l) [[ ! -f "$cron_file" ]] || cat "$cron_file" ;; -) cat > "$cron_file" ;; esac; }
trap 'nohup_stop_service argv-test >/dev/null 2>&1 || true; rm -rf "$argv_test"' EXIT
args=('path with spaces/config.json' 'name=a=b' 'https://example.invalid:8443' '中文 参数' '' 'literal $HOME ; $(false)')
program='import json,sys,time; open(sys.argv[1], "w").write(json.dumps(sys.argv[2:],ensure_ascii=False)); time.sleep(60)'
nohup_start_service argv-test python3 -c "$program" "$argv_test/actual.json" "${args[@]}"
python3 - "$argv_test/actual.json" "${args[@]}" <<'PY'
import json, sys
assert json.load(open(sys.argv[1])) == sys.argv[2:]
PY
grep -q -- '--argv' "$cron_file"
nohup_stop_service argv-test
# Execute the cron entry with /bin/sh, matching cron's default shell.
sed 's/^@reboot //' "$cron_file" > "$argv_test/boot-command"
# Stop removed the registered entry; create it explicitly for the boot test.
nohup_register_crontab argv-test python3 -c "$program" "$argv_test/actual.json" "${args[@]}"
sed 's/^@reboot //' "$cron_file" > "$argv_test/boot-command"
timeout -k 2s 15s sh "$argv_test/boot-command"
python3 - "$argv_test/actual.json" "${args[@]}" <<'PY'
import json, sys
assert json.load(open(sys.argv[1])) == sys.argv[2:]
PY
nohup_stop_service argv-test
decoded=()
sbd_decode_command_argv '/bin/program --config "/path with spaces/配置.json" key=a:b' decoded
[[ "${decoded[2]}" == '/path with spaces/配置.json' && "${decoded[3]}" == key=a:b ]]
for bad in '/bin/program "unfinished' '/bin/program ; touch /tmp/no' '/bin/program $(touch /tmp/no)' '/bin/program `id`'; do
  if sbd_decode_command_argv "$bad" decoded; then echo '[FAIL] ambiguous legacy command accepted'; exit 1; fi
done
printf '[OK] nohup argv and cron round-trip, strict nonexecuting legacy decode\n'
