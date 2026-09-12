#!/usr/bin/env bash
# shellcheck disable=SC2034

provider_set_port_info() {
  ensure_root
  [[ -f "${SBD_CONFIG_DIR}/runtime.env" ]] || die "No runtime state found"
  sbd_load_runtime_env "${SBD_CONFIG_DIR}/runtime.env" || return 1
  local whitelist cfg
  case "${engine:-sing-box}" in
    sing-box)
      whitelist="vless-reality,vless-ws,shadowsocks-2022,naive,hysteria2"
      cfg="${SBD_CONFIG_DIR}/config.json"
      ;;
    xray)
      whitelist="vless-reality,vless-ws,vless-xhttp"
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
        vless-reality|vless-ws|ss-2022|naive|hy2)
          log_info "$(msg "- ${tag}: ${port}" "- ${tag}: ${port}")"
          ;;
      esac
    done
  else
    jq -r '.inbounds[] | [.tag, (.port // "n/a")] | @tsv' "$cfg" | while IFS=$'\t' read -r tag port; do
      case "$tag" in
        vless-reality|vless-ws|vless-xhttp)
          log_info "$(msg "- ${tag}: ${port}" "- ${tag}: ${port}")"
          ;;
      esac
    done
  fi
  log_info "$(msg "用法: ./sing-box-deve.sh set-port --protocol <协议名> --port <1-65535>" "Usage: ./sing-box-deve.sh set-port --protocol <name> --port <1-65535>")"
}

provider_set_port() {
  sbd_with_mutation_lock sbd_transaction_run config-change provider_set_port_unlocked "$@"
}

provider_set_port_unlocked() {
  ensure_root
  provider_cfg_load_runtime_exports || return 1
  local protocol="$1" new_port="$2" tag cfg tmp old_port old_records
  local record_backend record_proto record_port record_tag answer
  if [[ ! "$new_port" =~ ^[1-9][0-9]{0,4}$ ]] || (( new_port > 65535 )); then
    log_error "Port must be between 1 and 65535"; return 1
  fi
  tag="$(protocol_inbound_tag "$protocol")" || return 1
  case "$engine" in
    sing-box) cfg="$SBD_CONFIG_DIR/config.json" ;;
    xray) cfg="$SBD_CONFIG_DIR/xray-config.json" ;;
    *) return 1 ;;
  esac
  old_port="$(jq -er --arg tag "$tag" '.inbounds[] | select(.tag == $tag) | (.listen_port // .port)' "$cfg")" || return 1
  [[ "$old_port" != "$new_port" ]] || { log_info "Port unchanged: $protocol=$new_port"; return 0; }
  provider_multi_ports_reject_conflict "$protocol" "$new_port" || return 1
  tmp="$(mktemp "$SBD_CONFIG_DIR/.set-port.XXXXXX")" || return 1
  if [[ "$engine" == sing-box ]]; then
    jq --arg tag "$tag" --argjson port "$new_port" \
      '(.inbounds[] | select(.tag == $tag)) |= (.listen_port=$port | del(.port))' "$cfg" > "$tmp" || { rm -f "$tmp"; return 1; }
  else
    jq --arg tag "$tag" --argjson port "$new_port" \
      '(.inbounds[] | select(.tag == $tag) | .port)=$port' "$cfg" > "$tmp" || { rm -f "$tmp"; return 1; }
  fi
  sbd_commit_file_with_backups "$cfg" "$tmp" 600 || return 1
  validate_generated_config "$engine" false || return 1
  fw_detect_backend || return 1
  # The installation baseline can predate protocol/engine changes.
  (load_install_context) || create_install_context "${provider:?Runtime provider missing}" "${profile:?Runtime profile missing}" "$engine" "${protocols:?Runtime protocols missing}" || return 1
  old_records="$(fw_records_for_protocol_endpoint "" "$protocol" "$old_port")" || return 1
  fw_apply_protocol_rule "$protocol" "$new_port" || return 1
  provider_restart core || return 1
  if [[ "$protocol" == vless-ws && "${ARGO_MODE:-off}" == temp ]]; then
    configure_argo_tunnel "$protocols" "$engine" || return 1
    persist_runtime_state "$provider" "$profile" "$engine" "$protocols" || return 1
  fi
  write_nodes_output "$engine" "$protocols" || return 1
  if [[ -n "$old_records" ]]; then
    answer=Y
    if [[ "${AUTO_YES:-false}" != true ]]; then
      read -r -p "Remove old port firewall rule ${protocol}/${old_port}? [Y/n]: " answer || answer=Y
    fi
    if [[ "${answer:-Y}" =~ ^[Yy]$ ]]; then
      while IFS='|' read -r record_backend record_proto record_port record_tag; do
        [[ -n "$record_tag" ]] || return 1
        fw_remove_rule_by_record "$record_backend" "$record_proto" "$record_port" "$record_tag" || return 1
        fw_remove_record_by_tag "$record_tag" || return 1
      done <<< "$old_records"
    fi
  fi
  log_success "Protocol port updated: $protocol -> $new_port"
}
