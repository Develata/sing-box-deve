#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="$ROOT_DIR"

source "${PROJECT_ROOT}/lib/common.sh"
source "${PROJECT_ROOT}/lib/providers_clash_rulesets.sh"
source "${PROJECT_ROOT}/lib/providers_client_templates.sh"

TEST_ROOT="$(mktemp -d /tmp/sbd-clash-test-XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT

SBD_INSTALL_DIR="${TEST_ROOT}/install"
SBD_DATA_DIR="${SBD_INSTALL_DIR}/data"
SBD_CONFIG_DIR="${TEST_ROOT}/etc"
SBD_NODES_FILE="${SBD_DATA_DIR}/nodes.txt"
SBD_SUB_FILE="${SBD_DATA_DIR}/nodes-sub.txt"

mkdir -p "$SBD_DATA_DIR" "$SBD_CONFIG_DIR"
cat > "$SBD_NODES_FILE" <<'EOF'
vless://11111111-1111-1111-1111-111111111111@example.com:443?encryption=none&security=reality&type=tcp#demo-node
EOF
base64 -w 0 < "$SBD_NODES_FILE" > "$SBD_SUB_FILE"

cat > "${SBD_CONFIG_DIR}/clash_custom_rules.list" <<'EOF'
# custom rules
DOMAIN-SUFFIX,openai.com,PROXY
IP-CIDR,1.1.1.1/32,PROXY,no-resolve
EOF

ensure_clash_rulesets_local
out_file="${SBD_DATA_DIR}/clash_meta_client.yaml"
render_clash_meta_yaml "$out_file"

[[ -s "$out_file" ]] || { echo "[ERROR] clash yaml not generated"; exit 1; }
[[ -s "${SBD_DATA_DIR}/clash-ruleset/geosite-cn.yaml" ]] || { echo "[ERROR] missing geosite-cn.yaml"; exit 1; }
[[ -s "${SBD_DATA_DIR}/clash-ruleset/geoip-cn.yaml" ]] || { echo "[ERROR] missing geoip-cn.yaml"; exit 1; }

grep -q '^rule-providers:' "$out_file"
grep -q 'RULE-SET,geosite-cn,DIRECT' "$out_file"
grep -q 'RULE-SET,geoip-cn,DIRECT,no-resolve' "$out_file"
grep -q 'DOMAIN-SUFFIX,openai.com,PROXY' "$out_file"
grep -q 'IP-CIDR,1.1.1.1/32,PROXY,no-resolve' "$out_file"
grep -q 'MATCH,PROXY' "$out_file"

custom_rule_line="$(grep -n 'DOMAIN-SUFFIX,openai.com,PROXY' "$out_file" | head -n1 | cut -d: -f1)"
match_line="$(grep -n 'MATCH,PROXY' "$out_file" | head -n1 | cut -d: -f1)"
[[ -n "$custom_rule_line" && -n "$match_line" ]] || {
  echo "[ERROR] cannot verify custom rules order"
  exit 1
}
[[ "$custom_rule_line" -lt "$match_line" ]] || {
  echo "[ERROR] custom rules must appear before MATCH,PROXY"
  exit 1
}

echo "[OK] clash ruleset generation checks passed"
