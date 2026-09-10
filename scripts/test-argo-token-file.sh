#!/usr/bin/env bash
# shellcheck disable=SC2034
# shellcheck disable=SC1090,SC1091
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="$root_dir"
source "$PROJECT_ROOT/lib/load.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT INT TERM HUP
SBD_HOST_STATE_DIR="$tmp_dir/control"
SBD_STATE_DIR="$tmp_dir/state"
SBD_INSTALL_DIR="$tmp_dir/install"
SBD_BIN_DIR="${tmp_dir}/bin"
SBD_DATA_DIR="${tmp_dir}/data"
SBD_CONFIG_DIR="${tmp_dir}/config"
SBD_RUNTIME_DIR="${tmp_dir}/run"
SBD_ARGO_TOKEN_FILE="${SBD_DATA_DIR}/argo-token"
SBD_ARGO_EXEC_FILE="${SBD_DATA_DIR}/argo-exec"
SBD_ARGO_SERVICE_FILE="${tmp_dir}/sing-box-deve-argo.service"
export SBD_CONFIG_DIR SBD_RUNTIME_DIR SBD_ARGO_TOKEN_FILE SBD_ARGO_EXEC_FILE SBD_ARGO_SERVICE_FILE
mkdir -p "$SBD_CONFIG_DIR" "$SBD_RUNTIME_DIR"
token='eyJhIjoi-secret-test-token'

argo_write_token_file "$token"
cmd="$(argo_fixed_exec_command)"
[[ "$(<"$SBD_ARGO_TOKEN_FILE")" == "$token" ]] || die "token file content mismatch"
[[ "$(stat -c %a "$SBD_ARGO_TOKEN_FILE")" == "600" ]] || die "token file mode is not 0600"
[[ "$cmd" == *"--token-file ${SBD_ARGO_TOKEN_FILE}"* ]] || die "token-file flag missing"
[[ "$cmd" != *"$token"* ]] || die "token leaked into process argv"

install_cloudflared_binary() { mkdir -p "$SBD_BIN_DIR"; }
resolve_protocol_port_for_engine() { printf '8444\n'; }
sbd_service_enable_and_start() { captured_exec="$2"; }
captured_exec=""
ARGO_MODE=fixed
ARGO_TOKEN="$token"
ARGO_DOMAIN=argo.example.com
export ARGO_MODE ARGO_TOKEN ARGO_DOMAIN
argo_write_token_file 'stale-token'
configure_argo_tunnel vless-ws sing-box
[[ "$(<"$SBD_ARGO_TOKEN_FILE")" == "$token" ]] || die "fixed tunnel token was not refreshed"
grep -Fq -- "--token-file ${SBD_ARGO_TOKEN_FILE}" "$SBD_ARGO_SERVICE_FILE" || die "unit does not use token-file"
if grep -Fq -- "$token" "$SBD_ARGO_SERVICE_FILE"; then die "token leaked into systemd unit"; fi
[[ "$captured_exec" != *"$token"* ]] || die "token leaked into service argv"
if grep -Eq -- '--token([[:space:]]|$)' "${root_dir}/scripts/serv00keep.sh"; then
  die "Serv00 keepalive still places tunnel token in argv"
fi

# An installation created before argo-exec existed must be migratable on the
# first nohup restart, without putting the fixed tunnel token back in argv.
rm -f "$SBD_ARGO_EXEC_FILE" "$SBD_ARGO_TOKEN_FILE"
{
  sbd_write_env_kv provider vps
  sbd_write_env_kv profile lite
  sbd_write_env_kv engine sing-box
  sbd_write_env_kv protocols vless-ws
  sbd_write_env_kv argo_mode fixed
  sbd_write_env_kv argo_token "$token"
} > "${SBD_CONFIG_DIR}/runtime.env"
: > "$SBD_ARGO_SERVICE_FILE"
SBD_INIT_SYSTEM="nohup"
captured_restart_exec=""
sbd_service_restart() { printf '%s\n' "$2" > "$tmp_dir/captured-restart"; }
sbd_service_wait_active() { return 0; }
provider_restart argo
captured_restart_exec="$(cat "$tmp_dir/captured-restart")"
[[ -s "$SBD_ARGO_EXEC_FILE" ]] || die "legacy nohup restart did not create argo-exec"
[[ "$(stat -c %a "$SBD_ARGO_EXEC_FILE")" == "600" ]] || die "migrated argo-exec mode is not 0600"
[[ -s "$SBD_ARGO_TOKEN_FILE" ]] || die "legacy fixed token was not migrated"
[[ "$captured_restart_exec" == *"--token-file ${SBD_ARGO_TOKEN_FILE}"* ]] || \
  die "legacy fixed restart did not use token-file"
[[ "$captured_restart_exec" != *"$token"* ]] || die "legacy fixed token leaked into restart argv"

# The temporary-tunnel command is reconstructed from runtime protocol state.
rm -f "$SBD_ARGO_EXEC_FILE" "$SBD_ARGO_TOKEN_FILE"
{
  sbd_write_env_kv provider vps
  sbd_write_env_kv profile lite
  sbd_write_env_kv engine sing-box
  sbd_write_env_kv protocols vless-ws
  sbd_write_env_kv argo_mode temp
  sbd_write_env_kv argo_token ""
} > "${SBD_CONFIG_DIR}/runtime.env"
resolve_protocol_port_for_engine() { printf '8444\n'; }
captured_restart_exec=""
provider_restart argo
captured_restart_exec="$(cat "$tmp_dir/captured-restart")"
[[ "$captured_restart_exec" == *"--url http://127.0.0.1:8444"* ]] || \
  die "legacy temp restart did not reconstruct the vless-ws target"

printf '[OK] Argo token-file checks passed\n'
