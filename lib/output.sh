#!/usr/bin/env bash

print_plan_summary() {
  local provider="$1"
  local profile="$2"
  local engine="$3"
  local protocols_csv="$4"

  printf '\n%s\n%s\n' "$(msg "执行计划" "Execution Plan")" "--------------"
  printf '%s\n' "$(msg "场景" "Provider") : ${provider}"
  printf '%s\n' "$(msg "规格" "Profile")  : ${profile}"
  printf '%s\n' "$(msg "内核" "Engine")   : ${engine}"
  printf '%s\n' "$(msg "协议" "Protocols"): ${protocols_csv}"
  printf '%s\n' "Argo     : ${ARGO_MODE:-off}"
  printf '%s\n' "WARP     : ${WARP_MODE:-off}"
  printf '%s\n' "$(msg "路由" "Route")    : ${ROUTE_MODE:-direct}"
  printf '%s\n' "$(msg "出站" "Egress")   : ${OUTBOUND_PROXY_MODE:-direct}"
  if [[ "${OUTBOUND_PROXY_MODE:-direct}" != "direct" ]]; then
    printf '%s\n' "$(msg "上游代理" "Outbound Proxy"): ${OUTBOUND_PROXY_MODE}://${OUTBOUND_PROXY_HOST:-}:${OUTBOUND_PROXY_PORT:-}"
  fi
  printf '\n%s\n%s\n' "$(msg "安全策略" "Safety")" "------"
  printf -- '- %s\n' "$(msg "仅增量添加防火墙规则" "Incremental firewall rules only")"
  printf -- '- %s\n' "$(msg "自动创建防火墙回滚快照" "Firewall rollback snapshot enabled")"
  printf -- '- %s\n' "$(msg "不执行防火墙清空/关闭动作" "No firewall disable/flush actions")"
  echo
}

print_post_install_info() {
  local provider="$1"
  local profile="$2"
  local engine="$3"
  local protocols_csv="$4"

  printf '\n%s\n%s\n' "$(msg "安装结果" "Installed")" "---------"
  printf '%s\n' "$(msg "场景" "Provider") : ${provider}"
  printf '%s\n' "$(msg "规格" "Profile")  : ${profile}"
  printf '%s\n' "$(msg "内核" "Engine")   : ${engine}"
  printf '%s\n' "$(msg "协议" "Protocols"): ${protocols_csv}"
  printf '%s\n' "Argo     : ${ARGO_MODE:-off}"
  printf '%s\n' "WARP     : ${WARP_MODE:-off}"
  printf '%s\n' "$(msg "路由" "Route")    : ${ROUTE_MODE:-direct}"
  printf '%s\n' "$(msg "出站" "Egress")   : ${OUTBOUND_PROXY_MODE:-direct}"
  printf '\n%s\n%s\n' "$(msg "生成文件" "Generated Files")" "---------------"
  printf -- '- %s\n' "${CONFIG_SNAPSHOT_FILE}"
  printf -- '- %s\n' "${SBD_CONTEXT_FILE}"
  printf -- '- %s\n' "${SBD_RULES_FILE}"
  printf '\n%s\n%s\n' "$(msg "下一步命令" "Next Commands")" "-------------"
  printf -- '- %s\n' "./sing-box-deve.sh list"
  printf -- '- %s\n' "./sing-box-deve.sh doctor"
  printf -- '- %s\n' "./sing-box-deve.sh fw status"
  echo

  print_nodes_with_qr
}

print_nodes_with_qr() {
  if [[ ! -f "$SBD_NODES_FILE" ]]; then
    log_warn "$(msg "节点文件不存在: $SBD_NODES_FILE" "Nodes file not found: $SBD_NODES_FILE")"
    return 0
  fi

  echo
  echo "$(msg "节点链接" "Node Links")"
  echo "----------"
  cat "$SBD_NODES_FILE"

  if [[ -f "$SBD_SUB_FILE" ]]; then
    echo
    echo "$(msg "聚合订阅（Base64）" "Aggregate Subscription (Base64)")"
    echo "-------------------------------"
    cat "$SBD_SUB_FILE"
  fi

  if ! command -v qrencode >/dev/null 2>&1; then
    log_warn "$(msg "未安装 qrencode，跳过二维码输出" "qrencode not installed; skipping QR output")"
    return 0
  fi

  echo
  echo "$(msg "二维码" "QR Codes")"
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
