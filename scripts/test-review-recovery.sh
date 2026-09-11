#!/usr/bin/env bash
# Case strings expand in the child bash, not in this parent shell.
# shellcheck disable=SC1091,SC2016,SC2034,SC2317
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$PROJECT_ROOT/lib/load.sh"
review_root="$(mktemp -d)"
trap 'rm -rf "$review_root"' EXIT
SBD_INSTALL_DIR="$review_root/install"
SBD_CONFIG_DIR="$review_root/config"
SBD_STATE_DIR="$review_root/state"
SBD_HOST_STATE_DIR="$review_root/control"
SBD_RUNTIME_DIR="$review_root/run"
SBD_BIN_DIR="$SBD_INSTALL_DIR/bin"
SBD_DATA_DIR="$SBD_INSTALL_DIR/data"
SBD_RULES_FILE="$SBD_STATE_DIR/firewall-rules.db"
SBD_SERVICE_FILE="$review_root/services/core"
SBD_ARGO_SERVICE_FILE="$review_root/services/argo"
SBD_FW_REPLAY_SERVICE_FILE="$review_root/services/firewall"
SBD_WARP_SOCKS_SERVICE_FILE="$review_root/services/warp"
SBD_INIT_SYSTEM="nohup"
mkdir -p "$SBD_CONFIG_DIR" "$SBD_DATA_DIR" "$SBD_STATE_DIR" "$review_root/services"
failures=0
run_case() {
  local name="$1" rc
  shift
  # A fresh shell retains errexit inside the case and never touches host services.
  if bash -euo pipefail -c "$1"; then printf '[OK] %s\n' "$name"
  else rc=$?; printf '[FAIL] %s (rc=%s)\n' "$name" "$rc" >&2; failures=$((failures + 1)); fi
}
export PROJECT_ROOT SBD_INSTALL_DIR SBD_CONFIG_DIR SBD_STATE_DIR SBD_HOST_STATE_DIR SBD_RUNTIME_DIR SBD_BIN_DIR SBD_DATA_DIR SBD_RULES_FILE SBD_SERVICE_FILE SBD_ARGO_SERVICE_FILE SBD_FW_REPLAY_SERVICE_FILE SBD_WARP_SOCKS_SERVICE_FILE SBD_INIT_SYSTEM review_root
# Export library functions without re-sourcing defaults over isolated paths.
# shellcheck disable=SC2163
while read -r _ _ function_name; do export -f "$function_name"; done < <(declare -F)
export SBD_MUTATION_DEPTH

run_case repeated_host_publish '
  dir="$review_root/repeated"
  mkdir "$dir"
  SBD_ACTIVE_TRANSACTION="$dir"
  printf "before\n" > "$dir/live"
  printf "first\n" > "$dir/candidate"
  sbd_host_file_publish "$dir/live" "$dir/candidate"
  printf "second\n" > "$dir/candidate"
  (sbd_host_file_prepare() { return 28; }; ! sbd_host_file_publish "$dir/live" "$dir/candidate")
  sbd_host_transaction_restore "$dir"
  [[ "$(cat "$dir/live")" == before ]]
'
run_case snapshot_service_ledger '
  SBD_ACTIVE_TRANSACTION=""
  printf "# Managed by sing-box-deve: service-v1\nExecStart=/old\n" > "$review_root/unit"
  sbd_host_file_publish "$SBD_ARGO_SERVICE_FILE" "$review_root/unit"
  sbd_state_capture "$review_root/snapshot" false
  printf "# Managed by sing-box-deve: service-v1\nExecStart=/new\n" > "$review_root/unit"
  sbd_host_file_publish "$SBD_ARGO_SERVICE_FILE" "$review_root/unit"
  SBD_ACTIVE_TRANSACTION="$review_root/snapshot-transaction"
  mkdir "$SBD_ACTIVE_TRANSACTION"
  sbd_state_restore "$review_root/snapshot"
  sbd_host_file_unchanged "$SBD_ARGO_SERVICE_FILE"
  sbd_host_transaction_restore "$SBD_ACTIVE_TRANSACTION"
  grep -q "ExecStart=/new" "$SBD_ARGO_SERVICE_FILE"
  sbd_host_file_unchanged "$SBD_ARGO_SERVICE_FILE"
  SBD_ACTIVE_TRANSACTION=""
  sbd_state_restore "$review_root/snapshot"
  cp "$SBD_ARGO_SERVICE_FILE" "$review_root/unit"
  sbd_host_file_publish "$SBD_ARGO_SERVICE_FILE" "$review_root/unit"
  printf "external-edit\n" > "$SBD_ARGO_SERVICE_FILE"
  printf "live-config\n" > "$SBD_CONFIG_DIR/config.json"
  if sbd_state_restore "$review_root/snapshot"; then exit 1; fi
  [[ "$(cat "$SBD_ARGO_SERVICE_FILE")" == external-edit ]]
  [[ "$(cat "$SBD_CONFIG_DIR/config.json")" == live-config ]]
'
run_case foreign_service_preflight '
  SBD_HOST_STATE_DIR="$review_root/foreign-control"
  printf "ExecStart=/foreign/service\n" > "$SBD_SERVICE_FILE"
  if sbd_transaction_begin install; then exit 1; fi
  [[ ! -e "$SBD_HOST_STATE_DIR/transactions/active" ]]
'
run_case legacy_firewall_service_ownership '
  dir="$review_root/legacy-firewall"
  mkdir -p "$dir"
  SBD_HOST_STATE_DIR="$dir/control"
  SBD_SERVICE_FILE="$dir/core"
  SBD_ARGO_SERVICE_FILE="$dir/argo"
  SBD_FW_REPLAY_SERVICE_FILE="$dir/firewall"
  SBD_WARP_SOCKS_SERVICE_FILE="$dir/warp"
  SBD_LAUNCHER_PATH="$dir/sb"
  printf "is_sbd_project_root() { :; }\n# /etc/sing-box-deve/runtime.env\n" > "$SBD_LAUNCHER_PATH"
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
  cp "$SBD_FW_REPLAY_SERVICE_FILE" "$dir/legacy"
  sbd_managed_unit_file "$SBD_FW_REPLAY_SERVICE_FILE"
  sbd_service_probe() { printf "inactive disabled\n"; }
  transaction="$(sbd_transaction_begin config-change)"
  [[ -L "$SBD_HOST_STATE_DIR/transactions/active" ]]
  cmp -s "$SBD_FW_REPLAY_SERVICE_FILE" "$dir/legacy"
  SBD_ACTIVE_TRANSACTION="$transaction"
  { printf "# Managed by sing-box-deve: service-v1\n"; cat "$dir/legacy"; } > "$dir/candidate"
  sbd_host_file_publish "$SBD_FW_REPLAY_SERVICE_FILE" "$dir/candidate"
  sbd_host_file_unchanged "$SBD_FW_REPLAY_SERVICE_FILE"
  sbd_host_transaction_restore "$transaction"
  cmp -s "$SBD_FW_REPLAY_SERVICE_FILE" "$dir/legacy"
  [[ ! -d "$(sbd_host_file_record "$SBD_FW_REPLAY_SERVICE_FILE")" ]]
  sbd_managed_unit_file "$SBD_FW_REPLAY_SERVICE_FILE"
  # Reject foreign commands, extra directives, another unit path and symlinks.
  printf "ExecStartPost=/foreign/command\n" >> "$SBD_FW_REPLAY_SERVICE_FILE"
  if sbd_managed_unit_file "$SBD_FW_REPLAY_SERVICE_FILE"; then exit 1; fi
  sed "s|^ExecStart=.*|ExecStart=/foreign/sb fw replay|" "$dir/legacy" > "$SBD_FW_REPLAY_SERVICE_FILE"
  if sbd_managed_unit_file "$SBD_FW_REPLAY_SERVICE_FILE"; then exit 1; fi
  cp "$dir/legacy" "$SBD_FW_REPLAY_SERVICE_FILE"
  cp "$dir/legacy" "$SBD_SERVICE_FILE"
  if sbd_managed_unit_file "$SBD_SERVICE_FILE"; then exit 1; fi
  mv "$SBD_FW_REPLAY_SERVICE_FILE" "$dir/real-unit"
  ln -s "$dir/real-unit" "$SBD_FW_REPLAY_SERVICE_FILE"
  if sbd_managed_unit_file "$SBD_FW_REPLAY_SERVICE_FILE"; then exit 1; fi
  rm "$SBD_FW_REPLAY_SERVICE_FILE"
  cp "$dir/legacy" "$SBD_FW_REPLAY_SERVICE_FILE"
  printf "#!/bin/sh\nexit 0\n" > "$SBD_LAUNCHER_PATH"
  if sbd_managed_unit_file "$SBD_FW_REPLAY_SERVICE_FILE"; then exit 1; fi
  printf "# Managed by sing-box-deve: launcher-v1\n" > "$SBD_LAUNCHER_PATH"
  sbd_managed_unit_file "$SBD_FW_REPLAY_SERVICE_FILE"
  # An existing ownership ledger takes priority over legacy recognition.
  sbd_host_file_prepare "$SBD_FW_REPLAY_SERVICE_FILE"
  printf "external change\n" >> "$SBD_FW_REPLAY_SERVICE_FILE"
  sbd_host_file_commit "$SBD_FW_REPLAY_SERVICE_FILE"
  cp "$dir/legacy" "$SBD_FW_REPLAY_SERVICE_FILE"
  if sbd_managed_unit_file "$SBD_FW_REPLAY_SERVICE_FILE"; then exit 1; fi
'
run_case install_warp_account_only '
  SBD_ACTIVE_TRANSACTION="$review_root/warp-transaction"
  SBD_MUTATION_DEPTH=1
  WARP_MODE=global
  WARP_PRIVATE_KEY=""
  ensure_root() { :; }
  sbd_http_small() { printf "%s\n" "{\"config\":{\"client_id\":\"AQID\",\"interface\":{\"addresses\":{\"v4\":\"172.16.0.2\",\"v6\":\"2606:4700::1\"}}}}"; }
  provider_warp_rebuild_runtime_from_account() { touch "$review_root/unexpected-runtime-rebuild"; }
  provider_vps_prepare_warp_account
  [[ -n "$WARP_PRIVATE_KEY" && "$WARP_MODE" == global ]]
  [[ ! -e "$review_root/unexpected-runtime-rebuild" ]]
  provider_warp_register_unlocked
  [[ -e "$review_root/unexpected-runtime-rebuild" ]]
'
run_case malformed_active_pointer '
  mkdir -p "$SBD_HOST_STATE_DIR/transactions"
  printf "corrupt\n" > "$SBD_HOST_STATE_DIR/transactions/active"
  if sbd_with_mutation_lock touch "$review_root/should-not-exist"; then exit 1; fi
  [[ ! -e "$review_root/should-not-exist" ]]
  rm "$SBD_HOST_STATE_DIR/transactions/active"
  ln -s "$SBD_HOST_STATE_DIR/transactions/missing" "$SBD_HOST_STATE_DIR/transactions/active"
  if sbd_with_mutation_lock touch "$review_root/should-not-exist"; then exit 1; fi
  [[ ! -e "$review_root/should-not-exist" ]]
'
run_case missing_schema_header '
  file="$review_root/runtime.env"
  printf "provider=vps\nprofile=lite\nengine=sing-box\nprotocols=vless-reality\n" > "$file"
  sbd_seal_runtime_file "$file"
  tail -n +2 "$file" > "$review_root/headerless.env"
  if sbd_load_runtime_env "$review_root/headerless.env"; then exit 1; fi
  sed "s/^runtime_schema=/ export runtime_schema=/" "$file" > "$review_root/indented.env"
  if sbd_load_runtime_env "$review_root/indented.env"; then exit 1; fi
  printf "provider=vps\nprofile=lite\nengine=sing-box\nprotocols=vless-reality\n" > "$review_root/legacy.env"
  sbd_load_runtime_env "$review_root/legacy.env"
'
(( failures == 0 ))
