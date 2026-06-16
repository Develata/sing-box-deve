#!/usr/bin/env bash

generate_client_artifacts() {
  mkdir -p "$SBD_DATA_DIR"
  [[ -f "$SBD_NODES_FILE" ]] || die "nodes file not found"
  ensure_clash_rulesets_local
  ensure_sing_route_rulesets_local
  render_singbox_client_json "${SBD_DATA_DIR}/sing_box_client.json"
  render_clash_meta_yaml "${SBD_DATA_DIR}/clash_meta_client.yaml"
  render_sfa_sfi_sfw "SFA" "${SBD_DATA_DIR}/sfa_client.json"
  render_sfa_sfi_sfw "SFI" "${SBD_DATA_DIR}/sfi_client.json"
  share_generate_bundle "$SBD_NODES_FILE"
}

provider_sub_rules_update() {
  ensure_root
  clash_rulesets_update_local true
  sing_route_rulesets_update_local
  log_success "$(msg "已从脚本内置规则集重新同步 clash 与 sing 路由规则" "Clash and sing route rulesets re-synced from bundled repo files")"
}

provider_sub_refresh() {
  ensure_root
  [[ -f "${SBD_CONFIG_DIR}/runtime.env" ]] || die "No runtime state found"
  sbd_load_runtime_env "${SBD_CONFIG_DIR}/runtime.env"
  write_nodes_output "${engine:-sing-box}" "${protocols:-vless-reality}"
  generate_client_artifacts
  log_success "$(msg "订阅与分享产物已刷新" "Subscription artifacts refreshed")"
}

provider_sub_show() {
  [[ -f "$SBD_NODES_FILE" ]] && log_info "$(msg "节点文件: $SBD_NODES_FILE" "nodes: $SBD_NODES_FILE")"
  [[ -f "$SBD_SUB_FILE" ]] && log_info "$(msg "聚合订阅: $SBD_SUB_FILE" "aggregate: $SBD_SUB_FILE")"
  [[ -f "${SBD_DATA_DIR}/sing_box_client.json" ]] && log_info "$(msg "sing-box 客户端配置: ${SBD_DATA_DIR}/sing_box_client.json" "sing-box client: ${SBD_DATA_DIR}/sing_box_client.json")"
  [[ -f "${SBD_DATA_DIR}/clash_meta_client.yaml" ]] && log_info "$(msg "clash-meta 客户端配置: ${SBD_DATA_DIR}/clash_meta_client.yaml" "clash-meta client: ${SBD_DATA_DIR}/clash_meta_client.yaml")"
  [[ -f "${SBD_DATA_DIR}/sfa_client.json" ]] && log_info "$(msg "SFA 客户端配置: ${SBD_DATA_DIR}/sfa_client.json" "SFA client: ${SBD_DATA_DIR}/sfa_client.json")"
  [[ -f "${SBD_DATA_DIR}/sfi_client.json" ]] && log_info "$(msg "SFI 客户端配置: ${SBD_DATA_DIR}/sfi_client.json" "SFI client: ${SBD_DATA_DIR}/sfi_client.json")"
  share_show_bundle true
}

provider_sub_command() {
  local action="${1:-show}"
  shift || true
  case "$action" in
    refresh) provider_sub_refresh ;;
    show) provider_sub_show ;;
    rules-update) provider_sub_rules_update ;;
    *)
      die "Usage: sub [refresh|show|rules-update]"
      ;;
  esac
}
