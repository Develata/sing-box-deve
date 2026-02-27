#!/usr/bin/env bash
# shellcheck disable=SC2034

provider_set_port_info() {
  ensure_root
  [[ -f /etc/sing-box-deve/runtime.env ]] || die "No runtime state found"
  sbd_load_runtime_env /etc/sing-box-deve/runtime.env
  local whitelist cfg
  case "${engine:-sing-box}" in
    sing-box)
      whitelist="vless-reality,vmess-ws,vless-ws,shadowsocks-2022,hysteria2,tuic,trojan,wireguard,anytls,any-reality"
      cfg="${SBD_CONFIG_DIR}/config.json"
      ;;
    xray)
      whitelist="vless-reality,vmess-ws,vless-ws,vless-xhttp,trojan,socks5"
      cfg="${SBD_CONFIG_DIR}/xray-config.json"
      ;;
    *)
      die "Unknown engine in runtime state: ${engine:-unknown}"
      ;;
  esac

  log_info "$(msg "可管理协议白名单（engine=${engine}）: ${whitelist}" "Whitelist (engine=${engine}): ${whitelist}")"
  [[ -f "$cfg" ]] || die "Config file not found: $cfg"
  command -v jq >/dev/null 2>&1 || die "jq is required for set-port --list"
  log_info "$(msg "当前协议端口映射:" "Current protocol ports:")"
  if [[ "${engine}" == "sing-box" ]]; then
    jq -r '.inbounds[] | [.tag, (.listen_port // .port // "n/a")] | @tsv' "$cfg" | while IFS=$'\t' read -r tag port; do
      case "$tag" in
        vless-reality|vmess-ws|vless-ws|ss-2022|hy2|tuic|trojan|wireguard|anytls|any-reality)
          log_info "$(msg "- ${tag}: ${port}" "- ${tag}: ${port}")"
          ;;
      esac
    done
  else
    jq -r '.inbounds[] | [.tag, (.port // "n/a")] | @tsv' "$cfg" | while IFS=$'\t' read -r tag port; do
      case "$tag" in
        vless-reality|vmess-ws|vless-ws|vless-xhttp|trojan|socks5)
          log_info "$(msg "- ${tag}: ${port}" "- ${tag}: ${port}")"
          ;;
      esac
    done
  fi
  log_info "$(msg "用法: ./sing-box-deve.sh set-port --protocol <协议名> --port <1-65535>" "Usage: ./sing-box-deve.sh set-port --protocol <name> --port <1-65535>")"
}

provider_set_port() {
  ensure_root
  [[ -f /etc/sing-box-deve/runtime.env ]] || die "No runtime state found"
  sbd_load_runtime_env /etc/sing-box-deve/runtime.env
  local runtime_provider="${provider:-vps}"
  local runtime_engine="${engine:-sing-box}"
  validate_provider "$runtime_provider"
  validate_engine "$runtime_engine"
  [[ "$2" =~ ^[0-9]+$ ]] || die "Port must be numeric"
  (( $2 >= 1 && $2 <= 65535 )) || die "Port must be between 1 and 65535"

  local protocol="$1" new_port="$2" tag fw_proto
  tag="$(protocol_inbound_tag "$protocol" || true)"
  [[ -n "$tag" ]] || die "Unsupported protocol for set-port: $protocol"
  fw_proto="$(protocol_port_map "$protocol")"
  fw_proto="${fw_proto%%:*}"

  local cfg tmp_cfg old_port rollback_cfg rollback_runtime rollback_nodes
  local old_tag new_tag new_rule_preexisting
  old_tag=""
  new_tag=""
  new_rule_preexisting="false"
  rollback_runtime=""
  rollback_nodes=""
  if [[ "$runtime_engine" == "sing-box" ]]; then
    cfg="${SBD_CONFIG_DIR}/config.json"
    [[ -f "$cfg" ]] || die "Config file missing: $cfg"
    old_port="$(jq -r --arg t "$tag" '.inbounds[] | select(.tag==$t) | (.listen_port // .port)' "$cfg" | head -n1)"
    [[ -n "$old_port" ]] || die "Protocol tag not found in config: $tag"
    if [[ "$old_port" == "$new_port" ]]; then
      log_info "$(msg "端口未变化: ${protocol}=${new_port}" "Port unchanged: ${protocol}=${new_port}")"
      return 0
    fi
    provider_multi_ports_reject_conflict "$protocol" "$new_port"
    rollback_cfg="${SBD_RUNTIME_DIR}/set-port.${tag}.bak.$$"
    cp "$cfg" "$rollback_cfg"
    cp "$cfg" "${cfg}.bak"
    tmp_cfg="${SBD_RUNTIME_DIR}/config.json.tmp"
    jq --arg t "$tag" --argjson p "$new_port" \
      '(.inbounds[] | select(.tag==$t) | .listen_port) = $p
       | ((.inbounds[] | select(.tag==$t)) |= del(.port))' \
      "$cfg" > "$tmp_cfg"
    mv "$tmp_cfg" "$cfg"
    validate_generated_config "sing-box" "true"
  else
    cfg="${SBD_CONFIG_DIR}/xray-config.json"
    [[ -f "$cfg" ]] || die "Config file missing: $cfg"
    old_port="$(jq -r --arg t "$tag" '.inbounds[] | select(.tag==$t) | .port' "$cfg" | head -n1)"
    [[ -n "$old_port" ]] || die "Protocol tag not found in config: $tag"
    if [[ "$old_port" == "$new_port" ]]; then
      log_info "$(msg "端口未变化: ${protocol}=${new_port}" "Port unchanged: ${protocol}=${new_port}")"
      return 0
    fi
    provider_multi_ports_reject_conflict "$protocol" "$new_port"
    rollback_cfg="${SBD_RUNTIME_DIR}/set-port.${tag}.bak.$$"
    cp "$cfg" "$rollback_cfg"
    cp "$cfg" "${cfg}.bak"
    tmp_cfg="${SBD_RUNTIME_DIR}/xray-config.json.tmp"
    jq --arg t "$tag" --argjson p "$new_port" '(.inbounds[] | select(.tag==$t) | .port) = $p' "$cfg" > "$tmp_cfg"
    mv "$tmp_cfg" "$cfg"
    validate_generated_config "xray" "true"
  fi

  fw_detect_backend
  load_install_context || create_install_context "$runtime_provider" "${profile:-lite}" "$runtime_engine" "${protocols:-vless-reality}"
  new_tag="$(fw_tag "core" "$fw_proto" "$new_port")"
  if fw_rule_exists_record "$new_tag"; then
    new_rule_preexisting="true"
  fi
  if [[ -n "$old_port" && "$old_port" != "$new_port" ]]; then
    old_tag="$(fw_tag "core" "$fw_proto" "$old_port")"
  fi

  if ! ( fw_apply_rule "$fw_proto" "$new_port" ); then
    cp -f "$rollback_cfg" "$cfg" 2>/dev/null || true
    provider_restart core >/dev/null 2>&1 || true
    rm -f "$rollback_cfg"
    die "Failed to apply firewall rule for new port: ${protocol}:${new_port}"
  fi

  if [[ -n "${port_egress_map:-}" ]]; then
    rollback_runtime="${SBD_RUNTIME_DIR}/set-port.runtime.bak.$$"
    rollback_nodes="${SBD_RUNTIME_DIR}/set-port.nodes.bak.$$"
    cp -f /etc/sing-box-deve/runtime.env "$rollback_runtime" 2>/dev/null || true
    cp -f "$SBD_NODES_FILE" "$rollback_nodes" 2>/dev/null || true

    if ! (
      provider_cfg_load_runtime_exports
      PORT_EGRESS_MAP="${port_egress_map:-}"
      provider_cfg_rebuild_runtime
    ); then
      cp -f "$rollback_cfg" "$cfg" 2>/dev/null || true
      cp -f "$rollback_runtime" /etc/sing-box-deve/runtime.env 2>/dev/null || true
      cp -f "$rollback_nodes" "$SBD_NODES_FILE" 2>/dev/null || true
      if [[ "$new_rule_preexisting" != "true" ]]; then
        fw_remove_rule_by_record "$FW_BACKEND" "$fw_proto" "$new_port" "$new_tag"
        awk -F'|' -v t="$new_tag" '$4 != t' "$SBD_RULES_FILE" > "${SBD_RULES_FILE}.tmp" 2>/dev/null || true
        mv "${SBD_RULES_FILE}.tmp" "$SBD_RULES_FILE" 2>/dev/null || true
      fi
      provider_restart core >/dev/null 2>&1 || true
      rm -f "$rollback_cfg"
      rm -f "$rollback_runtime" "$rollback_nodes"
      die "Failed to rebuild runtime after set-port: ${protocol}:${new_port}"
    fi
    if [[ -n "$old_tag" ]]; then
      local answer
      if fw_rule_exists_record "$old_tag"; then
        if [[ "${AUTO_YES:-false}" == "true" ]]; then
          answer="Y"
        else
          read -r -p "$(msg "是否移除旧端口的防火墙规则 ${fw_proto}/${old_port}? [Y/n]: " "Remove old port firewall rule ${fw_proto}/${old_port}? [Y/n]: ")" answer
          answer="${answer:-Y}"
        fi
        if [[ "$answer" =~ ^[Yy]$ ]]; then
          fw_remove_rule_by_record "$FW_BACKEND" "$fw_proto" "$old_port" "$old_tag"
          awk -F'|' -v t="$old_tag" '$4 != t' "$SBD_RULES_FILE" > "${SBD_RULES_FILE}.tmp" 2>/dev/null || true
          mv "${SBD_RULES_FILE}.tmp" "$SBD_RULES_FILE" 2>/dev/null || true
          log_success "$(msg "已移除旧防火墙规则: ${fw_proto}/${old_port}" "Removed old firewall rule: ${fw_proto}/${old_port}")"
        else
          log_warn "$(msg "保留历史防火墙规则: ${fw_proto}/${old_port}" "Preserving historical firewall rule: ${fw_proto}/${old_port}")"
        fi
      else
        log_warn "$(msg "保留历史防火墙规则: ${fw_proto}/${old_port}" "Preserving historical firewall rule: ${fw_proto}/${old_port}")"
      fi
    fi
    rm -f "$rollback_cfg"
    rm -f "$rollback_runtime" "$rollback_nodes"
    log_success "$(msg "协议端口已更新并重建端口出站策略: ${protocol} -> ${new_port}" "Protocol port updated and port egress policy rebuilt: ${protocol} -> ${new_port}")"
    return 0
  fi

  if ! ( provider_restart core ); then
    cp -f "$rollback_cfg" "$cfg" 2>/dev/null || true
    if [[ "$new_rule_preexisting" != "true" ]]; then
      fw_remove_rule_by_record "$FW_BACKEND" "$fw_proto" "$new_port" "$new_tag"
      awk -F'|' -v t="$new_tag" '$4 != t' "$SBD_RULES_FILE" > "${SBD_RULES_FILE}.tmp" 2>/dev/null || true
      mv "${SBD_RULES_FILE}.tmp" "$SBD_RULES_FILE" 2>/dev/null || true
    fi
    provider_restart core >/dev/null 2>&1 || true
    rm -f "$rollback_cfg"
    die "Failed to restart core after set-port: ${protocol}:${new_port}"
  fi
  if [[ -n "$old_tag" ]]; then
    local answer
    if fw_rule_exists_record "$old_tag"; then
      if [[ "${AUTO_YES:-false}" == "true" ]]; then
        answer="Y"
      else
        read -r -p "$(msg "是否移除旧端口的防火墙规则 ${fw_proto}/${old_port}? [Y/n]: " "Remove old port firewall rule ${fw_proto}/${old_port}? [Y/n]: ")" answer
        answer="${answer:-Y}"
      fi
      if [[ "$answer" =~ ^[Yy]$ ]]; then
        fw_remove_rule_by_record "$FW_BACKEND" "$fw_proto" "$old_port" "$old_tag"
        awk -F'|' -v t="$old_tag" '$4 != t' "$SBD_RULES_FILE" > "${SBD_RULES_FILE}.tmp" 2>/dev/null || true
        mv "${SBD_RULES_FILE}.tmp" "$SBD_RULES_FILE" 2>/dev/null || true
        log_success "$(msg "已移除旧防火墙规则: ${fw_proto}/${old_port}" "Removed old firewall rule: ${fw_proto}/${old_port}")"
      else
        log_warn "$(msg "保留历史防火墙规则: ${fw_proto}/${old_port}" "Preserving historical firewall rule: ${fw_proto}/${old_port}")"
      fi
    else
      log_warn "$(msg "保留历史防火墙规则: ${fw_proto}/${old_port}" "Preserving historical firewall rule: ${fw_proto}/${old_port}")"
    fi
  fi
  rm -f "$rollback_cfg"
  log_success "$(msg "协议端口已更新: ${protocol} -> ${new_port}" "Protocol port updated: ${protocol} -> ${new_port}")"
}
