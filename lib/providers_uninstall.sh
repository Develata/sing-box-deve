#!/usr/bin/env bash

uninstall_disable_unit() {
  local unit="$1"
  local svc_name="${unit%.service}"
  sbd_service_disable_oneshot "$svc_name"
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
        log_info "$(msg "已移除旧托管二进制: ${exec_bin}" "Removed legacy managed binary: ${exec_bin}")"
      fi
      uninstall_disable_unit "$unit"
      rm -f "$file"
      log_info "$(msg "已移除旧托管服务单元: ${unit}" "Removed legacy managed unit: ${unit}")"
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
        log_info "$(msg "已移除命令入口: ${p}" "Removed command entry: ${p}")"
        ;;
      /usr/local/bin/sing-box|/usr/local/bin/xray)
        if [[ "$real" == "${SBD_INSTALL_DIR}/"* ]]; then
          rm -f "$p"
          log_info "$(msg "已移除托管二进制链接: ${p}" "Removed managed binary link: ${p}")"
        fi
        ;;
    esac
  done
}

provider_uninstall() {
  local keep_settings="${1:-false}"
  ensure_root
  log_warn "$(msg "开始卸载：仅移除脚本托管的防火墙规则与 sing-box-deve 状态" "Uninstall requested; removing only managed firewall rules and sing-box-deve state")"
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
  sbd_service_daemon_reload
  fw_detect_backend
  fw_clear_managed_rules
  if [[ "$keep_settings" == "true" ]]; then
    mkdir -p "${SBD_CONFIG_DIR}/backup"
    [[ -f "$SBD_SETTINGS_FILE" ]] && cp "$SBD_SETTINGS_FILE" "${SBD_CONFIG_DIR}/backup/"
    [[ -f "${SBD_DATA_DIR}/uuid" ]] && cp "${SBD_DATA_DIR}/uuid" "${SBD_CONFIG_DIR}/backup/"
    [[ -f "${SBD_DATA_DIR}/reality_private.key" ]] && cp "${SBD_DATA_DIR}/reality_private.key" "${SBD_CONFIG_DIR}/backup/"
    [[ -f "${SBD_DATA_DIR}/reality_public.key" ]] && cp "${SBD_DATA_DIR}/reality_public.key" "${SBD_CONFIG_DIR}/backup/"
    [[ -f "${SBD_DATA_DIR}/reality_short_id" ]] && cp "${SBD_DATA_DIR}/reality_short_id" "${SBD_CONFIG_DIR}/backup/"
    [[ -f "${SBD_DATA_DIR}/xray_private.key" ]] && cp "${SBD_DATA_DIR}/xray_private.key" "${SBD_CONFIG_DIR}/backup/"
    [[ -f "${SBD_DATA_DIR}/xray_public.key" ]] && cp "${SBD_DATA_DIR}/xray_public.key" "${SBD_CONFIG_DIR}/backup/"
    [[ -f "${SBD_DATA_DIR}/xray_short_id" ]] && cp "${SBD_DATA_DIR}/xray_short_id" "${SBD_CONFIG_DIR}/backup/"
    # Priority 2.4: Set restrictive permissions on sensitive backup files (explicit list, no glob)
    chmod 700 "${SBD_CONFIG_DIR}/backup"
    local sensitive_file
    for sensitive_file in uuid reality_private.key reality_short_id xray_private.key xray_short_id; do
      [[ -f "${SBD_CONFIG_DIR}/backup/${sensitive_file}" ]] && chmod 600 "${SBD_CONFIG_DIR}/backup/${sensitive_file}"
    done
    rm -f "${SBD_CONFIG_DIR}/runtime.env" "${SBD_CONFIG_DIR}/config.yaml" "${SBD_CONFIG_DIR}/config.json" "${SBD_CONFIG_DIR}/xray-config.json"
    rm -rf "$SBD_STATE_DIR" "$SBD_RUNTIME_DIR" "$SBD_INSTALL_DIR"
    find "${SBD_CONFIG_DIR}" -maxdepth 1 -type f -delete 2>/dev/null || true
    log_info "$(msg "已保留备份: ${SBD_CONFIG_DIR}/backup/ (settings, uuid, keys)" "Backup preserved: ${SBD_CONFIG_DIR}/backup/ (settings, uuid, keys)")"
  else
    rm -rf "${SBD_CONFIG_DIR}" "$SBD_STATE_DIR" "$SBD_RUNTIME_DIR" "$SBD_INSTALL_DIR"
  fi
  
  # Priority 3.4: Verify uninstall completed successfully
  if ! verify_uninstall; then
    die "$(msg "卸载验证失败：仍有托管文件残留，请手动清理后重试" "Uninstall verification failed: managed files still remain, please clean up manually and retry")"
  fi
  
  log_success "$(msg "卸载完成" "Uninstall complete")"
}

# Priority 3.4: Verify that uninstall removed critical files
verify_uninstall() {
  local remaining=()
  
  # Check for remaining service files
  [[ -f "$SBD_SERVICE_FILE" ]] && remaining+=("$SBD_SERVICE_FILE")
  [[ -f "$SBD_ARGO_SERVICE_FILE" ]] && remaining+=("$SBD_ARGO_SERVICE_FILE")
  [[ -f /etc/systemd/system/sing-box-deve-jump.service ]] && remaining+=("/etc/systemd/system/sing-box-deve-jump.service")
  [[ -f /etc/systemd/system/sing-box-deve-fw-replay.service ]] && remaining+=("/etc/systemd/system/sing-box-deve-fw-replay.service")
  
  # Check for remaining directories (only if not keeping settings)
  [[ -d "$SBD_INSTALL_DIR" ]] && remaining+=("$SBD_INSTALL_DIR")
  
  # Check for persisted script directory
  [[ -d "/opt/sing-box-deve/script" ]] && remaining+=("/opt/sing-box-deve/script")
  
  # Check for remaining binaries
  [[ -f /usr/local/bin/sb ]] && remaining+=("/usr/local/bin/sb")
  
  # Check if services are still active
  if sbd_service_is_active "sing-box-deve" 2>/dev/null; then
    remaining+=("sing-box-deve.service (still active)")
  fi
  
  if [[ ${#remaining[@]} -gt 0 ]]; then
    log_warn "$(msg "以下项目未能完全移除:" "Following items were not fully removed:")"
    printf '  - %s\n' "${remaining[@]}"
    return 1
  else
    log_info "$(msg "卸载验证通过：所有托管文件已移除" "Uninstall verification passed: all managed files removed")"
    return 0
  fi
}
