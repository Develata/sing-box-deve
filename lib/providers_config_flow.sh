#!/usr/bin/env bash

SBD_CFG_SNAPSHOT_DIR="${SBD_STATE_DIR}/cfg-snapshots"
SBD_CFG_SNAPSHOT_LATEST_FILE="${SBD_CFG_SNAPSHOT_DIR}/latest"

provider_cfg_snapshot_create() {
  ensure_root
  local reason="${1:-cfg-change}" id dir
  mkdir -p "$SBD_CFG_SNAPSHOT_DIR"
  id="$(date -u +"%Y%m%dT%H%M%SZ")-$(rand_hex_8)"
  dir="${SBD_CFG_SNAPSHOT_DIR}/${id}"
  mkdir -p "$dir"

  cp -f "$(provider_cfg_runtime_file)" "$dir/runtime.env" 2>/dev/null || true
  cp -f "${SBD_CONFIG_DIR}/config.json" "$dir/config.json" 2>/dev/null || true
  cp -f "${SBD_CONFIG_DIR}/xray-config.json" "$dir/xray-config.json" 2>/dev/null || true
  cp -f "$SBD_NODES_FILE" "$dir/nodes.txt" 2>/dev/null || true
  cp -f "$SBD_ARGO_SERVICE_FILE" "$dir/sing-box-deve-argo.service" 2>/dev/null || true
  cp -f "${SBD_DATA_DIR}/argo_mode" "$dir/argo_mode" 2>/dev/null || true
  cp -f "${SBD_DATA_DIR}/argo_domain" "$dir/argo_domain" 2>/dev/null || true

  cat > "$dir/meta.env" <<EOF_META
snapshot_id=${id}
reason=${reason}
created_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF_META
  printf '%s\n' "$id" > "$SBD_CFG_SNAPSHOT_LATEST_FILE"
  printf '%s\n' "$id"
}

provider_cfg_snapshot_ids() {
  [[ -d "$SBD_CFG_SNAPSHOT_DIR" ]] || return 0
  find "$SBD_CFG_SNAPSHOT_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort
}

provider_cfg_snapshot_update_latest() {
  local latest
  latest="$(provider_cfg_snapshot_ids | tail -n1)"
  if [[ -n "$latest" ]]; then
    printf '%s\n' "$latest" > "$SBD_CFG_SNAPSHOT_LATEST_FILE"
  else
    rm -f "$SBD_CFG_SNAPSHOT_LATEST_FILE"
  fi
}

provider_cfg_snapshots_list() {
  local ids id meta created reason count=0 latest=""
  ids="$(provider_cfg_snapshot_ids | sort -r)"
  [[ -n "$ids" ]] || {
    log_info "No cfg snapshots found"
    return 0
  }

  log_info "cfg snapshots (${SBD_CFG_SNAPSHOT_DIR})"
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
    [[ -n "$latest" ]] && log_info "latest snapshot: $latest"
  fi
  log_info "total snapshots: $count"
}

provider_cfg_snapshots_prune() {
  ensure_root
  local keep="${1:-10}" ids id total remove_count removed=0
  [[ "$keep" =~ ^[0-9]+$ ]] || die "Usage: cfg snapshots prune [keep_count]"

  ids="$(provider_cfg_snapshot_ids)"
  [[ -n "$ids" ]] || {
    log_info "No cfg snapshots to prune"
    return 0
  }

  total="$(printf '%s\n' "$ids" | sed '/^$/d' | wc -l | tr -d ' ')"
  if (( keep >= total )); then
    provider_cfg_snapshot_update_latest
    log_info "No prune needed: keep=${keep}, total=${total}"
    return 0
  fi

  remove_count=$((total - keep))
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    (( removed < remove_count )) || break
    rm -rf "${SBD_CFG_SNAPSHOT_DIR:?}/${id:?}"
    log_info "pruned snapshot: ${id}"
    removed=$((removed + 1))
  done <<< "$ids"

  provider_cfg_snapshot_update_latest
  log_success "cfg snapshots pruned: removed=${removed}, kept=${keep}"
}

provider_cfg_snapshots_command() {
  local sub="${1:-list}"
  shift || true
  case "$sub" in
    list) provider_cfg_snapshots_list ;;
    prune) provider_cfg_snapshots_prune "${1:-10}" ;;
    *) die "Usage: cfg snapshots [list|prune [keep_count]]" ;;
  esac
}

provider_cfg_preview() {
  local action="${1:-}" arg1="${2:-}" arg2="${3:-}" arg3="${4:-}"
  provider_cfg_load_runtime_exports
  local current_protocols target_protocols
  current_protocols="${protocols:-vless-reality}"
  case "$action" in
    rotate-id)
      log_info "preview rotate-id: UUID/short-id will be regenerated"
      ;;
    argo)
      log_info "preview argo: mode ${ARGO_MODE:-off} -> ${arg1:-off}"
      log_info "preview argo domain: ${ARGO_DOMAIN:-} -> ${arg3:-${ARGO_DOMAIN:-}}"
      ;;
    ip-pref)
      log_info "preview ip-pref: ${IP_PREFERENCE:-auto} -> ${arg1:-auto}"
      ;;
    cdn-host)
      log_info "preview cdn-host: ${CDN_TEMPLATE_HOST:-} -> ${arg1:-}"
      ;;
    domain-split)
      log_info "preview split direct: ${DOMAIN_SPLIT_DIRECT:-} -> ${arg1:-}"
      log_info "preview split proxy: ${DOMAIN_SPLIT_PROXY:-} -> ${arg2:-}"
      log_info "preview split block: ${DOMAIN_SPLIT_BLOCK:-} -> ${arg3:-}"
      ;;
    tls)
      log_info "preview tls mode: ${TLS_MODE:-self-signed} -> ${arg1:-self-signed}"
      if [[ "${arg1:-}" == "acme" ]]; then
        log_info "preview tls cert: ${ACME_CERT_PATH:-} -> ${arg2:-}"
        log_info "preview tls key: ${ACME_KEY_PATH:-} -> ${arg3:-}"
      fi
      ;;
    protocol-add)
      [[ -n "$arg1" ]] || die "Usage: cfg preview protocol-add <proto_csv> [random|manual] [proto:port,...]"
      target_protocols="$(provider_cfg_protocol_csv_merge "$current_protocols" "$arg1")"
      log_info "preview protocols: ${current_protocols} -> ${target_protocols}"
      log_info "preview add port-mode: ${arg2:-random}"
      if [[ -n "${arg3:-}" ]]; then
        log_info "preview add port-map: ${arg3}"
      fi
      ;;
    protocol-remove)
      [[ -n "$arg1" ]] || die "Usage: cfg preview protocol-remove <proto_csv>"
      target_protocols="$(provider_cfg_protocol_csv_remove "$current_protocols" "$arg1")"
      [[ -n "$target_protocols" ]] || die "Preview result invalid: at least one protocol must remain"
      log_info "preview protocols: ${current_protocols} -> ${target_protocols}"
      ;;
    rebuild)
      log_info "preview rebuild: engine=${engine:-sing-box} protocols=${protocols:-vless-reality}"
      ;;
    *)
      die "Usage: cfg preview <rotate-id|argo|ip-pref|cdn-host|domain-split|tls|protocol-add|protocol-remove|rebuild> ..."
      ;;
  esac
}

provider_cfg_apply_with_snapshot() {
  local action="${1:-}"
  shift || true
  [[ -n "$action" ]] || die "Usage: cfg apply <action> ..."
  local sid
  sid="$(provider_cfg_snapshot_create "cfg ${action}")"
  log_info "cfg snapshot created: ${sid}"
  provider_cfg_apply_dispatch "$action" "$@"
}

provider_cfg_rollback() {
  ensure_root
  local id="${1:-latest}" target_dir runtime_file
  runtime_file="$(provider_cfg_runtime_file)"
  if [[ "$id" == "latest" ]]; then
    [[ -f "$SBD_CFG_SNAPSHOT_LATEST_FILE" ]] || die "No cfg snapshot found"
    id="$(cat "$SBD_CFG_SNAPSHOT_LATEST_FILE")"
  fi

  target_dir="${SBD_CFG_SNAPSHOT_DIR}/${id}"
  [[ -d "$target_dir" ]] || die "Snapshot not found: ${id}"
  [[ -f "$target_dir/runtime.env" ]] || die "Snapshot runtime missing: ${id}"

  cp -f "$target_dir/runtime.env" "$runtime_file"
  cp -f "$target_dir/config.json" "${SBD_CONFIG_DIR}/config.json" 2>/dev/null || true
  cp -f "$target_dir/xray-config.json" "${SBD_CONFIG_DIR}/xray-config.json" 2>/dev/null || true
  cp -f "$target_dir/nodes.txt" "$SBD_NODES_FILE" 2>/dev/null || true

  provider_cfg_rebuild_runtime
  # shellcheck disable=SC1090
  source "$runtime_file"
  if [[ "${argo_mode:-off}" == "off" ]]; then
    systemctl disable --now sing-box-deve-argo.service >/dev/null 2>&1 || true
    rm -f "$SBD_ARGO_SERVICE_FILE"
    rm -f "${SBD_DATA_DIR}/argo_domain" "${SBD_DATA_DIR}/argo_mode"
    systemctl daemon-reload
  else
    configure_argo_tunnel "${protocols:-vless-reality}" "${engine:-sing-box}"
  fi
  write_nodes_output "${engine:-sing-box}" "${protocols:-vless-reality}"
  persist_runtime_state "${provider:-vps}" "${profile:-lite}" "${engine:-sing-box}" "${protocols:-vless-reality}"
  log_success "cfg rollback completed: ${id}"
}

provider_cfg_command() {
  local action="${1:-}"
  shift || true
  case "$action" in
    snapshots|snapshot) provider_cfg_snapshots_command "$@" ;;
    preview) provider_cfg_preview "$@" ;;
    apply) provider_cfg_apply_with_snapshot "$@" ;;
    rollback) provider_cfg_rollback "${1:-latest}" ;;
    rotate-id|argo|ip-pref|cdn-host|domain-split|tls|protocol-add|protocol-remove|rebuild)
      provider_cfg_apply_with_snapshot "$action" "$@"
      ;;
    *)
      die "Usage: cfg [snapshots [list|prune [keep_count]]|preview <action...>|apply <action...>|rollback [snapshot_id|latest]|rotate-id|argo <off|temp|fixed> [token] [domain]|ip-pref <auto|v4|v6>|cdn-host <domain>|domain-split <direct_csv> <proxy_csv> <block_csv>|tls <self-signed|acme> [cert] [key]|protocol-add <proto_csv> [random|manual] [proto:port,...]|protocol-remove <proto_csv>|rebuild]"
      ;;
  esac
}
