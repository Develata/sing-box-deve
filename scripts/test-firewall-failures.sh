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

run_case failed_backend_is_not_recorded '
  fw_tag() { echo "MYBOX:test:core:$2:$3"; }
  fw_backend_rule_present() { return 1; }
  fw_command() { return 42; }
  fw_enable_replay_service() { touch "$review_root/unexpected-replay"; }
  for FW_BACKEND in iptables ufw nftables firewalld; do
    if fw_apply_rule tcp 443; then exit 1; fi
    [[ ! -s "$SBD_RULES_FILE" ]]
  done
  [[ ! -e "$review_root/unexpected-replay" ]]
  printf "iptables|tcp|443|MYBOX:test:core:tcp:443|date\n" > "$SBD_RULES_FILE"
  cp "$SBD_RULES_FILE" "$review_root/expected-rules"
  ! fw_replay
  cmp "$SBD_RULES_FILE" "$review_root/expected-rules"
  fw_remove_rule_by_record() { return 42; }
  ! fw_clear_managed_rules
  cmp "$SBD_RULES_FILE" "$review_root/expected-rules"
  SBD_FW_SNAPSHOT_FILE="$review_root/expected-rules"
  ! fw_rollback
  cmp "$SBD_RULES_FILE" "$review_root/expected-rules"
'
run_case failed_iptables_delete_is_finite '
  fw_command() { if [[ "$2" == -C ]]; then return 0; fi; echo delete >> "$review_root/delete-calls"; return 42; }
  started=$SECONDS
  ! fw_remove_rule_by_record iptables tcp 443 MYBOX:test:core:tcp:443
  (( SECONDS - started < 3 ))
  [[ "$(wc -l < "$review_root/delete-calls")" == 1 ]]
  # Even a lying backend reporting successful deletion cannot spin forever.
  fw_command() { return 0; }
  SBD_FIREWALL_TIMEOUT=1
  ! fw_remove_rule_by_record iptables tcp 443 MYBOX:test:core:tcp:443
  (( SECONDS - started < 4 ))
'
run_case firewall_command_deadline '
  SBD_FIREWALL_TIMEOUT=1
  started=$SECONDS
  if fw_command sleep 20; then exit 1; else rc=$?; fi
  [[ "$rc" == 124 ]]
  (( SECONDS - started < 5 ))
'
run_case partial_firewalld_recovers_from_intent '
  FW_BACKEND=firewalld
  SBD_ACTIVE_TRANSACTION="$review_root/firewall-tx"
  mkdir "$SBD_ACTIVE_TRANSACTION"
  : > "$SBD_RULES_FILE"
  fw_tag() { echo "MYBOX:test:core:$2:$3"; }
  fw_command() {
    local scope=runtime
    [[ "$*" != *--permanent* ]] || scope=permanent
    case "$*" in
      *--query-port=*) [[ -f "$review_root/$scope-rule" ]] ;;
      *--add-port=*) [[ "$scope" == permanent ]] || return 42; touch "$review_root/$scope-rule" ;;
      *--remove-port=*) rm "$review_root/$scope-rule" ;;
      *) return 42 ;;
    esac
  }
  ! fw_apply_rule tcp 443
  [[ -f "$review_root/permanent-rule" && ! -s "$SBD_RULES_FILE" ]]
  grep -q "firewalld|tcp|443|MYBOX:test:core:tcp:443|pending" "$SBD_ACTIVE_TRANSACTION/firewall-pending"
  sbd_transaction_restore_firewall "$SBD_ACTIVE_TRANSACTION"
  [[ ! -f "$review_root/permanent-rule" ]]
  # A preexisting permanent-only user rule must never be adopted or removed.
  touch "$review_root/permanent-rule"
  cp "$SBD_ACTIVE_TRANSACTION/firewall-pending" "$review_root/intent-before"
  fw_apply_rule tcp 443
  cmp "$SBD_ACTIVE_TRANSACTION/firewall-pending" "$review_root/intent-before"
  [[ -f "$review_root/permanent-rule" && ! -s "$SBD_RULES_FILE" ]]
'
run_case record_or_replay_failure_is_visible '
  FW_BACKEND=iptables SBD_RULES_FILE="$review_root/no-records"
  fw_tag() { echo "MYBOX:test:core:$2:$3"; }
  fw_apply_rule_to_backend() { :; }
  fw_record_rule() { return 42; }
  ! fw_apply_rule tcp 443
  fw_record_rule() { :; }
  fw_enable_replay_service() { return 43; }
  ! fw_apply_rule tcp 443
'
run_case nft_query_error_does_not_erase_ownership '
  printf "nftables|tcp|443|MYBOX:test:core:tcp:443|date\n" > "$SBD_RULES_FILE"
  fw_command() { return 1; }
  if fw_backend_rule_present nftables tcp 443 MYBOX:test:core:tcp:443; then exit 1; else [[ "$?" == 2 ]]; fi
  ! fw_clear_managed_rules
  [[ -s "$SBD_RULES_FILE" ]]
  # Successfully listing no tables is different from a failed query.
  fw_command() { [[ "$*" == "nft list tables" ]]; }
  fw_clear_managed_rules
  [[ ! -s "$SBD_RULES_FILE" ]]
'
(( failures == 0 ))
