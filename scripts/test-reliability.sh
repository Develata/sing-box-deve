#!/usr/bin/env bash
# SC2329 directives mark overrides called by sourced lifecycle code, or guards
# that fail if a forbidden service/filesystem operation is attempted.
# shellcheck disable=SC1091,SC2034,SC2317,SC2178
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$PROJECT_ROOT/lib/load.sh"
test_root="$(mktemp -d)"
child=""
trap '[[ -z "$child" ]] || kill "$child" 2>/dev/null || true; rm -rf "$test_root"' EXIT
SBD_INSTALL_DIR="$test_root/install"
SBD_CONFIG_DIR="$test_root/config"
SBD_STATE_DIR="$test_root/state"
SBD_HOST_STATE_DIR="$test_root/control"
SBD_RUNTIME_DIR="$test_root/run"
SBD_BIN_DIR="$SBD_INSTALL_DIR/bin"
SBD_DATA_DIR="$SBD_INSTALL_DIR/data"
SBD_CACHE_DIR="$SBD_INSTALL_DIR/cache"
SBD_RULES_FILE="$SBD_STATE_DIR/firewall-rules.db"
SBD_SERVICE_FILE="$test_root/services/core"
SBD_ARGO_SERVICE_FILE="$test_root/services/argo"
SBD_FW_REPLAY_SERVICE_FILE="$test_root/services/firewall"
SBD_WARP_SOCKS_SERVICE_FILE="$test_root/services/warp"
SBD_SETTINGS_FILE="$SBD_CONFIG_DIR/settings.conf"
SBD_INIT_SYSTEM="nohup"
SBD_LAUNCHER_PATH="$test_root/global/sb"
mkdir -p "$SBD_CONFIG_DIR" "$SBD_DATA_DIR" "$SBD_STATE_DIR" "$SBD_BIN_DIR" "$SBD_RUNTIME_DIR"
ensure_root() { return 0; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

# Failed rename in a conditional caller must not report a successful commit.
printf 'old\n' > "$test_root/file"
printf 'new\n' > "$test_root/candidate"
(
  mv() { return 28; }
  if sbd_commit_file_with_backups "$test_root/file" "$test_root/candidate"; then exit 1; fi
) || fail 'commit failure was hidden'
[[ "$(cat "$test_root/file")" == old ]] || fail 'failed commit damaged live file'

# Whole-file parsing is atomic; unknown runtime fields and truncation fail closed.
printf 'provider=vps\nprofile=lite\nengine=sing-box\nprotocols=vless-reality\n' > "$SBD_CONFIG_DIR/runtime.env"
sbd_load_runtime_env
[[ "$engine" == sing-box ]] || fail 'valid runtime rejected'
printf 'provider=serv00\nprofile=lite\nengine=xray\nprotocols=vless-reality\nPATH=/bad\n' > "$test_root/bad.env"
if sbd_load_runtime_env "$test_root/bad.env"; then fail 'reserved key accepted'; fi
[[ "$provider" == vps && "$engine" == sing-box ]] || fail 'partial runtime was published'
printf 'provider=serv00\nprofile=lite\nengine=xray\nprotocols="vless-reality\n' > "$test_root/bad.env"
if sbd_load_runtime_env "$test_root/bad.env"; then fail 'truncated quote accepted'; fi
[[ "$provider" == vps && "$engine" == sing-box ]] || fail 'truncated runtime leaked values'

# A complete-looking prefix truncated at a key boundary is rejected in v2.
sbd_seal_runtime_file "$SBD_CONFIG_DIR/runtime.env"
sbd_load_runtime_env
head -n -1 "$SBD_CONFIG_DIR/runtime.env" > "$test_root/truncated.env"
if sbd_load_runtime_env "$test_root/truncated.env"; then fail 'v2 missing footer accepted'; fi
cp "$SBD_CONFIG_DIR/runtime.env" "$test_root/corrupt.env"
sed -i 's/provider=vps/provider=serv00/' "$test_root/corrupt.env"
if sbd_load_runtime_env "$test_root/corrupt.env"; then fail 'v2 content corruption accepted'; fi

# Snapshot restores authoritative identity, generated ports and absence markers.
printf 'original-uuid\n' > "$SBD_DATA_DIR/uuid"
printf '{"port":12345}\n' > "$SBD_CONFIG_DIR/config.json"
sbd_state_capture "$test_root/snapshot" false
printf 'changed-uuid\n' > "$SBD_DATA_DIR/uuid"
printf 'new-secret\n' > "$SBD_DATA_DIR/ss2022_password"
printf '{"port":54321}\n' > "$SBD_CONFIG_DIR/config.json"
sbd_state_restore "$test_root/snapshot"
[[ "$(cat "$SBD_DATA_DIR/uuid")" == original-uuid && ! -e "$SBD_DATA_DIR/ss2022_password" ]] || fail 'identity/absence rollback failed'
[[ "$(jq -r .port "$SBD_CONFIG_DIR/config.json")" == 12345 ]] || fail 'port rollback failed'
cp "$test_root/snapshot/checksums.txt" "$test_root/sums"
sed -i '/files\/data\/uuid$/d' "$test_root/snapshot/checksums.txt"
if sbd_state_restore "$test_root/snapshot"; then fail 'incomplete checksum inventory accepted'; fi
cp "$test_root/sums" "$test_root/snapshot/checksums.txt"
rm "$test_root/snapshot/files/data/uuid"
ln -s "$SBD_DATA_DIR/uuid" "$test_root/snapshot/files/data/uuid"
if sbd_state_restore "$test_root/snapshot"; then fail 'symlink snapshot accepted'; fi

# Host modifications compensate only content matching the journal.
host_file="$test_root/host.conf"
printf 'host-before\n' > "$host_file"
mkdir "$test_root/host-txn"
SBD_ACTIVE_TRANSACTION="$test_root/host-txn"
printf 'host-after\n' > "$test_root/host-candidate"
sbd_host_file_publish "$host_file" "$test_root/host-candidate"
sbd_host_transaction_restore "$SBD_ACTIVE_TRANSACTION"
[[ "$(cat "$host_file")" == host-before ]] || fail 'host undo failed'
unset SBD_ACTIVE_TRANSACTION
printf 'host-managed\n' > "$test_root/host-candidate"
sbd_host_file_publish "$host_file" "$test_root/host-candidate"
printf 'external-change\n' > "$host_file"
sbd_host_purge
[[ "$(cat "$host_file")" == external-change ]] || fail 'purge overwrote external change'

# Failed install and uncatchable SIGKILL recover before the next mutation.
rm "$SBD_CONFIG_DIR/runtime.env"
sbd_service_stop() { return 0; }
sbd_service_daemon_reload() { return 0; }
fw_replay() { return 0; }
change_then_fail() {
  sbd_transaction_phase "$SBD_ACTIVE_TRANSACTION" committing || return 1
  printf 'broken\n' > "$SBD_DATA_DIR/uuid"
  return 28
}
if sbd_with_mutation_lock sbd_transaction_run install change_then_fail; then fail 'failed install reported success'; fi
[[ "$(cat "$SBD_DATA_DIR/uuid")" == original-uuid ]] || fail 'failed install did not recover'
change_then_kill() {
  sbd_transaction_phase "$SBD_ACTIVE_TRANSACTION" committing || return 1
  printf 'interrupted\n' > "$SBD_DATA_DIR/uuid"
  kill -KILL "$BASHPID"
}
if sbd_with_mutation_lock sbd_transaction_run install change_then_kill; then fail 'killed install reported success'; fi
[[ -L "$SBD_HOST_STATE_DIR/transactions/active" ]] || fail 'SIGKILL lost recovery record'
active_dir="$(readlink -f "$SBD_HOST_STATE_DIR/transactions/active")"
cp "$active_dir/lifecycle" "$test_root/saved-lifecycle"
printf 'corrupt-service active enabled\n' >> "$active_dir/lifecycle"
if sbd_with_mutation_lock true; then fail 'corrupt transaction metadata accepted'; fi
[[ "$(cat "$SBD_DATA_DIR/uuid")" == interrupted ]] || fail 'corrupt recovery performed partial state writes'
cp "$test_root/saved-lifecycle" "$active_dir/lifecycle"
sbd_with_mutation_lock true
[[ "$(cat "$SBD_DATA_DIR/uuid")" == original-uuid && ! -e "$SBD_HOST_STATE_DIR/transactions/active" ]] || fail 'next mutation did not recover interruption'

# An unrelated pre-existing service is never adopted by overwriting its file.
mkdir -p "$(dirname "$SBD_SERVICE_FILE")"
printf '[Service]\nExecStart=/foreign/bin/server\n' > "$SBD_SERVICE_FILE"
printf '# Managed by sing-box-deve: service-v1\n[Service]\nExecStart=%s/bin/sing-box\n' "$SBD_INSTALL_DIR" > "$test_root/unit-candidate"
if sbd_host_file_publish "$SBD_SERVICE_FILE" "$test_root/unit-candidate"; then fail 'foreign service was adopted'; fi
grep -q '/foreign/bin/server' "$SBD_SERVICE_FILE" || fail 'foreign unit changed'
rm "$SBD_SERVICE_FILE"

# Archive pages participate in the same host undo journal.
sbd_write_archive_gateway_site >/dev/null
archive_index="$SBD_INSTALL_DIR/archive-gateway/index.html"
archive_sum="$(sha256sum "$archive_index")"
mkdir "$test_root/site-txn"
SBD_ACTIVE_TRANSACTION="$test_root/site-txn"
printf 'changed page\n' > "$test_root/site-candidate"
sbd_host_file_publish "$archive_index" "$test_root/site-candidate"
sbd_host_transaction_restore "$SBD_ACTIVE_TRANSACTION"
[[ "$(sha256sum "$archive_index")" == "$archive_sum" ]] || fail 'archive page undo failed'
unset SBD_ACTIVE_TRANSACTION

# Web service compensation observes the restored file and prior enable state.
(
  mkdir "$test_root/web-txn"
  SBD_ACTIVE_TRANSACTION="$test_root/web-txn"
  sbd_systemd_unit_exists() { return 0; }
  sbd_service_op() {
    case "$*" in
      *'show -p ActiveState'*) printf 'ActiveState=active\nUnitFileState=disabled\n' ;;
      *'reload nginx.service'*) [[ "$(cat "$test_root/web.conf")" == old-web ]] || return 1; printf 'reloaded\n' >> "$test_root/web-actions" ;;
      *'disable nginx.service'*) printf 'disabled\n' >> "$test_root/web-actions" ;;
      *) return 1 ;;
    esac
  }
  printf 'old-web\n' > "$test_root/web.conf"
  printf 'new-web\n' > "$test_root/web-candidate"
  sbd_host_file_publish "$test_root/web.conf" "$test_root/web-candidate"
  sbd_web_front_capture_service /bin/true nginx
  sbd_host_transaction_restore "$SBD_ACTIVE_TRANSACTION"
  sbd_web_front_restore_service "$SBD_ACTIVE_TRANSACTION"
  [[ "$(cat "$test_root/web-actions")" == $'reloaded\ndisabled' ]] || fail 'web runtime state was not compensated'
)

# Port change failure restores both generated port and firewall ledger.
(
  # shellcheck disable=SC2329
  provider_cfg_load_runtime_exports() { provider=vps; profile=lite; engine=sing-box; protocols=vless-reality; }
  # shellcheck disable=SC2329
  provider_multi_ports_reject_conflict() { return 0; }
  # shellcheck disable=SC2329
  validate_generated_config() { return 0; }
  # shellcheck disable=SC2329
  fw_detect_backend() { FW_BACKEND=iptables; }
  # shellcheck disable=SC2329
  load_install_context() { return 0; }
  # shellcheck disable=SC2329
  fw_apply_rule() { printf 'iptables|tcp|%s|MYBOX:test:core:tcp:%s|now\n' "$2" "$2" > "$SBD_RULES_FILE"; }
  # shellcheck disable=SC2329
  fw_remove_rule_by_record() { printf 'removed\n' > "$test_root/port-fw-undo"; }
  # shellcheck disable=SC2329
  provider_restart() { return 1; }
  printf '{"inbounds":[{"tag":"vless-reality","listen_port":12345}]}\n' > "$SBD_CONFIG_DIR/config.json"
  if provider_set_port vless-reality 23456; then fail 'failed port restart reported success'; fi
  [[ "$(jq -r '.inbounds[0].listen_port' "$SBD_CONFIG_DIR/config.json")" == 12345 ]] || fail 'port did not recover'
  [[ ! -e "$SBD_RULES_FILE" && -f "$test_root/port-fw-undo" ]] || fail 'port firewall did not recover'
)

# A failed registration HTTP request leaves the existing account intact.
(
  printf 'account-before\n' > "$SBD_DATA_DIR/warp-account.env"
  sbd_http_small() { return 28; }
  if provider_warp_register_unlocked; then fail 'failed WARP HTTP request reported success'; fi
  [[ "$(cat "$SBD_DATA_DIR/warp-account.env")" == account-before ]] || fail 'failed WARP registration replaced account'
)

# Bare PID or wrong identity must never signal an unrelated living process.
sleep 120 & child=$!
printf '%s\n' "$child" > "$SBD_RUNTIME_DIR/stale.pid"
printf 'wrong-boot|wrong-start|wrong-exe\n' > "$SBD_RUNTIME_DIR/stale.pid.identity"
if nohup_stop_service stale; then fail 'stale PID accepted'; fi
kill -0 "$child" || fail 'unrelated process was killed'
printf '00000000-0000-0000-0000-000000000000|previous-start|previous-inode|/old/exe\n' > "$SBD_RUNTIME_DIR/stale.pid.identity"
nohup_remove_crontab() { return 0; }
nohup_stop_service stale
kill -0 "$child" || fail 'previous-boot retirement signaled unrelated current process'
[[ ! -e "$SBD_RUNTIME_DIR/stale.pid" ]] || fail 'previous boot state blocked restart'
kill "$child"; wait "$child" 2>/dev/null || true; child=""

# Backup destination must be outside the entire uninstall deletion set.
if sbd_uninstall_backup "$SBD_DATA_DIR/backup"; then fail 'unsafe backup destination accepted'; fi
sbd_uninstall_backup "$test_root/safe-backup"
[[ "$(cat "$test_root/safe-backup/files/data/uuid")" == original-uuid ]] || fail 'backup missing identity'
SBD_INSTALL_DIR=/tmp
if sbd_uninstall_validate_roots; then fail 'broad uninstall path accepted'; fi
printf '[OK] reliability failure-injection checks passed\n'
