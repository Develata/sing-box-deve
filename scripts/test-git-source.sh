#!/usr/bin/env bash
# The stale-menu case intentionally changes PROJECT_ROOT only in a subshell.
# shellcheck disable=SC1091,SC2030,SC2031,SC2034,SC2317
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$PROJECT_ROOT/lib/load.sh"
# Binding deliberately rejects ephemeral roots and writable ancestors.
git_test="$(mktemp -d "${HOME}/.sbd-source-test.XXXXXX")"
trap 'rm -rf "$git_test"' EXIT
checkout="$git_test/source with spaces and ' quotes"
upstream="$git_test/upstream"
mkdir -p "$upstream"
python3 - "$PROJECT_ROOT" "$upstream" <<'PY'
from pathlib import Path
import shutil, sys
source, target = map(Path, sys.argv[1:])
names = ['checksums.txt'] + [line.split('  ', 1)[1] for line in (source / 'checksums.txt').read_text().splitlines()]
for name in names:
    dest = target / name
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source / name, dest)
PY
git -C "$upstream" init -q -b main
commit_source() {
  local root="$1" message="$2"
  bash "$root/scripts/update-checksums.sh" >/dev/null
  git -C "$root" add .
  git -C "$root" -c user.name=SourceTest -c user.email=source@example.invalid commit -qm "$message"
}
commit_source "$upstream" initial
git clone -q "$upstream" "$checkout"
owner="$(stat -c %u "$checkout")"
SBD_INSTALL_DIR="$git_test/install"
SBD_CONFIG_DIR="$git_test/config"
SBD_STATE_DIR="$git_test/state"
SBD_RUNTIME_DIR="$git_test/run"
SBD_HOST_STATE_DIR="$git_test/control"
SBD_BIN_DIR="$SBD_INSTALL_DIR/bin"
SBD_DATA_DIR="$SBD_INSTALL_DIR/data"
SBD_ARGO_TOKEN_FILE="$SBD_DATA_DIR/argo-token"
SBD_ARGO_EXEC_FILE="$SBD_DATA_DIR/argo-exec"
SBD_RULES_FILE="$SBD_STATE_DIR/firewall-rules.db"
SBD_LAUNCHER_PATH="$git_test/bin/sb"
SBD_SERVICE_FILE="$git_test/service/core"
SBD_ARGO_SERVICE_FILE="$git_test/service/argo"
SBD_FW_REPLAY_SERVICE_FILE="$git_test/service/firewall"
SBD_WARP_SOCKS_SERVICE_FILE="$git_test/service/warp"
SBD_INIT_SYSTEM="nohup"
mkdir -p "$SBD_CONFIG_DIR" "$SBD_DATA_DIR" "$SBD_BIN_DIR" "$git_test/service"
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
expect_fail() { if ("$@") >"$git_test/expected-error" 2>&1; then fail "unexpected success: $*"; fi; }
sbd_service_probe() { printf 'active enabled\n'; }
sbd_service_op() { fail 'source operation invoked a service operation'; }
sbd_service_stop() { fail 'source operation stopped a service'; }
fw_replay() { fail 'source operation rewrote firewall'; }
write_nodes_output() { fail 'source operation regenerated nodes'; }
ensure_root() { :; }
crontab() { return 1; }
printf 'unchanged core\n' > "$SBD_BIN_DIR/sing-box"
printf '{"preserve":"config"}\n' > "$SBD_CONFIG_DIR/config.json"
printf 'unchanged identity\n' > "$SBD_DATA_DIR/uuid"
sha256sum "$SBD_BIN_DIR/sing-box" "$SBD_CONFIG_DIR/config.json" "$SBD_DATA_DIR/uuid" > "$git_test/preserved.sha256"
printf 'provider="vps"\nprofile="lite"\nengine="sing-box"\nprotocols="vless-reality"\n' > "$SBD_CONFIG_DIR/runtime.env"
sbd_write_env_kv script_root "$PROJECT_ROOT" >> "$SBD_CONFIG_DIR/runtime.env"
sbd_with_mutation_lock sbd_transaction_run script-update sbd_release_install_tree "$checkout" >/dev/null
before="$(readlink -f "$SBD_INSTALL_DIR/current")"
cp "$SBD_CONFIG_DIR/runtime.env" "$git_test/release.env"
mkdir -p "$SBD_STATE_DIR/cfg-snapshots"
sbd_state_capture "$SBD_STATE_DIR/cfg-snapshots/release-before-binding" false
provider_warp_snapshot_lifecycle "$SBD_STATE_DIR/cfg-snapshots/release-before-binding"
cfg_source_rollback() (
  provider_cfg_rebuild_runtime() { provider_cfg_load_runtime_exports; persist_runtime_state vps lite sing-box vless-reality; }
  sbd_service_stop() { :; }
  sbd_service_daemon_reload() { :; }
  write_nodes_output() { :; }
  sbd_with_mutation_lock sbd_transaction_run config-rollback provider_cfg_rollback_unlocked "$1" >/dev/null
)
expect_fail sbd_git_source_path_allowed /tmp/checkout
expect_fail sbd_git_source_path_allowed "$SBD_INSTALL_DIR/source"
expect_fail sbd_git_source_path_allowed "$git_test"
expect_fail sbd_git_source_verify "$checkout" "$((owner + 1))"
chmod g+w "$checkout/lib/common.sh"
expect_fail sbd_git_source_verify "$checkout" "$owner"
chmod g-w "$checkout/lib/common.sh"
printf '\n# local modification\n' >> "$checkout/lib/common.sh"
expect_fail sbd_git_source_verify "$checkout" "$owner"
git -C "$checkout" restore lib/common.sh

update_command --bind-git "$checkout" --yes >/dev/null
[[ "$("$SBD_LAUNCHER_PATH" --print-root)" == "$checkout" ]] || fail 'binding did not select fixed checkout'
"$SBD_LAUNCHER_PATH" --self-test
declare -A binding=()
sbd_read_source_state binding
[[ "${binding[script_source]}" == git && "${binding[script_fallback_root]}" == "$before" ]]
cp "$SBD_CONFIG_DIR/runtime.env" "$git_test/bound.env"
update_command --bind-git "$checkout" --yes >/dev/null
cmp "$git_test/bound.env" "$SBD_CONFIG_DIR/runtime.env" || fail 'repeated binding changed source state'
(cd /; [[ "$("$SBD_LAUNCHER_PATH" --print-root)" == "$checkout" ]]) || fail 'cwd redirected bound source'
update_command --script --yes >/dev/null
update_command --check-source >/dev/null
cmp "$git_test/bound.env" "$SBD_CONFIG_DIR/runtime.env" || fail 'source check mutated runtime'
persist_runtime_state vps lite sing-box vless-reality
sbd_source_is_git || fail 'configuration persistence lost Git binding'
[[ "$(sbd_read_runtime_script_root)" == "$checkout" ]]
cfg_source_rollback release-before-binding
sbd_source_is_git || fail 'configuration rollback changed source mode'
[[ "$(sbd_read_runtime_script_root)" == "$checkout" ]]
sbd_state_capture "$SBD_STATE_DIR/cfg-snapshots/with-binding" false
provider_warp_snapshot_lifecycle "$SBD_STATE_DIR/cfg-snapshots/with-binding"

# Both version and same-version commits follow an actual git pull.
stamp="$(sbd_git_source_verify "$checkout" "$owner")"
printf 'v9.8.7\n' > "$upstream/version"
commit_source "$upstream" next-version
git -C "$checkout" pull -q --ff-only
[[ "$("$SBD_LAUNCHER_PATH" --print-version)" == v9.8.7 ]] || fail 'pulled version stayed stale'
(
  PROJECT_ROOT="$checkout"
  SBD_GIT_SOURCE_STAMP="$stamp" SBD_GIT_SOURCE_UID="$owner"
  expect_fail sbd_with_mutation_lock touch "$git_test/stale-command"
  [[ ! -e "$git_test/stale-command" ]]
)
stamp="$(sbd_git_source_verify "$checkout" "$owner")"
printf '\n# next commit, same version\n' >> "$upstream/lib/common_source_binding.sh"
commit_source "$upstream" same-version
git -C "$checkout" pull -q --ff-only
next_stamp="$(sbd_git_source_verify "$checkout" "$owner")"
[[ "${stamp%%:*}" != "${next_stamp%%:*}" ]]
[[ "$("$SBD_LAUNCHER_PATH" --print-version)" == v9.8.7 ]]
"$SBD_LAUNCHER_PATH" --self-test
# A developer may edit the checkout, but all managed checksums must agree.
printf '\n# intentional local edit\n' >> "$checkout/lib/common_source_binding.sh"
expect_fail "$SBD_LAUNCHER_PATH" --self-test
bash "$checkout/scripts/update-checksums.sh" >/dev/null
[[ "$(sbd_git_source_verify "$checkout" "$owner")" == *:modified ]]
"$SBD_LAUNCHER_PATH" --self-test
git -C "$checkout" restore lib/common_source_binding.sh checksums.txt
mv "$checkout/lib/providers.sh" "$git_test/module.saved"
expect_fail "$SBD_LAUNCHER_PATH" --print-version
mv "$git_test/module.saved" "$checkout/lib/providers.sh"
printf '#!/usr/bin/env bash\n' > "$checkout/lib/unlisted.sh"
expect_fail sbd_git_source_verify "$checkout" "$owner"
rm "$checkout/lib/unlisted.sh"
mv "$checkout/lib/common.sh" "$git_test/common.saved"
ln -s "$git_test/common.saved" "$checkout/lib/common.sh"
expect_fail sbd_git_source_verify "$checkout" "$owner"
rm "$checkout/lib/common.sh"
mv "$git_test/common.saved" "$checkout/lib/common.sh"

# Failed changes and an interrupted source switch recover selectors, runtime and
# launcher without invoking the core, node renderer or firewall.
cp "$SBD_CONFIG_DIR/runtime.env" "$git_test/before-failure.env"
change_then_fail() { sbd_update_runtime_script_root "$SBD_INSTALL_DIR/current"; return 29; }
expect_fail sbd_with_mutation_lock sbd_transaction_run script-update change_then_fail
cmp "$git_test/before-failure.env" "$SBD_CONFIG_DIR/runtime.env"
[[ ! -L "$SBD_HOST_STATE_DIR/transactions/active" ]]
transaction="$(sbd_with_mutation_lock sbd_transaction_begin script-update)"
sbd_update_runtime_script_root "$SBD_INSTALL_DIR/current"
sbd_transaction_recover >/dev/null
cmp "$git_test/before-failure.env" "$SBD_CONFIG_DIR/runtime.env"
[[ "$(cat "$transaction/phase")" == recovered ]]
mv "$checkout" "$checkout.moved"
expect_fail "$SBD_LAUNCHER_PATH" --print-root
grep -q 'sb --rollback-source' "$git_test/expected-error" || fail 'broken binding omitted fixed recovery command'
update_command --rollback >/dev/null
[[ "$("$SBD_LAUNCHER_PATH" --print-root)" == "$before" ]] || fail 'rollback did not restore pre-binding release'
sbd_source_is_git && fail 'rollback retained Git mode'
if grep -qE '^script_(source|source_uid|fallback_root)=' "$SBD_CONFIG_DIR/runtime.env"; then fail 'rollback retained new runtime keys'; fi
mv "$checkout.moved" "$checkout"

# Release installation is explicit, clears the binding, and leaves Git alone.
update_command --bind-git "$checkout" --yes >/dev/null
python3 "$PROJECT_ROOT/scripts/runtime-archive.py" pack "$checkout" "$git_test/runtime.tar.gz"
SBD_RELEASE_ARCHIVE_URL="file://$git_test/runtime.tar.gz"
SBD_RELEASE_SHA256="$(sha256sum "$git_test/runtime.tar.gz")"
SBD_RELEASE_SHA256="${SBD_RELEASE_SHA256%% *}"
update_command --release --yes >/dev/null
sbd_source_is_git && fail 'explicit Release update retained Git mode'
[[ "$(git -C "$checkout" rev-parse HEAD)" == "${next_stamp%%:*}" ]]
[[ -z "$(git -C "$checkout" status --porcelain)" ]]
cfg_source_rollback with-binding
! sbd_source_is_git || fail 'configuration snapshot resurrected a Git binding'
sha256sum -c "$git_test/preserved.sha256"
expect_fail parse_update_args --bind-git "$checkout" --core
expect_fail parse_update_args --check-source --rollback
expect_fail parse_update_args --release --rollback
git -C "$upstream" worktree add -q --detach "$git_test/worktree" HEAD
update_command --bind-git "$git_test/worktree" --yes >/dev/null
[[ "$("$SBD_LAUNCHER_PATH" --print-root)" == "$git_test/worktree" ]]
# The real deletion path operates only on this fixture's managed directories.
(
  SBD_GLOBAL_BIN_DIR="$git_test/bin" SBD_SYSTEMD_DIR="$git_test/service"
  uninstall_disable_unit() { :; }
  sbd_service_is_active() { return 1; }
  sbd_service_daemon_reload() { :; }
  fw_detect_backend_optional() { return 1; }
  provider_uninstall false >/dev/null
)
[[ -d "$checkout/.git" && -f "$git_test/worktree/.git" ]]
sbd_git_source_verify "$git_test/worktree" "$owner" >/dev/null
printf '[OK] fixed Git source, real pull, dirty/missing/unsafe source, stale menu, repeat, recovery and Release rollback checks passed\n'
