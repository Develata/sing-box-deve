#!/usr/bin/env bash
# shellcheck disable=SC2034

SBD_CFG_SNAPSHOT_DIR="${SBD_STATE_DIR}/cfg-snapshots"
SBD_CFG_SNAPSHOT_LATEST_FILE="${SBD_CFG_SNAPSHOT_DIR}/latest"

provider_cfg_snapshot_paths_sync() {
  SBD_CFG_SNAPSHOT_DIR="${SBD_STATE_DIR}/cfg-snapshots"
  SBD_CFG_SNAPSHOT_LATEST_FILE="${SBD_CFG_SNAPSHOT_DIR}/latest"
}

provider_cfg_snapshot_create() {
  ensure_root >&2
  provider_cfg_snapshot_paths_sync
  local reason="${1:-cfg-change}" id dir
  mkdir -p "$SBD_CFG_SNAPSHOT_DIR"
  id="$(date -u +"%Y%m%dT%H%M%SZ")-$(rand_hex_8)"
  dir="${SBD_CFG_SNAPSHOT_DIR}/${id}"
  sbd_state_capture "$dir" false || return 1
  provider_warp_snapshot_lifecycle "$dir" || return 1

  cat > "$dir/meta.env" <<EOF_META
snapshot_id=${id}
reason=${reason}
created_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF_META
  printf '%s\n' "$id" > "$SBD_CFG_SNAPSHOT_LATEST_FILE"
  printf '%s\n' "$id"
}

provider_cfg_snapshot_ids() {
  provider_cfg_snapshot_paths_sync
  [[ -d "$SBD_CFG_SNAPSHOT_DIR" ]] || return 0
  find "$SBD_CFG_SNAPSHOT_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort
}

provider_cfg_snapshot_update_latest() {
  provider_cfg_snapshot_paths_sync
  local latest
  latest="$(provider_cfg_snapshot_ids | tail -n1)"
  if [[ -n "$latest" ]]; then
    printf '%s\n' "$latest" > "$SBD_CFG_SNAPSHOT_LATEST_FILE"
  else
    rm -f "$SBD_CFG_SNAPSHOT_LATEST_FILE"
  fi
}

provider_cfg_snapshots_list() {
  provider_cfg_snapshot_paths_sync
  local ids id meta created reason count=0 latest=""
  ids="$(provider_cfg_snapshot_ids | sort -r)"
  [[ -n "$ids" ]] || {
    log_info "$(msg "未找到配置快照" "No cfg snapshots found")"
    return 0
  }

  log_info "$(msg "配置快照列表（${SBD_CFG_SNAPSHOT_DIR}）" "cfg snapshots (${SBD_CFG_SNAPSHOT_DIR})")"
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    meta="${SBD_CFG_SNAPSHOT_DIR}/${id}/meta.env"
    created="unknown"
    reason="unknown"
    if [[ -f "$meta" ]]; then
      created="$(grep -E '^created_at=' "$meta" | head -n1 | cut -d= -f2-)"
      reason="$(grep -E '^reason=' "$meta" | head -n1 | cut -d= -f2-)"
    fi
    printf '%s | %s | %s\n' "$id" "${created:-unknown}" "${reason:-unknown}"
    count=$((count + 1))
  done <<< "$ids"

  if [[ -f "$SBD_CFG_SNAPSHOT_LATEST_FILE" ]]; then
    latest="$(cat "$SBD_CFG_SNAPSHOT_LATEST_FILE")"
    [[ -n "$latest" ]] && log_info "$(msg "最新快照: $latest" "latest snapshot: $latest")"
  fi
  log_info "$(msg "快照总数: $count" "total snapshots: $count")"
}

provider_cfg_snapshots_prune_unlocked() {
  ensure_root
  provider_cfg_snapshot_paths_sync
  local keep="${1:-10}" ids id total remove_count removed=0
  [[ "$keep" =~ ^[0-9]+$ ]] || die "Usage: cfg snapshots prune [keep_count]"

  ids="$(provider_cfg_snapshot_ids)"
  [[ -n "$ids" ]] || {
    log_info "$(msg "没有可清理的配置快照" "No cfg snapshots to prune")"
    return 0
  }

  total="$(printf '%s\n' "$ids" | sed '/^$/d' | wc -l | tr -d ' ')"
  if (( keep >= total )); then
    provider_cfg_snapshot_update_latest
    log_info "$(msg "无需清理: 保留=${keep}, 总数=${total}" "No prune needed: keep=${keep}, total=${total}")"
    return 0
  fi

  remove_count=$((total - keep))
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    (( removed < remove_count )) || break
    rm -rf "${SBD_CFG_SNAPSHOT_DIR:?}/${id:?}"
    log_info "$(msg "已清理快照: ${id}" "pruned snapshot: ${id}")"
    removed=$((removed + 1))
  done <<< "$ids"

  provider_cfg_snapshot_update_latest
  log_success "$(msg "配置快照清理完成: 已删=${removed}, 保留=${keep}" "cfg snapshots pruned: removed=${removed}, kept=${keep}")"
}

provider_cfg_snapshots_command() {
  local sub="${1:-list}"
  shift || true
  case "$sub" in
    list) provider_cfg_snapshots_list ;;
    prune) provider_cfg_with_lock provider_cfg_snapshots_prune_unlocked "${1:-10}" ;;
    *) die "Usage: cfg snapshots [list|prune [keep_count]]" ;;
  esac
}

provider_cfg_preview() {
  local action="${1:-}" arg1="${2:-}" arg2="${3:-}" arg3="${4:-}"
  provider_cfg_load_runtime_exports || return 1
  local current_protocols target_protocols
  current_protocols="${protocols:-vless-reality}"
  case "$action" in
    rotate-id)
      log_info "$(msg "预览 rotate-id: 将重置 UUID/short-id" "preview rotate-id: UUID/short-id will be regenerated")"
      ;;
    argo)
      log_info "$(msg "预览 argo: 模式 ${ARGO_MODE:-off} -> ${arg1:-off}" "preview argo: mode ${ARGO_MODE:-off} -> ${arg1:-off}")"
      log_info "$(msg "预览 argo 域名: ${ARGO_DOMAIN:-} -> ${arg3:-${ARGO_DOMAIN:-}}" "preview argo domain: ${ARGO_DOMAIN:-} -> ${arg3:-${ARGO_DOMAIN:-}}")"
      ;;
    ip-pref)
      log_info "$(msg "预览 ip-pref: ${IP_PREFERENCE:-auto} -> ${arg1:-auto}" "preview ip-pref: ${IP_PREFERENCE:-auto} -> ${arg1:-auto}")"
      ;;
    cdn-host)
      log_info "$(msg "预览 cdn-host: ${CDN_TEMPLATE_HOST:-} -> ${arg1:-}" "preview cdn-host: ${CDN_TEMPLATE_HOST:-} -> ${arg1:-}")"
      ;;
    domain-split)
      log_info "$(msg "预览分流直连: ${DOMAIN_SPLIT_DIRECT:-} -> ${arg1:-}" "preview split direct: ${DOMAIN_SPLIT_DIRECT:-} -> ${arg1:-}")"
      log_info "$(msg "预览分流代理: ${DOMAIN_SPLIT_PROXY:-} -> ${arg2:-}" "preview split proxy: ${DOMAIN_SPLIT_PROXY:-} -> ${arg2:-}")"
      log_info "$(msg "预览分流屏蔽: ${DOMAIN_SPLIT_BLOCK:-} -> ${arg3:-}" "preview split block: ${DOMAIN_SPLIT_BLOCK:-} -> ${arg3:-}")"
      ;;
    tls)
      log_info "$(msg "预览 TLS 模式: ${TLS_MODE:-self-signed} -> ${arg1:-self-signed}" "preview tls mode: ${TLS_MODE:-self-signed} -> ${arg1:-self-signed}")"
      if [[ "${arg1:-}" == "acme" ]]; then
        log_info "$(msg "预览 TLS 证书: ${ACME_CERT_PATH:-} -> ${arg2:-}" "preview tls cert: ${ACME_CERT_PATH:-} -> ${arg2:-}")"
        log_info "$(msg "预览 TLS 私钥: ${ACME_KEY_PATH:-} -> ${arg3:-}" "preview tls key: ${ACME_KEY_PATH:-} -> ${arg3:-}")"
      elif [[ "${arg1:-}" == "acme-auto" ]]; then
        log_info "$(msg "预览 acme-auto 域名: ${arg2:-}" "preview acme-auto domain: ${arg2:-}")"
        log_info "$(msg "预览 acme-auto 邮箱: ${arg3:-}" "preview acme-auto email: ${arg3:-}")"
      fi
      ;;
    protocol-add)
      [[ -n "$arg1" ]] || die "Usage: cfg preview protocol-add <proto_csv> [random|manual] [proto:port,...]"
      target_protocols="$(provider_cfg_protocol_csv_merge "$current_protocols" "$arg1")"
      log_info "$(msg "预览协议变更: ${current_protocols} -> ${target_protocols}" "preview protocols: ${current_protocols} -> ${target_protocols}")"
      log_info "$(msg "预览新增协议端口模式: ${arg2:-random}" "preview add port-mode: ${arg2:-random}")"
      if [[ -n "${arg3:-}" ]]; then
        log_info "$(msg "预览新增协议端口映射: ${arg3}" "preview add port-map: ${arg3}")"
      fi
      ;;
    protocol-remove)
      [[ -n "$arg1" ]] || die "Usage: cfg preview protocol-remove <proto_csv|index_csv>"
      arg1="$(provider_cfg_protocol_resolve_drop_csv "$current_protocols" "$arg1" "${engine:-sing-box}")"
      target_protocols="$(provider_cfg_protocol_csv_remove "$current_protocols" "$arg1")"
      [[ -n "$target_protocols" ]] || die "Preview result invalid: at least one protocol must remain"
      log_info "$(msg "预览协议变更: ${current_protocols} -> ${target_protocols}" "preview protocols: ${current_protocols} -> ${target_protocols}")"
      ;;
    rebuild)
      log_info "$(msg "预览重建: engine=${engine:-sing-box} protocols=${protocols:-vless-reality}" "preview rebuild: engine=${engine:-sing-box} protocols=${protocols:-vless-reality}")"
      ;;
    *)
      die "Usage: cfg preview <rotate-id|argo|ip-pref|cdn-host|domain-split|tls|protocol-add|protocol-remove|rebuild> ..."
      ;;
  esac
}

provider_cfg_apply_with_snapshot_unlocked() {
  local action="${1:-}"
  shift || true
  [[ -n "$action" ]] || die "Usage: cfg apply <action> ..."
  local sid
  sid="$(provider_cfg_snapshot_create "cfg ${action}")" || return 1
  log_info "$(msg "已创建配置快照: ${sid}" "cfg snapshot created: ${sid}")"
  sbd_transaction_phase "$SBD_ACTIVE_TRANSACTION" committing || return 1
  provider_cfg_apply_dispatch "$action" "$@" || return 1
  provider_cfg_snapshots_prune_unlocked "${SBD_CFG_SNAPSHOT_KEEP:-20}"
}

provider_cfg_rollback_unlocked() {
  ensure_root
  provider_cfg_snapshot_paths_sync
  local id="${1:-latest}" target_dir runtime_file warp_status
  runtime_file="$(provider_cfg_runtime_file)"
  if [[ "$id" == "latest" ]]; then
    [[ -f "$SBD_CFG_SNAPSHOT_LATEST_FILE" ]] || die "No cfg snapshot found"
    id="$(cat "$SBD_CFG_SNAPSHOT_LATEST_FILE")"
  fi

  [[ "$id" =~ ^[A-Za-z0-9_-]+$ ]] || { log_error "Invalid snapshot id"; return 1; }
  target_dir="${SBD_CFG_SNAPSHOT_DIR}/${id}"
  [[ -d "$target_dir" ]] || die "Snapshot not found: ${id}"
  sbd_state_verify "$target_dir" || return 1
  provider_warp_snapshot_verify "$target_dir" || return 1
  warp_status="$(sbd_service_probe sing-box-deve-warp-socks5)" || return 1
  sbd_require_supported_runtime "$target_dir/files/config/runtime.env" || return 1
  local -A live_source=()
  sbd_read_source_state live_source || return 1
  sbd_transaction_phase "$SBD_ACTIVE_TRANSACTION" committing || return 1
  sbd_restore_firewall_delta "$target_dir/files/state/firewall-rules.db" || return 1
  sbd_service_stop sing-box-deve-warp-socks5 || return 1
  sbd_state_restore "$target_dir" || return 1
  provider_warp_snapshot_restore "$target_dir" "$warp_status" || return 1
  sbd_update_runtime_script_root "${live_source[script_root]:-$SBD_INSTALL_DIR/current}" \
    "${live_source[script_source]:-release}" "${live_source[script_source_uid]:-}" "${live_source[script_fallback_root]:-}" || return 1
  CFG_RUNTIME_LOADED=false
  provider_cfg_rebuild_runtime || return 1
  sbd_load_runtime_env "$runtime_file" || return 1
  if [[ "${argo_mode:-off}" == "off" ]]; then
    sbd_service_stop "sing-box-deve-argo" || return 1
    rm -f "$SBD_ARGO_SERVICE_FILE"
    rm -f "${SBD_DATA_DIR}/argo_domain" "${SBD_DATA_DIR}/argo_mode" "$SBD_ARGO_TOKEN_FILE" "$SBD_ARGO_EXEC_FILE"
    sbd_service_daemon_reload || return 1
  else
    configure_argo_tunnel "${protocols:-vless-reality}" "${engine:-sing-box}" || return 1
  fi
  write_nodes_output "${engine:-sing-box}" "${protocols:-vless-reality}" || return 1
  persist_runtime_state "${provider:-vps}" "${profile:-lite}" "${engine:-sing-box}" "${protocols:-vless-reality}" || return 1
  log_success "$(msg "配置回滚完成: ${id}" "cfg rollback completed: ${id}")"
}

provider_cfg_command() {
  local action="${1:-}"
  shift || true
  case "$action" in
    snapshots|snapshot) provider_cfg_snapshots_command "$@" ;;
    preview) provider_cfg_preview "$@" ;;
    apply) provider_cfg_with_lock sbd_transaction_run config-change provider_cfg_apply_with_snapshot_unlocked "$@" ;;
    rollback) provider_cfg_with_lock sbd_transaction_run config-rollback provider_cfg_rollback_unlocked "${1:-latest}" ;;
    rotate-id|argo|ip-pref|cdn-host|domain-split|tls|profile|protocol-add|protocol-remove|rebuild)
      provider_cfg_with_lock sbd_transaction_run config-change provider_cfg_apply_with_snapshot_unlocked "$action" "$@"
      ;;
    *)
      die "Usage: cfg [snapshots [list|prune [keep_count]]|preview <action...>|apply <action...>|rollback [snapshot_id|latest]|rotate-id|argo <off|temp|fixed> [token] [domain]|ip-pref <auto|v4|v6>|cdn-host <domain>|domain-split <direct_csv> <proxy_csv> <block_csv>|tls <self-signed|acme|acme-auto> [cert|domain] [key|email]|profile <lite|full>|protocol-add <proto_csv> [random|manual] [proto:port,...]|protocol-remove <proto_csv|index_csv>|rebuild]"
      ;;
  esac
}
