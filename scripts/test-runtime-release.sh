#!/usr/bin/env bash
# shellcheck disable=SC2317
# shellcheck disable=SC1091,SC2034
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$PROJECT_ROOT/lib/load.sh"
release_test="$(mktemp -d)"
trap 'rm -rf "$release_test"' EXIT
SBD_INSTALL_DIR="$release_test/install with spaces"
SBD_CONFIG_DIR="$release_test/config"
SBD_STATE_DIR="$release_test/state"
SBD_HOST_STATE_DIR="$release_test/control"
SBD_LAUNCHER_PATH="$release_test/bin/sb"
mkdir -p "$SBD_CONFIG_DIR" "$release_test/source" "$release_test/cwd/sing-box-deve"
cp -a "$PROJECT_ROOT/lib" "$PROJECT_ROOT/providers" "$PROJECT_ROOT/rulesets" "$PROJECT_ROOT/scripts" "$release_test/source/"
cp "$PROJECT_ROOT/sing-box-deve.sh" "$PROJECT_ROOT/version" "$PROJECT_ROOT/LICENSE" "$release_test/source/"
fail() { echo "[FAIL] $*" >&2; exit 1; }
pack_release() {
  python3 "$PROJECT_ROOT/scripts/runtime-archive.py" pack "$release_test/source" "$release_test/runtime.tar.gz"
  release_sum="$(sha256sum "$release_test/runtime.tar.gz")"; release_sum="${release_sum%% *}"
}
printf 'v9.0.0\n' > "$release_test/source/version"
pack_release
first_sum="$release_sum"
cp "$release_test/runtime.tar.gz" "$release_test/first.tar.gz"
pack_release
cmp "$release_test/first.tar.gz" "$release_test/runtime.tar.gz" || fail 'archive is not reproducible'
printf 'script_root="%s"\n' "$release_test/source" > "$SBD_CONFIG_DIR/runtime.env"
sbd_with_mutation_lock sbd_release_migrate_legacy
legacy="$(readlink -f "$SBD_INSTALL_DIR/current")"
sbd_with_mutation_lock sbd_release_activate_archive "$release_test/runtime.tar.gz" "$release_sum"
first="$(readlink -f "$SBD_INSTALL_DIR/current")"
[[ "$(readlink -f "$SBD_INSTALL_DIR/previous")" == "$legacy" ]] || fail 'cold migration lost legacy generation'
[[ "$("$SBD_LAUNCHER_PATH" --print-version)" == v9.0.0 ]] || fail 'launcher did not resolve first release'
# Host cwd containing a different/newer checkout must not redirect installed sb.
printf '#!/usr/bin/env bash\necho WRONG-CHECKOUT\n' > "$release_test/cwd/sing-box-deve/sing-box-deve.sh"
chmod +x "$release_test/cwd/sing-box-deve/sing-box-deve.sh"
(cd "$release_test/cwd"; [[ "$("$SBD_LAUNCHER_PATH" --print-root)" == "$first" ]]) || fail 'launcher followed cwd'
printf 'v9.0.1\n' > "$release_test/source/version"
printf '#!/usr/bin/env bash\nnew_release_module() { :; }\n' > "$release_test/source/lib/new-release-module.sh"
pack_release
if sbd_with_mutation_lock sbd_release_activate_archive "$release_test/runtime.tar.gz" "$first_sum"; then fail 'digest mismatch accepted'; fi
[[ "$(readlink -f "$SBD_INSTALL_DIR/current")" == "$first" ]] || fail 'bad digest changed current'
sbd_with_mutation_lock sbd_release_activate_archive "$release_test/runtime.tar.gz" "$release_sum"
second="$(readlink -f "$SBD_INSTALL_DIR/current")"
[[ -f "$second/lib/new-release-module.sh" && ! -f "$first/lib/new-release-module.sh" ]] || fail 'new module release evolution failed'
[[ "$(readlink -f "$SBD_INSTALL_DIR/previous")" == "$first" ]] || fail 'previous generation pointer lost'
sbd_with_mutation_lock sbd_release_rollback
[[ "$("$SBD_LAUNCHER_PATH" --print-version)" == v9.0.0 ]] || fail 'release rollback failed'
# Simulate SIGKILL at the only version selector replacement boundary.
(
  original_atomic="$(declare -f sbd_atomic_symlink)"
  eval "${original_atomic/sbd_atomic_symlink/sbd_test_atomic}"
  sbd_atomic_symlink() {
    sbd_test_atomic "$@" || return 1
    [[ "$2" != "$SBD_INSTALL_DIR/current" ]] || kill -KILL "$BASHPID"
  }
  sbd_with_mutation_lock sbd_release_activate_archive "$release_test/runtime.tar.gz" "$release_sum"
) && fail 'injected kill did not execute'
[[ "$("$SBD_LAUNCHER_PATH" --print-version)" == v9.0.1 ]] || fail 'selector kill left mixed/unbootable runtime'
sbd_release_verify "$(readlink -f "$SBD_INSTALL_DIR/current")"
printf '[OK] runtime release, migration and interruption checks passed\n'
