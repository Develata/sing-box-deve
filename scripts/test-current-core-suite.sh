#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
core_dir="$(mktemp -d)"
trap 'rm -rf "$core_dir"' EXIT INT TERM HUP

bash "${root_dir}/scripts/download-current-cores.sh" "$core_dir"
source "${core_dir}/core-test.env"
export SBD_TEST_SINGBOX_BIN SBD_TEST_XRAY_BIN

bash "${root_dir}/scripts/test-egress-udp.sh"
bash "${root_dir}/scripts/test-egress-protocols.sh"
python3 "${root_dir}/scripts/test-egress-traffic.py"
bash "${root_dir}/scripts/test-client-artifacts.sh"
bash "${root_dir}/scripts/test-current-core-configs.sh"

printf '[OK] current stable core suite passed\n'
