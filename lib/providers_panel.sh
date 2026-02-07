#!/usr/bin/env bash

provider_status_header() {
  local core_state="unknown"
  local argo_state="off"
  if [[ -f "$SBD_SERVICE_FILE" ]]; then
    if systemctl is-active --quiet sing-box-deve.service; then
      core_state="running"
    else
      core_state="stopped"
    fi
  fi
  if [[ -f "$SBD_ARGO_SERVICE_FILE" ]]; then
    if systemctl is-active --quiet sing-box-deve-argo.service; then
      argo_state="running"
    else
      argo_state="stopped"
    fi
  fi
  log_info "State: core=${core_state} argo=${argo_state}"

  if [[ -f /etc/sing-box-deve/runtime.env ]]; then
    # shellcheck disable=SC1091
    source /etc/sing-box-deve/runtime.env
    log_info "Provider: ${provider:-unknown} | Profile: ${profile:-unknown} | Engine: ${engine:-unknown}"
    log_info "Protocols: ${protocols:-none}"
    log_info "Argo: ${argo_mode:-off} | WARP: ${warp_mode:-off} | Route: ${route_mode:-direct} | Egress: ${outbound_proxy_mode:-direct}"

    local main_port="n/a"
    if [[ "${engine:-}" == "sing-box" && -f "${SBD_CONFIG_DIR}/config.json" ]]; then
      main_port="$(jq -r '.inbounds[0] | (.listen_port // .port // "n/a")' "${SBD_CONFIG_DIR}/config.json" 2>/dev/null || true)"
    elif [[ "${engine:-}" == "xray" && -f "${SBD_CONFIG_DIR}/xray-config.json" ]]; then
      main_port="$(jq -r '.inbounds[0] | (.port // "n/a")' "${SBD_CONFIG_DIR}/xray-config.json" 2>/dev/null || true)"
    fi
    local pub_ip
    pub_ip="$(detect_public_ip)"
    log_info "PublicIP: ${pub_ip} | MainPort: ${main_port}"
  else
    log_warn "Runtime state not found (/etc/sing-box-deve/runtime.env)"
  fi

  if [[ -f "$SBD_SERVICE_FILE" ]]; then
    if systemctl is-active --quiet sing-box-deve.service; then
      log_success "Core service: running"
    else
      log_warn "Core service: not running"
    fi
  fi

  local script_local script_remote script_upgrade
  script_local="$(current_script_version)"
  script_remote="$(fetch_remote_script_version 2>/dev/null || true)"
  if [[ -z "$script_remote" ]]; then
    script_upgrade="unknown"
  elif [[ "$script_local" == "$script_remote" ]]; then
    script_upgrade="no"
  else
    script_upgrade="yes"
  fi
  log_info "Script: local=${script_local} remote=${script_remote:-n/a} upgrade=${script_upgrade}"

  if [[ -x "${SBD_BIN_DIR}/sing-box" ]]; then
    local sbver
    sbver="$("${SBD_BIN_DIR}/sing-box" version 2>/dev/null | awk '/version/{print $NF}' | head -n1)"
    if [[ -n "$sbver" ]]; then
      local sb_remote sb_upgrade sb_local_norm sb_remote_norm
      sb_remote="$(fetch_latest_release_tag "SagerNet/sing-box" 2>/dev/null || true)"
      sb_local_norm="${sbver#v}"
      sb_remote_norm="${sb_remote#v}"
      if [[ -z "$sb_remote" ]]; then
        sb_upgrade="unknown"
      elif [[ "$sb_local_norm" == "$sb_remote_norm" ]]; then
        sb_upgrade="no"
      else
        sb_upgrade="yes"
      fi
      log_info "sing-box: local=${sbver} remote=${sb_remote:-n/a} upgrade=${sb_upgrade}"
    fi
  fi

  if [[ -x "${SBD_BIN_DIR}/xray" ]]; then
    local xver
    xver="$("${SBD_BIN_DIR}/xray" version 2>/dev/null | awk '/^Xray/{print $2}' | head -n1)"
    if [[ -n "$xver" ]]; then
      local x_remote x_upgrade x_local_norm x_remote_norm
      x_remote="$(fetch_latest_release_tag "XTLS/Xray-core" 2>/dev/null || true)"
      x_local_norm="${xver#v}"
      x_remote_norm="${x_remote#v}"
      if [[ -z "$x_remote" ]]; then
        x_upgrade="unknown"
      elif [[ "$x_local_norm" == "$x_remote_norm" ]]; then
        x_upgrade="no"
      else
        x_upgrade="yes"
      fi
      log_info "xray: local=${xver} remote=${x_remote:-n/a} upgrade=${x_upgrade}"
    fi
  fi

  if [[ -x "${SBD_BIN_DIR}/cloudflared" ]]; then
    local cver
    cver="$("${SBD_BIN_DIR}/cloudflared" --version 2>/dev/null | awk '{print $3}' | head -n1)"
    [[ -n "$cver" ]] && log_info "cloudflared version: ${cver}"
    if [[ -f "$SBD_ARGO_SERVICE_FILE" ]]; then
      if systemctl is-active --quiet sing-box-deve-argo.service; then
        log_success "Argo sidecar: running"
      else
        log_warn "Argo sidecar: not running"
      fi
    fi
  fi

  if [[ -f "$SBD_NODES_FILE" ]]; then
    log_info "Nodes file: $SBD_NODES_FILE"
  fi
}

provider_panel() {
  local mode="${1:-compact}"
  log_info "========== sing-box-deve panel =========="
  provider_status_header

  if [[ "$mode" == "full" ]]; then
    echo
    log_info "----- Runtime Details -----"
    if [[ -f /etc/sing-box-deve/runtime.env ]]; then
      cat /etc/sing-box-deve/runtime.env
    else
      log_warn "runtime.env missing"
    fi
    log_info "----- Settings -----"
    show_settings
    log_info "----- Managed Firewall Rules -----"
    fw_status
  fi

  log_info "========================================="
}
