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

run_case restart_failure_rolls_back '
  ensure_root() { :; }
  sbd_service_probe() { if [[ "$1" == sing-box-deve ]]; then echo "active disabled"; else echo "inactive disabled"; fi; }
  crontab() { return 1; }
  detect_init_system() { SBD_INIT_SYSTEM=nohup; }
  sbd_service_stop() { :; }
  sbd_service_daemon_reload() { :; }
  write_nodes_output() { :; }
  printf "# Managed by sing-box-deve: service-v1\n" > "$SBD_SERVICE_FILE"
  printf "old\n" > "$SBD_CONFIG_DIR/config.json"
  sbd_service_restart() { [[ "$(cat "$SBD_CONFIG_DIR/config.json")" == old ]]; }
  sbd_service_wait_active() { :; }
  change_restart() { printf "new\n" > "$SBD_CONFIG_DIR/config.json"; provider_restart core || return 1; }
  if sbd_with_mutation_lock sbd_transaction_run config-change change_restart; then exit 1; fi
  [[ "$(cat "$SBD_CONFIG_DIR/config.json")" == old ]]
  [[ ! -L "$SBD_HOST_STATE_DIR/transactions/active" ]]
  grep -q recovered "$SBD_HOST_STATE_DIR"/transactions/config-change.*/phase
'
run_case failed_preparation_is_discarded '
  SBD_HOST_STATE_DIR="$review_root/preparation"
  mkdir -p "$SBD_BIN_DIR"
  printf "binary\n" > "$SBD_BIN_DIR/sing-box"
  sbd_service_probe() { return 42; }
  crontab() { return 1; }
  for n in 1 2 3; do if sbd_transaction_begin core-update; then exit 1; fi; done
  [[ -z "$(find "$SBD_HOST_STATE_DIR/transactions" -mindepth 1 -print -quit)" ]]
'
run_case cron_service_names_are_exact '
  cron_file="$review_root/crontab"
  printf "@reboot core # sbd:sing-box-deve\n@reboot argo # sbd:sing-box-deve-argo\n@reboot warp # sbd:sing-box-deve-warp-socks5\n@reboot other # other\n" > "$cron_file"
  crontab() { case "$1" in -l) cat "$cron_file" ;; -) cat > "$cron_file" ;; esac; }
  nohup_register_crontab sing-box-deve "/bin/sleep 60" "$review_root/core.log"
  [[ "$(wc -l < "$cron_file")" == 4 ]]
  nohup_remove_crontab sing-box-deve
  [[ "$(wc -l < "$cron_file")" == 3 ]]
  grep -q "# sbd:sing-box-deve-argo$" "$cron_file"
  grep -q "# sbd:sing-box-deve-warp-socks5$" "$cron_file"
  detect_init_system() { SBD_INIT_SYSTEM=nohup; }
  ! sbd_service_unit_exists sing-box-deve
  ! sbd_service_is_enabled sing-box-deve
  [[ "$(sbd_service_probe sing-box-deve)" == "inactive disabled" ]]
'
run_case warp_domain_overrides_and_xray_default '
  ROUTE_MODE=direct WARP_MODE=global OUTBOUND_PROXY_MODE=direct
  DOMAIN_SPLIT_DIRECT=direct.example DOMAIN_SPLIT_PROXY=proxy.example DOMAIN_SPLIT_BLOCK=block.example
  for WARP_MODE in global s4 s6; do
    build_singbox_route_json warp-out | jq -e ".rules[0].domain_suffix == [\"direct.example\"] and .rules[1].outbound == \"warp-out\" and .rules[2].action == \"reject\""
  done
  for WARP_MODE in global x x4 x6; do
    route="$(build_xray_routing_fragment warp-out)"
    printf "{\"dummy\":0%s}" "$route" | jq -e ".routing.rules[-1].outboundTag == \"warp-out\" and .routing.rules[2].domain == [\"domain:block.example\"]"
  done
'
run_case runtime_apply_forwards_fixed_argo '
  ensure_root() { :; }
  printf "provider=vps\nprofile=lite\nengine=sing-box\nprotocols=vless-ws\nscript_root=/isolated/source\ninstalled_at=2026-09-12\nargo_mode=fixed\nargo_token=SYNTHETIC-TOKEN\nargo_domain=tunnel.example.invalid\n" > "$SBD_CONFIG_DIR/runtime.env"
  ARGO_TOKEN="" ARGO_DOMAIN=""
  run_install() { [[ "$ARGO_MODE" == fixed && "$ARGO_TOKEN" == SYNTHETIC-TOKEN && "$ARGO_DOMAIN" == tunnel.example.invalid ]]; }
  apply_runtime_unlocked
'
run_case redact_share_uri '
  ensure_root() { :; }
  printf "outbound_proxy_link=hy2://SYNTHETIC-SECRET@example.invalid:443\n" > "$SBD_CONFIG_DIR/runtime.env"
  output="$(provider_list runtime)"
  [[ "$output" != *SYNTHETIC-SECRET* && "$output" == *redacted* ]]
'
run_case hy2_extra_endpoint '
  line="$(rewrite_link_with_endpoint "hysteria2://pass@example.invalid:8443?sni=test#label" "203.0.113.1:9000")"
  [[ "$line" == "hysteria2://pass@203.0.113.1:9000?sni=test#label" ]]
'
run_case ss2022_dual_transport '
  [[ "$(protocol_transports shadowsocks-2022)" == "tcp udp" ]]
  ss() { if [[ "$*" == "-H -lnu" ]]; then echo "UNCONN 0 0 127.0.0.1:2443 0.0.0.0:*"; fi; }
  sbd_port_is_in_use "$(protocol_transports shadowsocks-2022)" 2443
  fw_apply_rule() { echo "$1/$2" >> "$review_root/applied"; }
  fw_apply_protocol_rule shadowsocks-2022 2443
  [[ "$(cat "$review_root/applied")" == $'"'"'tcp/2443\nudp/2443'"'"' ]]
  printf "iptables|tcp|2443|MYBOX:old:core:tcp:2443|date\nnftables|udp|2443|MYBOX:old:core:udp:2443|date\niptables|tcp|24430|MYBOX:old:core:tcp:24430|date\n" > "$SBD_RULES_FILE"
  records="$(fw_records_for_protocol_endpoint "" shadowsocks-2022 2443)"
  [[ "$(wc -l <<< "$records")" == 2 ]]
  fw_remove_rule_by_record() { echo "$2/$3" >> "$review_root/removed"; }
  provider_multi_ports_remove_firewall shadowsocks-2022 2443
  [[ "$(cat "$review_root/removed")" == $'"'"'tcp/2443\nudp/2443'"'"' ]]
  [[ "$(wc -l < "$SBD_RULES_FILE")" == 1 ]]
'
run_case user_mode_share_paths '
  init_user_mode_paths
  [[ "$SBD_SHARE_RAW_FILE" == "$SBD_DATA_DIR/jhdy.txt" ]]
  [[ "$SBD_SHARE_BASE64_FILE" == "$SBD_DATA_DIR/jh_sub.txt" ]]
  [[ "$SBD_SHARE_GROUP_DIR" == "$SBD_DATA_DIR/share-groups" ]]
'
run_case regen_nodes_obeys_lock '
  ensure_root() { :; }
  printf "provider=vps\nprofile=lite\nengine=sing-box\nprotocols=vless-reality\n" > "$SBD_CONFIG_DIR/runtime.env"
  SBD_NODES_FILE="$SBD_DATA_DIR/nodes.txt"
  write_nodes_output() { touch "$review_root/nodes-written"; }
  mkdir -p "$SBD_STATE_DIR"
  mkdir -p "$SBD_HOST_STATE_DIR"
  lock="$SBD_HOST_STATE_DIR/mutation.lock"
  exec 8> "$lock"
  flock -x 8
  SBD_LOCK_TIMEOUT=0
  if provider_regen_nodes; then exit 1; fi
  [[ ! -e "$review_root/nodes-written" ]]
  flock -u 8
  provider_regen_nodes
  [[ -e "$review_root/nodes-written" ]]
'
run_case xray_asset_snapshot '
  SBD_ACTIVE_TRANSACTION=""
  for asset in geoip.dat geosite.dat; do printf "old-%s\n" "$asset" > "$SBD_BIN_DIR/$asset"; done
  sbd_state_capture "$review_root/assets" true
  for asset in geoip.dat geosite.dat; do printf "new\n" > "$SBD_BIN_DIR/$asset"; done
  sbd_state_restore "$review_root/assets"
  [[ "$(cat "$SBD_BIN_DIR/geoip.dat")" == old-geoip.dat ]]
  [[ "$(cat "$SBD_BIN_DIR/geosite.dat")" == old-geosite.dat ]]
'
run_case warp_snapshot_lifecycle '
  dir="$review_root/warp-snapshot"
  mkdir "$dir"
  printf "4\n" > "$dir/schema"
  sbd_service_probe() { echo "active disabled"; }
  crontab() { return 1; }
  provider_warp_snapshot_lifecycle "$dir"
  provider_warp_snapshot_verify "$dir"
  printf "{\"inbounds\":[{\"listen_port\":40000}]}\n" > "$SBD_CONFIG_DIR/warp-socks5.json"
  sbd_service_daemon_reload() { SBD_INIT_SYSTEM=nohup; }
  sbd_service_restart() { [[ "$1" == sing-box-deve-warp-socks5 ]]; jq -e ".inbounds[0].listen_port == 40000" "$SBD_CONFIG_DIR/warp-socks5.json"; touch "$review_root/warp-restarted"; }
  sbd_service_wait_active() { :; }
  provider_warp_snapshot_restore "$dir" "inactive enabled"
  [[ -e "$review_root/warp-restarted" ]]
  sbd_service_probe() { echo "inactive disabled"; }
  provider_warp_snapshot_lifecycle "$dir"
  rm "$review_root/warp-restarted"
  provider_warp_snapshot_restore "$dir" "active enabled"
  [[ ! -e "$review_root/warp-restarted" ]]
  printf "active enabled\n" > "$dir/warp-lifecycle"
  ! provider_warp_snapshot_verify "$dir"
'
run_case ws_port_retargets_temporary_argo '
  ensure_root() { :; }
  AUTO_YES=true
  printf "provider=vps\nprofile=full\nengine=sing-box\nprotocols=vless-ws\nargo_mode=temp\n" > "$SBD_CONFIG_DIR/runtime.env"
  printf "{\"inbounds\":[{\"type\":\"vless\",\"tag\":\"vless-ws\",\"listen_port\":8444}]}\n" > "$SBD_CONFIG_DIR/config.json"
  validate_generated_config() { :; }
  fw_detect_backend() { FW_BACKEND=iptables; }
  load_install_context() { :; }
  fw_records_for_endpoint() { :; }
  fw_apply_rule() { :; }
  provider_multi_ports_reject_conflict() { :; }
  provider_restart() { :; }
  write_nodes_output() { :; }
  configure_argo_tunnel() { config_port_for_tag sing-box vless-ws > "$review_root/argo-target"; }
  persist_runtime_state() { touch "$review_root/runtime-persisted"; }
  provider_set_port_unlocked vless-ws 9444
  [[ "$(cat "$review_root/argo-target")" == 9444 ]]
  [[ -e "$review_root/runtime-persisted" ]]
'
run_case cfg_rollback_reconciles_warp_process '
  SBD_ARGO_TOKEN_FILE="$SBD_DATA_DIR/argo-token"
  SBD_ARGO_EXEC_FILE="$SBD_DATA_DIR/argo-exec"
  ensure_root() { :; }
  sbd_service_probe() { echo "active disabled"; }
  crontab() { return 1; }
  printf "provider=vps\nprofile=lite\nengine=sing-box\nprotocols=vless-reality\nargo_mode=off\n" > "$SBD_CONFIG_DIR/runtime.env"
  sbd_write_env_kv script_root "$PROJECT_ROOT" >> "$SBD_CONFIG_DIR/runtime.env"
  printf "# Managed by sing-box-deve: service-v1\n" > "$SBD_WARP_SOCKS_SERVICE_FILE"
  printf "{\"port\":40000}\n" > "$SBD_CONFIG_DIR/warp-socks5.json"
  printf "40000\n" > "$SBD_DATA_DIR/warp-socks5-port"
  id="$(provider_cfg_snapshot_create test)"
  printf "{\"port\":40001}\n" > "$SBD_CONFIG_DIR/warp-socks5.json"
  printf "40001\n" > "$SBD_DATA_DIR/warp-socks5-port"
  running_port=40001
  sbd_service_stop() { [[ "$1" != sing-box-deve-warp-socks5 ]] || running_port=stopped; }
  sbd_service_restart() {
    [[ "$1" == sing-box-deve-warp-socks5 && "$running_port" == stopped ]]
    running_port="$(jq -r .port "$SBD_CONFIG_DIR/warp-socks5.json")"
  }
  sbd_service_daemon_reload() { SBD_INIT_SYSTEM=nohup; }
  sbd_service_wait_active() { :; }
  provider_cfg_rebuild_runtime() { :; }
  persist_runtime_state() { :; }
  write_nodes_output() { :; }
  SBD_ACTIVE_TRANSACTION="$review_root/cfg-rollback"
  mkdir "$SBD_ACTIVE_TRANSACTION"
  provider_cfg_rollback_unlocked "$id"
  [[ "$running_port" == 40000 && "$(cat "$SBD_DATA_DIR/warp-socks5-port")" == 40000 ]]
'
(( failures == 0 ))
