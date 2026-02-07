#!/usr/bin/env bash

provider_list() {
  local mode="${1:-all}"

  if [[ "$mode" == "runtime" || "$mode" == "all" ]]; then
    if [[ -f /etc/sing-box-deve/runtime.env ]]; then
      log_info "Current runtime state:"
      cat /etc/sing-box-deve/runtime.env
    else
      log_warn "No runtime state found"
    fi
  fi

  if [[ "$mode" == "settings" || "$mode" == "all" ]]; then
    echo
    log_info "Persistent settings:"
    show_settings
  fi

  if [[ "$mode" == "nodes" || "$mode" == "all" ]]; then
    if [[ -f "$SBD_NODES_FILE" ]]; then
      echo
      log_info "Node links:"
      cat "$SBD_NODES_FILE"
    else
      log_warn "Node file not found: $SBD_NODES_FILE"
    fi
  fi
}

provider_restart() {
  local target="${1:-all}"

  if [[ "$target" == "core" || "$target" == "all" ]]; then
    if [[ -f "$SBD_SERVICE_FILE" ]]; then
      safe_service_restart
      log_success "sing-box-deve service restarted"
    else
      log_warn "Service not installed"
    fi
  fi

  if [[ "$target" == "argo" || "$target" == "all" ]]; then
    if [[ -f "$SBD_ARGO_SERVICE_FILE" ]]; then
      systemctl restart sing-box-deve-argo.service
      log_success "sing-box-deve argo service restarted"
    else
      log_warn "Argo service file not found"
    fi
  fi
}

provider_logs() {
  ensure_root
  local target="${1:-core}"
  case "$target" in
    core)
      if [[ ! -f "$SBD_SERVICE_FILE" ]]; then
        die "Core service is not installed"
      fi
      journalctl -u sing-box-deve.service -n 120 --no-pager
      ;;
    argo)
      if [[ ! -f "$SBD_ARGO_SERVICE_FILE" ]]; then
        die "Argo service is not installed"
      fi
      journalctl -u sing-box-deve-argo.service -n 120 --no-pager
      ;;
    *)
      die "Unsupported logs target: $target"
      ;;
  esac
}

provider_regen_nodes() {
  ensure_root
  [[ -f /etc/sing-box-deve/runtime.env ]] || die "No runtime state found"
  # shellcheck disable=SC1091
  source /etc/sing-box-deve/runtime.env
  local runtime_engine="${engine:-sing-box}"
  local runtime_protocols="${protocols:-vless-reality}"
  write_nodes_output "$runtime_engine" "$runtime_protocols"
  log_success "Nodes regenerated: $SBD_NODES_FILE"
}

provider_update() {
  if [[ ! -f /etc/sing-box-deve/runtime.env ]]; then
    die "No installed runtime found"
  fi

  # shellcheck disable=SC1091
  source /etc/sing-box-deve/runtime.env
  install_engine_binary "$engine"
  safe_service_restart
  if [[ -f "$SBD_ARGO_SERVICE_FILE" ]]; then
    systemctl restart sing-box-deve-argo.service
  fi
  log_success "Engine updated and service restarted"
  provider_panel
}
