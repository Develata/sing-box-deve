#!/usr/bin/env bash

provider_uninstall() {
  local keep_settings="${1:-false}"
  ensure_root
  log_warn "Uninstall requested; removing only managed firewall rules and sing-box-deve state"
  if systemctl list-unit-files | grep -q '^sing-box-deve.service'; then
    systemctl disable --now sing-box-deve.service >/dev/null 2>&1 || true
  fi
  if systemctl list-unit-files | grep -q '^sing-box-deve-argo.service'; then
    systemctl disable --now sing-box-deve-argo.service >/dev/null 2>&1 || true
  fi
  rm -f "$SBD_SERVICE_FILE"
  rm -f "$SBD_ARGO_SERVICE_FILE"
  systemctl daemon-reload
  fw_detect_backend
  fw_clear_managed_rules
  if [[ "$keep_settings" == "true" ]]; then
    rm -f /etc/sing-box-deve/runtime.env /etc/sing-box-deve/config.yaml /etc/sing-box-deve/config.json /etc/sing-box-deve/xray-config.json
    rm -rf "$SBD_STATE_DIR" "$SBD_RUNTIME_DIR" "$SBD_INSTALL_DIR"
    log_info "Kept persistent settings file: /etc/sing-box-deve/settings.conf"
  else
    rm -rf /etc/sing-box-deve "$SBD_STATE_DIR" "$SBD_RUNTIME_DIR" "$SBD_INSTALL_DIR"
  fi
  log_success "Uninstall complete"
}
