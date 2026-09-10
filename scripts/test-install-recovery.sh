#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034,SC2317
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$PROJECT_ROOT/lib/load.sh"
install_test="$(mktemp -d)"
trap 'rm -rf "$install_test"' EXIT
SBD_INSTALL_DIR="$install_test/install"
SBD_CONFIG_DIR="$install_test/config"
SBD_STATE_DIR="$install_test/state"
SBD_HOST_STATE_DIR="$install_test/control"
SBD_RUNTIME_DIR="$install_test/run"
SBD_BIN_DIR="$SBD_INSTALL_DIR/bin"
SBD_DATA_DIR="$SBD_INSTALL_DIR/data"
SBD_CACHE_DIR="$SBD_INSTALL_DIR/cache"
SBD_RULES_FILE="$SBD_STATE_DIR/firewall-rules.db"
SBD_CONTEXT_FILE="$SBD_STATE_DIR/context.env"
SBD_SETTINGS_FILE="$SBD_CONFIG_DIR/settings.conf"
CONFIG_SNAPSHOT_FILE="$SBD_CONFIG_DIR/config.yaml"
SBD_SERVICE_FILE="$install_test/services/core"
SBD_ARGO_SERVICE_FILE="$install_test/services/argo"
SBD_FW_REPLAY_SERVICE_FILE="$install_test/services/firewall"
SBD_WARP_SOCKS_SERVICE_FILE="$install_test/services/warp"
SBD_ARGO_TOKEN_FILE="$SBD_DATA_DIR/argo-token"
SBD_ARGO_EXEC_FILE="$SBD_DATA_DIR/argo-exec"
SBD_LAUNCHER_PATH="$install_test/bin/sb"
SBD_INIT_SYSTEM=systemd
fail() { echo "[FAIL] $*" >&2; exit 1; }
ensure_root() { :; }
detect_os() { OS_ID=debian; }
install_apt_dependencies() { :; }
provider_prepare_domain_runtime_artifacts() { :; }
fw_detect_backend() { FW_BACKEND=none; }
fw_snapshot_create() { :; }
fw_apply_rule() { :; }
fw_rollback() { :; }
fw_replay() { :; }
validate_generated_config() { :; }
sbd_service_op() { :; }
sbd_service_daemon_reload() { :; }
sbd_service_stop() { :; }
sbd_service_probe() { if [[ "$1" == sing-box-deve && -f "$SBD_SERVICE_FILE" ]]; then echo 'active enabled'; else echo 'inactive disabled'; fi; }
safe_service_restart() { cat "$SBD_DATA_DIR/engine-version" >> "$install_test/restarts"; }
write_nodes_output() { printf 'derived\n' > "$SBD_DATA_DIR/nodes.txt"; }
print_post_install_info() { :; }
fail_late=false
generation=v9.0.0
configure_argo_tunnel() { [[ "$fail_late" != true ]]; }
install_engine_binary() {
  mkdir -p "$SBD_BIN_DIR" "$SBD_DATA_DIR"
  cat > "$SBD_BIN_DIR/sing-box" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  generate) printf 'PrivateKey: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\nPublicKey: BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB\n' ;;
  *) exit 0 ;;
esac
SH
  chmod +x "$SBD_BIN_DIR/sing-box"
  printf '%s\n' "$generation" > "$SBD_DATA_DIR/engine-version"
}
parse_install_args --provider vps --profile lite --engine sing-box --protocols vless-reality --uuid 11111111-1111-4111-8111-111111111111 --yes
run_install vps lite sing-box vless-reality false
first="$(readlink -f "$SBD_INSTALL_DIR/current")"
[[ "$("$SBD_LAUNCHER_PATH" --print-root)" == "$first" ]] || fail 'fresh install did not select immutable release'
sbd_load_runtime_env
[[ "$(cat "$SBD_DATA_DIR/engine-version")" == v9.0.0 ]] || fail 'initial core version incorrect'
original_uuid="$(cat "$SBD_DATA_DIR/uuid")"
original_config="$(sha256sum "$SBD_CONFIG_DIR/config.json")"
# New source generation, with a late failure after core and service publication.
mkdir "$install_test/source"
cp -a "$PROJECT_ROOT/lib" "$PROJECT_ROOT/providers" "$PROJECT_ROOT/rulesets" "$PROJECT_ROOT/scripts" "$install_test/source/"
cp "$PROJECT_ROOT/sing-box-deve.sh" "$PROJECT_ROOT/LICENSE" "$install_test/source/"
printf 'v9.9.9\n' > "$install_test/source/version"
PROJECT_ROOT="$install_test/source"
generation=v9.0.1
fail_late=true
if run_install vps lite sing-box vless-reality false; then fail 'late reinstall failure was hidden'; fi
[[ "$(readlink -f "$SBD_INSTALL_DIR/current")" == "$first" ]] || fail 'failed reinstall changed script selector'
[[ "$(cat "$SBD_DATA_DIR/uuid")" == "$original_uuid" ]] || fail 'failed reinstall changed identity'
[[ "$(sha256sum "$SBD_CONFIG_DIR/config.json")" == "$original_config" ]] || fail 'failed reinstall changed config'
[[ "$(cat "$SBD_DATA_DIR/engine-version")" == v9.0.0 ]] || fail 'failed reinstall changed core version'
[[ "$(tail -n1 "$install_test/restarts")" == v9.0.0 ]] || fail 'recovery did not restart previous core'
fail_late=false
run_install vps lite sing-box vless-reality false
[[ "$(cat "$SBD_DATA_DIR/engine-version")" == v9.0.1 ]] || fail 'candidate data copied old version over new version'
[[ "$("$SBD_LAUNCHER_PATH" --print-version)" == v9.9.9 ]] || fail 'successful reinstall did not switch script release'
printf '[OK] full install/reinstall recovery path checks passed\n'

# Failure after selector/launcher publication recovers the full previous entry.
selected_before="$(readlink -f "$SBD_INSTALL_DIR/current")"
previous_before="$(readlink -f "$SBD_INSTALL_DIR/previous")"
launcher_before="$(sha256sum "$SBD_LAUNCHER_PATH")"
printf 'v9.9.10\n' > "$PROJECT_ROOT/version"
(
  sbd_update_runtime_script_root() { return 28; }
  if sync_installed_script_root_from_project; then fail 'runtime-root write failure was hidden'; fi
)
[[ "$(readlink -f "$SBD_INSTALL_DIR/current")" == "$selected_before" ]] || fail 'script update failure lost current'
[[ "$(readlink -f "$SBD_INSTALL_DIR/previous")" == "$previous_before" ]] || fail 'script update failure lost previous'
[[ "$(sha256sum "$SBD_LAUNCHER_PATH")" == "$launcher_before" ]] || fail 'script update failure changed launcher'
[[ "$("$SBD_LAUNCHER_PATH" --print-version)" == v9.9.9 ]] || fail 'script update failure broke launch'
printf '[OK] script update publication failure recovery passed\n'
