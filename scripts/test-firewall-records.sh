#!/usr/bin/env bash
# shellcheck disable=SC2034,SC1091
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT

SBD_RULES_FILE="${tmp_dir}/firewall-rules.db"
SBD_FW_SNAPSHOT_FILE="${tmp_dir}/firewall.snapshot"
SBD_FW_REPLAY_SERVICE_FILE="${tmp_dir}/fw-replay.service"
FW_BACKEND="iptables"
install_id="new"

msg() { printf '%s' "$1"; }
die() { echo "[ERROR] $*" >&2; exit 1; }
log_info() { printf '%s\n' "$*"; }
log_warn() { printf '%s\n' "$*"; }
log_success() { printf '%s\n' "$*"; }
detect_init_system() { SBD_INIT_SYSTEM="none"; }
sbd_service_enable_oneshot() { :; }
load_install_context() { : "${install_id:=new}"; return 0; }

# shellcheck source=../lib/security.sh
source "${PROJECT_ROOT}/lib/security.sh"

FW_BACKEND="iptables"
declare -A BACKEND_RULES=()
APPLIED_COUNT=0

fw_backend_rule_present() {
  local _backend="$1" _proto="$2" _port="$3" tag="$4"
  [[ -n "${BACKEND_RULES[$tag]:-}" ]]
}

fw_apply_rule_to_backend() {
  local _backend="$1" _proto="$2" _port="$3" tag="$4"
  APPLIED_COUNT=$((APPLIED_COUNT + 1))
  BACKEND_RULES["$tag"]=1
}

fw_enable_replay_service() { :; }
fw_detect_backend_optional() {
  [[ "${SBD_FW_BACKEND:-iptables}" == "none" ]] && return 1
  FW_BACKEND="${SBD_FW_BACKEND:-iptables}"
  return 0
}

assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "[FAIL] ${label}: expected=${expected} actual=${actual}" >&2
    exit 1
  fi
}

assert_file_lines() {
  local expected="$1" file="$2" label="$3" actual
  actual="$(awk 'END{print NR+0}' "$file" 2>/dev/null || echo 0)"
  assert_eq "$expected" "$actual" "$label"
}

# New endpoint: apply once and record once.
install_id="new"
fw_apply_rule tcp 443
assert_eq "1" "$APPLIED_COUNT" "new endpoint applies once"
assert_file_lines 1 "$SBD_RULES_FILE" "new endpoint records once"
new_tag="MYBOX:new:core:tcp:443"
grep -Fq "|${new_tag}|" "$SBD_RULES_FILE"

# Same install_id + backend present: idempotent no-op.
fw_apply_rule tcp 443
assert_eq "1" "$APPLIED_COUNT" "tracked endpoint with backend present does not reapply"
assert_file_lines 1 "$SBD_RULES_FILE" "tracked endpoint does not duplicate record"

# Same record but backend missing: self-heals without duplicating.
unset 'BACKEND_RULES[MYBOX:new:core:tcp:443]'
fw_apply_rule tcp 443
assert_eq "2" "$APPLIED_COUNT" "tracked endpoint missing in backend is replayed"
assert_file_lines 1 "$SBD_RULES_FILE" "self-heal does not duplicate record"
[[ -n "${BACKEND_RULES[MYBOX:new:core:tcp:443]:-}" ]]

# Old install_id record for the same endpoint prevents duplicate rules after reinstall.
install_id="old"
old_tag="$(fw_tag core tcp 8443)"
fw_record_rule iptables tcp 8443 "$old_tag"
BACKEND_RULES["$old_tag"]=1
before_count="$APPLIED_COUNT"
install_id="newer"
fw_apply_rule tcp 8443
assert_eq "$before_count" "$APPLIED_COUNT" "old install_id endpoint with backend present is not duplicated"
assert_file_lines 2 "$SBD_RULES_FILE" "old install_id endpoint keeps one record"
grep -Fq "|${old_tag}|" "$SBD_RULES_FILE"
if grep -Fq "|MYBOX:newer:core:tcp:8443|" "$SBD_RULES_FILE"; then
  echo "[FAIL] newer install_id duplicated endpoint record" >&2
  exit 1
fi

# Old install_id record with missing backend self-heals using the old tracked tag.
unset "BACKEND_RULES[$old_tag]"
fw_apply_rule tcp 8443
assert_eq "$((before_count + 1))" "$APPLIED_COUNT" "old install_id endpoint missing in backend is replayed"
assert_file_lines 2 "$SBD_RULES_FILE" "old install_id self-heal does not duplicate record"
[[ -n "${BACKEND_RULES[$old_tag]:-}" ]]

# Direct record replacement by endpoint removes stale install_id records.
replacement_tag="MYBOX:replacement:core:tcp:8443"
fw_record_rule iptables tcp 8443 "$replacement_tag"
assert_file_lines 2 "$SBD_RULES_FILE" "record replacement keeps endpoint unique"
grep -Fq "|${replacement_tag}|" "$SBD_RULES_FILE"
if grep -Fq "|${old_tag}|" "$SBD_RULES_FILE"; then
  echo "[FAIL] stale old install_id record survived replacement" >&2
  exit 1
fi

# Endpoint enumeration returns every historical record for the same endpoint.
fw_record_rule iptables tcp 9443 "MYBOX:hist1:core:tcp:9443"
printf '%s|%s|%s|%s|%s\n' iptables tcp 9443 "MYBOX:hist2:core:tcp:9443" now >> "$SBD_RULES_FILE"
enum_count="$(fw_records_for_endpoint iptables tcp 9443 core | wc -l | tr -d ' ')"
assert_eq "2" "$enum_count" "endpoint enumeration includes duplicate historical records"

# Web front can use its own service tag for TCP 80/443 ownership.
install_id="web"
fw_apply_rule tcp 80 web-front
web_tag="MYBOX:web:web-front:tcp:80"
grep -Fq "|${web_tag}|" "$SBD_RULES_FILE"

# Status must be useful even when no backend can be detected.
SBD_FW_BACKEND="none"
fw_status > "${tmp_dir}/status.out"
grep -Fq "backend=iptables proto=tcp port=443" "${tmp_dir}/status.out"
grep -Fq "backend=iptables proto=tcp port=80" "${tmp_dir}/status.out"
grep -Fq "跳过后端存在性检查" "${tmp_dir}/status.out"

# Full uninstall should also remove legacy direct INPUT ACCEPT rules for
# current core ports that older versions may have written before the
# managed SING_BOX_DEVE_INPUT chain existed.
declare -A LEGACY_RULES=([tcp:9443]=1 [udp:9443]=1 [tcp:80]=1)
iptables() {
  local action="${1:-}" chain="${2:-}" proto="" port=""
  shift 2 || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p) proto="$2"; shift 2 ;;
      --dport) port="$2"; shift 2 ;;
      -j) shift 2 ;;
      *) shift ;;
    esac
  done
  [[ "$chain" == "INPUT" && -n "$proto" && -n "$port" ]] || return 1
  case "$action" in
    -C) [[ -n "${LEGACY_RULES[${proto}:${port}]:-}" ]] ;;
    -D) unset "LEGACY_RULES[${proto}:${port}]" ;;
    *) return 1 ;;
  esac
}
SBD_FW_BACKEND="iptables"
fw_clear_legacy_iptables_core_rules
[[ -z "${LEGACY_RULES[tcp:9443]:-}" ]]
[[ -z "${LEGACY_RULES[udp:9443]:-}" ]]
[[ -n "${LEGACY_RULES[tcp:80]:-}" ]]

echo "[OK] firewall record/idempotency tests passed"
