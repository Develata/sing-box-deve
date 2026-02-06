#!/usr/bin/env bash

print_plan_summary() {
  local provider="$1"
  local profile="$2"
  local engine="$3"
  local protocols_csv="$4"

  cat <<EOF

Execution Plan
--------------
Provider : ${provider}
Profile  : ${profile}
Engine   : ${engine}
Protocols: ${protocols_csv}

Safety
------
- Incremental firewall rules only
- Firewall rollback snapshot enabled
- No firewall disable/flush actions

EOF
}

print_post_install_info() {
  local provider="$1"
  local profile="$2"
  local engine="$3"
  local protocols_csv="$4"

  cat <<EOF

Installed
---------
Provider : ${provider}
Profile  : ${profile}
Engine   : ${engine}
Protocols: ${protocols_csv}

Generated Files
---------------
- ${CONFIG_SNAPSHOT_FILE}
- ${SBD_CONTEXT_FILE}
- ${SBD_RULES_FILE}

Next Commands
-------------
- ./sing-box-deve.sh list
- ./sing-box-deve.sh doctor
- ./sing-box-deve.sh fw status

EOF
}
