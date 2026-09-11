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
# README manual recovery: the candidate updater installs a local, digest-pinned
# archive through the regular transaction, accepting the exact legacy fw unit.
(
  manual="$release_test/manual recovery"
  SBD_INSTALL_DIR="$manual/install"
  SBD_CONFIG_DIR="$manual/config"
  SBD_STATE_DIR="$manual/state"
  SBD_HOST_STATE_DIR="$manual/control"
  SBD_RUNTIME_DIR="$manual/run"
  SBD_BIN_DIR="$SBD_INSTALL_DIR/bin"
  SBD_DATA_DIR="$SBD_INSTALL_DIR/data"
  SBD_RULES_FILE="$SBD_STATE_DIR/firewall-rules.db"
  SBD_LAUNCHER_PATH="$manual/sb"
  SBD_SERVICE_FILE="$manual/services/core"
  SBD_ARGO_SERVICE_FILE="$manual/services/argo"
  SBD_FW_REPLAY_SERVICE_FILE="$manual/services/firewall"
  SBD_WARP_SOCKS_SERVICE_FILE="$manual/services/warp"
  mkdir -p "$SBD_CONFIG_DIR" "$SBD_BIN_DIR" "$SBD_DATA_DIR" "$manual/services"
  sbd_write_env_kv script_root "$release_test/source" > "$SBD_CONFIG_DIR/runtime.env"
  # Script-only migration must remain available for a retired deployment.
  printf 'provider="vps"\nprofile="full"\nengine="sing-box"\nprotocols="vless-reality,tuic"\n' >> "$SBD_CONFIG_DIR/runtime.env"
  printf 'is_sbd_project_root() { :; }\n# /etc/sing-box-deve/runtime.env\n' > "$SBD_LAUNCHER_PATH"
  cat > "$SBD_FW_REPLAY_SERVICE_FILE" <<EOF
[Unit]
Description=sing-box-deve firewall replay
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$SBD_LAUNCHER_PATH fw replay

[Install]
WantedBy=multi-user.target
EOF
  printf 'existing core binary\n' > "$SBD_BIN_DIR/sing-box"
  printf '{"existing":"core configuration"}\n' > "$SBD_CONFIG_DIR/config.json"
  printf 'existing identity\n' > "$SBD_DATA_DIR/uuid"
  sha256sum "$SBD_BIN_DIR/sing-box" "$SBD_CONFIG_DIR/config.json" "$SBD_DATA_DIR/uuid" "$SBD_FW_REPLAY_SERVICE_FILE" > "$manual/preserved.sha256"
  sbd_service_probe() { printf 'active enabled\n'; }
  sbd_service_op() { fail 'manual script update invoked a service operation'; }
  provider_restart() { fail 'manual script update restarted a core'; }
  ensure_root() { :; }
  sleep 120 & sentinel=$!
  trap 'kill "$sentinel" 2>/dev/null || true; wait "$sentinel" 2>/dev/null || true' EXIT
  cp "$release_test/runtime.tar.gz" "$manual/runtime.tar.gz"
  SBD_RELEASE_ARCHIVE_URL="$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).resolve().as_uri())' "$manual/runtime.tar.gz")"
  SBD_RELEASE_SHA256="$release_sum"
  update_command --script --yes
  [[ "$("$SBD_LAUNCHER_PATH" --print-version)" == v9.0.1 ]]
  [[ "$(readlink -f "$SBD_INSTALL_DIR/previous")" == "$SBD_INSTALL_DIR/releases/legacy-"* ]]
  update_command --script --yes
  sha256sum -c "$manual/preserved.sha256"
  kill -0 "$sentinel"
  [[ ! -L "$SBD_HOST_STATE_DIR/transactions/active" ]]
  printf '[OK] manual local-archive update and repeated update preserved core/config/identity/legacy unit; no service operations\n'
)
printf '[OK] runtime release, migration and interruption checks passed\n'
