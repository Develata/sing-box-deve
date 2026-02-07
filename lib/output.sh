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
Argo     : ${ARGO_MODE:-off}
WARP     : ${WARP_MODE:-off}
Route    : ${ROUTE_MODE:-direct}
Egress   : ${OUTBOUND_PROXY_MODE:-direct}

$(if [[ "${OUTBOUND_PROXY_MODE:-direct}" != "direct" ]]; then echo "Outbound Proxy: ${OUTBOUND_PROXY_MODE}://${OUTBOUND_PROXY_HOST:-}:${OUTBOUND_PROXY_PORT:-}"; fi)

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
Argo     : ${ARGO_MODE:-off}
WARP     : ${WARP_MODE:-off}
Route    : ${ROUTE_MODE:-direct}
Egress   : ${OUTBOUND_PROXY_MODE:-direct}

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

  print_nodes_with_qr
}

print_nodes_with_qr() {
  if [[ ! -f "$SBD_NODES_FILE" ]]; then
    log_warn "Nodes file not found: $SBD_NODES_FILE"
    return 0
  fi

  echo
  echo "Node Links"
  echo "----------"
  cat "$SBD_NODES_FILE"

  if [[ -f "$SBD_SUB_FILE" ]]; then
    echo
    echo "Aggregate Subscription (Base64)"
    echo "-------------------------------"
    cat "$SBD_SUB_FILE"
  fi

  if ! command -v qrencode >/dev/null 2>&1; then
    log_warn "qrencode not installed; skipping QR output"
    return 0
  fi

  echo
  echo "QR Codes"
  echo "--------"
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    case "$line" in
      vless://*|vmess://*|hysteria2://*|trojan://*|anytls://*|wireguard://*)
        printf '%s\n' "$line"
        qrencode -o - -t ANSIUTF8 "$line"
        echo
        ;;
    esac
  done < "$SBD_NODES_FILE"

  if [[ -f "$SBD_SUB_FILE" ]]; then
    echo "aggregate-base64://$(cat "$SBD_SUB_FILE")"
    qrencode -o - -t ANSIUTF8 "aggregate-base64://$(cat "$SBD_SUB_FILE")"
    echo
  fi
}
