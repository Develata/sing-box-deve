#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034,SC2317
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$PROJECT_ROOT/lib/load.sh"
retired_root="$(mktemp -d)"
trap 'rm -rf "$retired_root"' EXIT
SBD_INSTALL_DIR="$retired_root/install"
SBD_CONFIG_DIR="$retired_root/config"
SBD_STATE_DIR="$retired_root/state"
SBD_HOST_STATE_DIR="$retired_root/control"
SBD_RUNTIME_DIR="$retired_root/run"
SBD_BIN_DIR="$SBD_INSTALL_DIR/bin"
SBD_DATA_DIR="$SBD_INSTALL_DIR/data"
SBD_RULES_FILE="$SBD_STATE_DIR/firewall-rules.db"
SBD_NODES_FILE="$SBD_DATA_DIR/nodes.txt"
SBD_SERVICE_FILE="$retired_root/services/core"
SBD_ARGO_SERVICE_FILE="$retired_root/services/argo"
SBD_FW_REPLAY_SERVICE_FILE="$retired_root/services/firewall"
SBD_WARP_SOCKS_SERVICE_FILE="$retired_root/services/warp"
mkdir -p "$SBD_CONFIG_DIR" "$SBD_DATA_DIR" "$SBD_BIN_DIR" "$SBD_STATE_DIR"
printf 'existing core\n' > "$SBD_BIN_DIR/sing-box"
printf '{"inbounds":[{"type":"tuic","tag":"tuic","listen_port":10443}]}\n' > "$SBD_CONFIG_DIR/config.json"
printf 'existing identity\n' > "$SBD_DATA_DIR/uuid"
printf 'tuic://test-only@192.0.2.1:10443\n' > "$SBD_NODES_FILE"
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
unexpected_mutation() { touch "$retired_root/unexpected"; return 1; }
ensure_root() { :; }
crontab() { return 1; }
sbd_service_probe() { printf 'active enabled\n'; }
sbd_service_stop() { unexpected_mutation; }
sbd_service_daemon_reload() { :; }
provider_restart() { unexpected_mutation; }
fw_replay() { :; }

write_test_runtime() {
  {
    sbd_write_env_kv provider vps
    sbd_write_env_kv profile full
    sbd_write_env_kv engine sing-box
    sbd_write_env_kv protocols "$1"
    sbd_write_env_kv outbound_proxy_mode "$2"
    sbd_write_env_kv outbound_proxy_link "$3"
  } > "$SBD_CONFIG_DIR/runtime.env"
  sbd_seal_runtime_file "$SBD_CONFIG_DIR/runtime.env"
  chmod 600 "$SBD_CONFIG_DIR/runtime.env"
}

if contains_protocol tuic || engine_supports_protocol sing-box tuic || engine_supports_protocol xray tuic; then
  fail 'retired protocol is still advertised'
fi
sha256sum "$SBD_BIN_DIR/sing-box" "$SBD_CONFIG_DIR/config.json" "$SBD_DATA_DIR/uuid" "$SBD_NODES_FILE" > "$retired_root/files.sha256"
for generator in build_sing_box_config build_xray_config; do
  if ("$generator" vless-reality,tuic); then fail 'retired inbound was silently dropped'; fi
done
if (write_nodes_output sing-box vless-reality,tuic); then fail 'retired nodes were silently regenerated'; fi
sha256sum -c "$retired_root/files.sha256" >/dev/null

# Both legacy inbound state and upstream state remain readable, but cannot
# enter a configuration/core transaction that would discard unsupported data.
for scenario in inbound upstream link; do
  case "$scenario" in
    inbound) write_test_runtime vless-reality,tuic direct '' ;;
    upstream) write_test_runtime vless-reality tuic '' ;;
    link) write_test_runtime vless-reality direct 'TUIC://test-only@192.0.2.1:443' ;;
  esac
  sbd_load_runtime_env
  before="$(sha256sum "$SBD_CONFIG_DIR/runtime.env")"
  for kind in install config-change core-update kernel-set host-change; do
    if sbd_with_mutation_lock sbd_transaction_run "$kind" unexpected_mutation; then
      fail 'retired runtime entered a modifying transaction'
    fi
    [[ ! -L "$SBD_HOST_STATE_DIR/transactions/active" && ! -e "$retired_root/unexpected" ]]
  done
  [[ "$before" == "$(sha256sum "$SBD_CONFIG_DIR/runtime.env")" ]]
done

# A failed script update must recover without regenerating retired artifacts.
write_nodes_output() {
  if [[ ",$2," == *,tuic,* ]]; then unexpected_mutation; else return 0; fi
}
write_test_runtime vless-reality,tuic direct ''
before="$(sha256sum "$SBD_CONFIG_DIR/runtime.env")"
if sbd_with_mutation_lock sbd_transaction_run script-update false; then fail 'injected failure did not fail'; fi
[[ ! -L "$SBD_HOST_STATE_DIR/transactions/active" && ! -e "$retired_root/unexpected" ]]
[[ "$before" == "$(sha256sum "$SBD_CONFIG_DIR/runtime.env")" ]]
sha256sum -c "$retired_root/files.sha256" >/dev/null

# Reject a retired cfg snapshot before entering the phase that restarts services.
provider_cfg_snapshot_paths_sync
mkdir -p "$SBD_CFG_SNAPSHOT_DIR"
sbd_state_capture "$SBD_CFG_SNAPSHOT_DIR/old-tuic" false
provider_warp_snapshot_lifecycle "$SBD_CFG_SNAPSHOT_DIR/old-tuic"
write_test_runtime vless-reality direct ''
before="$(sha256sum "$SBD_CONFIG_DIR/runtime.env")"
if sbd_with_mutation_lock sbd_transaction_run config-rollback provider_cfg_rollback_unlocked old-tuic; then
  fail 'retired cfg snapshot was restored'
fi
[[ ! -L "$SBD_HOST_STATE_DIR/transactions/active" && ! -e "$retired_root/unexpected" ]]
[[ "$before" == "$(sha256sum "$SBD_CONFIG_DIR/runtime.env")" ]]
sha256sum -c "$retired_root/files.sha256" >/dev/null
printf '[OK] retired protocol rejection, legacy reads, script recovery and snapshot preflight\n'
