#!/usr/bin/env bash

provider_doctor() {
  if [[ -f "$SBD_SERVICE_FILE" ]]; then
    if systemctl is-active --quiet sing-box-deve.service; then
      log_success "Service status: active"
    else
      log_warn "Service status: inactive"
      log_info "Suggestion: run './sing-box-deve.sh restart --core' and re-check logs"
      systemctl status sing-box-deve.service --no-pager -l || true
    fi
  else
    log_warn "Service file not found: $SBD_SERVICE_FILE"
    log_info "Suggestion: install runtime first via 'install' command"
  fi

  if [[ -f /etc/sing-box-deve/runtime.env ]]; then
    log_info "Runtime state detected"
    # shellcheck disable=SC1091
    source /etc/sing-box-deve/runtime.env
    if [[ "${engine:-}" == "sing-box" && -f "${SBD_CONFIG_DIR}/config.json" && -x "${SBD_BIN_DIR}/sing-box" ]]; then
      if "${SBD_BIN_DIR}/sing-box" check -c "${SBD_CONFIG_DIR}/config.json" >/dev/null 2>&1; then
        log_success "sing-box config check passed"
      else
        log_warn "sing-box config check failed"
      fi
    elif [[ "${engine:-}" == "xray" && -f "${SBD_CONFIG_DIR}/xray-config.json" && -x "${SBD_BIN_DIR}/xray" ]]; then
      if "${SBD_BIN_DIR}/xray" run -test -config "${SBD_CONFIG_DIR}/xray-config.json" >/dev/null 2>&1; then
        log_success "xray config check passed"
      else
        log_warn "xray config check failed"
      fi
    fi

    if [[ "${protocols:-}" == *"argo"* ]]; then
      if [[ -f "$SBD_ARGO_SERVICE_FILE" ]]; then
        if systemctl is-active --quiet sing-box-deve-argo.service; then
          log_success "Argo diagnostic: service active"
        else
          log_warn "Argo diagnostic: service inactive"
          log_info "Suggestion: run './sing-box-deve.sh restart --argo'"
        fi
      else
        log_warn "Argo diagnostic: service file missing"
        log_info "Suggestion: reinstall with protocol including argo and --argo temp|fixed"
      fi

      if [[ -f "${SBD_DATA_DIR}/argo_domain" ]]; then
        local adomain
        adomain="$(<"${SBD_DATA_DIR}/argo_domain")"
        if [[ -n "$adomain" ]]; then
          log_success "Argo diagnostic: domain detected (${adomain})"
        else
          log_warn "Argo diagnostic: domain file empty"
        fi
      else
        log_warn "Argo diagnostic: domain file missing"
      fi
    fi

    if [[ "${protocols:-}" == *"warp"* ]]; then
      if [[ "${warp_mode:-off}" != "global" ]]; then
        log_warn "WARP diagnostic: warp protocol enabled but warp_mode is not global"
      else
        if [[ -n "${WARP_PRIVATE_KEY:-}" && -n "${WARP_PEER_PUBLIC_KEY:-}" ]]; then
          log_success "WARP diagnostic: keys found in current environment"
        elif [[ -f "${SBD_CONFIG_DIR}/config.json" ]] && grep -q '"tag": "warp-out"' "${SBD_CONFIG_DIR}/config.json"; then
          log_success "WARP diagnostic: warp-out configured in config.json"
        else
          log_warn "WARP diagnostic: warp keys not found in env and warp-out not detected"
          log_info "Suggestion: set WARP_PRIVATE_KEY/WARP_PEER_PUBLIC_KEY and re-apply runtime"
        fi
      fi
    fi

    if [[ "${outbound_proxy_mode:-direct}" != "direct" ]]; then
      if [[ -n "${outbound_proxy_host:-}" && -n "${outbound_proxy_port:-}" ]]; then
        log_success "Outbound proxy diagnostic: ${outbound_proxy_mode}://${outbound_proxy_host}:${outbound_proxy_port}"
      else
        log_warn "Outbound proxy diagnostic: mode enabled but host/port missing in runtime state"
        log_info "Suggestion: use set-egress to persist a valid outbound proxy endpoint"
      fi
    fi
  else
    log_warn "Runtime state file missing"
    log_info "Suggestion: run install once or restore /etc/sing-box-deve/runtime.env"
  fi

  if [[ -f "$SBD_NODES_FILE" ]]; then
    log_success "Node output file present: $SBD_NODES_FILE"
    local bad_nodes
    bad_nodes="$(awk '!/^(vless|vmess|hysteria2|trojan|wireguard|anytls|socks|ss|tuic|argo-domain|warp-mode):\/\//{print NR":"$0}' "$SBD_NODES_FILE" || true)"
    if [[ -n "$bad_nodes" ]]; then
      log_warn "Node output contains unrecognized lines:"
      printf '%s\n' "$bad_nodes"
    else
      log_success "Node output format check passed"
    fi
  else
    log_warn "Node output file missing"
    log_info "Suggestion: run './sing-box-deve.sh regen-nodes'"
  fi

  if [[ -f /etc/sing-box-deve/runtime.env ]]; then
    # shellcheck disable=SC1091
    source /etc/sing-box-deve/runtime.env
    local p mapping proto port tag
    IFS=',' read -r -a _plist <<< "${protocols:-}"
    for p in "${_plist[@]}"; do
      p="$(echo "$p" | xargs)"
      [[ -n "$p" ]] || continue
      protocol_needs_local_listener "$p" || continue
      tag="$(protocol_inbound_tag "$p" || true)"
      [[ -n "$tag" ]] || continue
      mapping="$(protocol_port_map "$p")"
      proto="${mapping%%:*}"
      port="$(config_port_for_tag "${engine:-sing-box}" "$tag" 2>/dev/null || true)"
      [[ -n "$port" ]] || port="$(get_protocol_port "$p")"
      if ss -lntup 2>/dev/null | grep -E "[.:]${port}[[:space:]]" >/dev/null; then
        log_success "Port listening detected for ${p}: ${proto}/${port}"
      else
        log_warn "Port not detected for ${p}: ${proto}/${port}"
        log_info "Suggestion: check service status and firewall rules, then run './sing-box-deve.sh restart --all'"
      fi
    done
  fi
}
