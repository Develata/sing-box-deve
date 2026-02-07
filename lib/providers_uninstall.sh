#!/usr/bin/env bash

uninstall_disable_unit() {
  local unit="$1"
  if systemctl list-unit-files | grep -q "^${unit}"; then
    systemctl disable --now "$unit" >/dev/null 2>&1 || true
  fi
}

uninstall_remove_legacy_engine_units() {
  local unit file exec_cmd exec_bin
  for unit in "sing-box.service" "xray.service"; do
    file="/etc/systemd/system/${unit}"
    [[ -f "$file" ]] || continue
    if grep -Eq '/opt/sing-box-deve|/usr/local/bin/(sing-box|xray)|sing-box-deve' "$file"; then
      exec_cmd="$(awk -F= '/^ExecStart=/{print $2; exit}' "$file" | xargs || true)"
      exec_bin="${exec_cmd%% *}"
      if [[ "$exec_bin" == "/usr/local/bin/sing-box" || "$exec_bin" == "/usr/local/bin/xray" ]]; then
        rm -f "$exec_bin"
        log_info "Removed legacy managed binary: ${exec_bin}"
      fi
      uninstall_disable_unit "$unit"
      rm -f "$file"
      log_info "Removed legacy managed unit: ${unit}"
    fi
  done
}

uninstall_remove_managed_global_bins() {
  local p real
  for p in "/usr/local/bin/sb" "/usr/local/bin/sing-box" "/usr/local/bin/xray"; do
    [[ -e "$p" ]] || continue
    real="$(readlink -f "$p" 2>/dev/null || true)"
    case "$p" in
      /usr/local/bin/sb)
        rm -f "$p"
        log_info "Removed command entry: ${p}"
        ;;
      /usr/local/bin/sing-box|/usr/local/bin/xray)
        if [[ "$real" == "${SBD_INSTALL_DIR}/"* ]]; then
          rm -f "$p"
          log_info "Removed managed binary link: ${p}"
        fi
        ;;
    esac
  done
}

provider_uninstall() {
  local keep_settings="${1:-false}"
  ensure_root
  log_warn "Uninstall requested; removing only managed firewall rules and sing-box-deve state"
  uninstall_disable_unit "sing-box-deve.service"
  uninstall_disable_unit "sing-box-deve-argo.service"
  uninstall_disable_unit "sing-box-deve-jump.service"
  uninstall_disable_unit "sing-box-deve-fw-replay.service"
  uninstall_remove_legacy_engine_units
  rm -f "$SBD_SERVICE_FILE"
  rm -f "$SBD_ARGO_SERVICE_FILE"
  rm -f /etc/systemd/system/sing-box-deve-jump.service
  rm -f /etc/systemd/system/sing-box-deve-fw-replay.service
  uninstall_remove_managed_global_bins
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
