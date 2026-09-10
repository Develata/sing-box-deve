#!/usr/bin/env bash
# shellcheck disable=SC2119
# shellcheck disable=SC1091,SC2034
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$PROJECT_ROOT/lib/load.sh"
authority_test="$(mktemp -d)"
trap 'rm -rf "$authority_test"' EXIT
SBD_CONFIG_DIR="$authority_test/config"
SBD_STATE_DIR="$authority_test/state"
SBD_INSTALL_DIR="$authority_test/install"
SBD_HOST_STATE_DIR="$authority_test/control"
SBD_LAUNCHER_PATH="$authority_test/bin/sb"
root_with_quotes="$authority_test/runtime \\ with \" quotes"
mkdir -p "$SBD_CONFIG_DIR" "$root_with_quotes/lib" "$authority_test/cwd/sing-box-deve/lib"
printf '#!/usr/bin/env bash\nprintf "runtime-ok\\n"\n' > "$root_with_quotes/sing-box-deve.sh"
printf '#!/usr/bin/env bash\nprintf "wrong-checkout\\n"\n' > "$authority_test/cwd/sing-box-deve/sing-box-deve.sh"
touch "$root_with_quotes/lib/common.sh" "$authority_test/cwd/sing-box-deve/lib/common.sh"
chmod +x "$root_with_quotes/sing-box-deve.sh" "$authority_test/cwd/sing-box-deve/sing-box-deve.sh"
sbd_write_env_kv script_root "$root_with_quotes" > "$SBD_CONFIG_DIR/runtime.env"
write_sb_launcher
[[ "$("$SBD_LAUNCHER_PATH" --print-root)" == "$root_with_quotes" ]]
(cd "$authority_test/cwd"; [[ "$("$SBD_LAUNCHER_PATH" help)" == runtime-ok ]])
# No installed runtime means fail; a cwd checkout is never silently adopted.
rm "$SBD_CONFIG_DIR/runtime.env"
if (cd "$authority_test/cwd"; "$SBD_LAUNCHER_PATH" help >/dev/null 2>&1); then
  echo '[FAIL] launcher silently adopted a cwd checkout' >&2; exit 1
fi
printf '[OK] launcher authority and quoted runtime path checks passed\n'
