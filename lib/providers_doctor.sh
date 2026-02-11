#!/usr/bin/env bash

provider_cert_days_left() {
  local cert="$1" end_raw end_epoch now
  command -v openssl >/dev/null 2>&1 || return 1
  end_raw="$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2-)"
  [[ -n "$end_raw" ]] || return 1
  end_epoch="$(date -d "$end_raw" +%s 2>/dev/null || true)"
  now="$(date +%s)"
  [[ -n "$end_epoch" ]] || return 1
  echo $(((end_epoch - now) / 86400))
}

provider_doctor_check_service() {
  if [[ ! -f "$SBD_SERVICE_FILE" ]]; then
    log_warn "$(msg "未找到服务文件: ${SBD_SERVICE_FILE}" "Service file not found: ${SBD_SERVICE_FILE}")"
    return
  fi
  if systemctl is-active --quiet sing-box-deve.service; then
    log_success "$(msg "核心服务状态: 运行中" "Core service status: active")"
  else
    log_warn "$(msg "核心服务状态: 未运行" "Core service status: inactive")"
    log_info "$(msg "建议执行: sb restart --core 并检查日志" "Suggestion: run 'sb restart --core' and check logs")"
  fi
}

provider_doctor_check_runtime() {
  if [[ ! -f /etc/sing-box-deve/runtime.env ]]; then
    log_warn "$(msg "运行时状态文件缺失: /etc/sing-box-deve/runtime.env" "Runtime state file missing: /etc/sing-box-deve/runtime.env")"
    return 1
  fi
  # shellcheck disable=SC1091
  source /etc/sing-box-deve/runtime.env
  log_success "$(msg "运行时状态已加载" "Runtime state loaded")"
}

provider_doctor_check_config() {
  if [[ "${engine:-}" == "sing-box" && -f "${SBD_CONFIG_DIR}/config.json" && -x "${SBD_BIN_DIR}/sing-box" ]]; then
    if "${SBD_BIN_DIR}/sing-box" check -c "${SBD_CONFIG_DIR}/config.json" >/dev/null 2>&1; then
      log_success "$(msg "sing-box 配置校验通过" "sing-box config check passed")"
    else
      log_warn "$(msg "sing-box 配置校验失败" "sing-box config check failed")"
    fi
  elif [[ "${engine:-}" == "xray" && -f "${SBD_CONFIG_DIR}/xray-config.json" && -x "${SBD_BIN_DIR}/xray" ]]; then
    if "${SBD_BIN_DIR}/xray" run -test -config "${SBD_CONFIG_DIR}/xray-config.json" >/dev/null 2>&1; then
      log_success "$(msg "xray 配置校验通过" "xray config check passed")"
    else
      log_warn "$(msg "xray 配置校验失败" "xray config check failed")"
    fi
  else
    log_warn "$(msg "未检测到可校验的配置或内核" "No valid config+engine pair found for check")"
  fi
}

provider_doctor_check_ports() {
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
      log_success "$(msg "端口监听正常: ${p} ${proto}/${port}" "Port listening: ${p} ${proto}/${port}")"
    else
      log_warn "$(msg "端口未监听: ${p} ${proto}/${port}" "Port not listening: ${p} ${proto}/${port}")"
    fi
  done
}

provider_doctor_check_nodes() {
  if [[ ! -f "$SBD_NODES_FILE" ]]; then
    log_warn "$(msg "节点文件缺失: ${SBD_NODES_FILE}" "Node file missing: ${SBD_NODES_FILE}")"
    return
  fi
  local bad_nodes
  bad_nodes="$(awk '!/^(vless|vmess|hysteria2|trojan|wireguard|anytls|socks|ss|tuic|argo-domain|warp-mode):\/\//{print NR":"$0}' "$SBD_NODES_FILE" || true)"
  if [[ -n "$bad_nodes" ]]; then
    log_warn "$(msg "节点文件中存在异常行" "Node output contains unrecognized lines")"
    printf '%s\n' "$bad_nodes"
  else
    log_success "$(msg "节点文件格式检查通过" "Node output format check passed")"
  fi
}

provider_doctor_check_tls_cert() {
  local cert key days
  if [[ "${tls_mode:-self-signed}" == "acme" ]]; then
    cert="${acme_cert_path:-}"; key="${acme_key_path:-}"
  else
    cert="${SBD_DATA_DIR}/cert.pem"; key="${SBD_DATA_DIR}/private.key"
  fi
  [[ -f "$cert" && -f "$key" ]] || {
    log_warn "$(msg "证书或私钥缺失: cert=${cert} key=${key}" "TLS cert/key missing: cert=${cert} key=${key}")"
    return
  }
  days="$(provider_cert_days_left "$cert" 2>/dev/null || true)"
  if [[ "$days" =~ ^-?[0-9]+$ ]]; then
    if (( days < 0 )); then
      log_warn "$(msg "证书已过期: ${cert}" "Certificate expired: ${cert}")"
    elif (( days <= 7 )); then
      log_warn "$(msg "证书即将过期(${days}天): ${cert}" "Certificate expires soon (${days} days): ${cert}")"
    elif (( days <= 30 )); then
      log_info "$(msg "证书剩余${days}天，建议提前续签: ${cert}" "Certificate has ${days} days left, renewal recommended: ${cert}")"
    else
      log_success "$(msg "证书有效期正常(${days}天): ${cert}" "Certificate validity OK (${days} days): ${cert}")"
    fi
  else
    log_warn "$(msg "无法解析证书有效期: ${cert}" "Unable to parse certificate expiration: ${cert}")"
  fi
}

provider_doctor_check_acme_renew() {
  if [[ "${tls_mode:-self-signed}" != "acme" ]]; then
    return
  fi
  if [[ ! -x /root/.acme.sh/acme.sh ]]; then
    log_warn "$(msg "ACME 模式已启用，但未检测到 /root/.acme.sh/acme.sh" "ACME mode enabled but /root/.acme.sh/acme.sh not found")"
    return
  fi
  if crontab -l 2>/dev/null | grep -q 'acme.sh'; then
    log_success "$(msg "检测到 acme.sh 自动续签计划（crontab）" "acme.sh auto-renew schedule found in crontab")"
  elif [[ -f /etc/cron.d/acme.sh ]]; then
    log_success "$(msg "检测到 acme.sh 自动续签计划（/etc/cron.d/acme.sh）" "acme.sh auto-renew schedule found in /etc/cron.d/acme.sh")"
  else
    log_warn "$(msg "未检测到 acme.sh 自动续签任务，建议执行 acme.sh --install-cronjob" "No acme.sh auto-renew schedule found, run acme.sh --install-cronjob")"
  fi
}

provider_doctor_check_cfg_snapshots() {
  local count latest
  count="$(provider_cfg_snapshot_ids | sed '/^$/d' | wc -l | tr -d ' ')"
  if [[ "${count:-0}" == "0" ]]; then
    log_warn "$(msg "未检测到配置快照，建议执行一次 cfg apply 生成快照" "No cfg snapshots found, run cfg apply once to create snapshots")"
    return
  fi
  latest="$(cat "$SBD_CFG_SNAPSHOT_LATEST_FILE" 2>/dev/null || true)"
  if [[ -n "$latest" && -d "${SBD_CFG_SNAPSHOT_DIR}/${latest}" ]]; then
    log_success "$(msg "配置快照链路正常: ${count} 个，latest=${latest}" "Cfg snapshots healthy: ${count}, latest=${latest}")"
  else
    log_warn "$(msg "配置快照 latest 指针异常，建议执行 cfg snapshots list 检查" "Cfg snapshots latest pointer is invalid, run cfg snapshots list")"
  fi
}

provider_doctor_check_firewall_persistence() {
  local managed_count
  managed_count="$(wc -l < "$SBD_RULES_FILE" 2>/dev/null | tr -d ' ')"
  if [[ "${managed_count:-0}" == "0" ]]; then
    log_warn "$(msg "未检测到托管防火墙规则记录" "No managed firewall rule records found")"
    return
  fi
  if systemctl is-enabled --quiet sing-box-deve-fw-replay.service 2>/dev/null; then
    log_success "$(msg "防火墙规则持久化服务已启用（fw replay）" "Firewall replay persistence service enabled")"
  else
    log_warn "$(msg "存在托管规则但 fw replay 服务未启用，建议执行 sb fw replay" "Managed rules exist but replay service disabled, run sb fw replay")"
  fi
}

provider_doctor_check_update_source() {
  local base remote
  base="$(resolve_update_base_url)"
  if [[ -z "$base" ]]; then
    log_warn "$(msg "未解析到脚本更新源（可设置 SBD_UPDATE_BASE_URL）" "Unable to resolve update source (set SBD_UPDATE_BASE_URL)")"
    return
  fi
  remote="$(fetch_remote_script_version "auto" 2>/dev/null || true)"
  [[ -n "${SBD_ACTIVE_UPDATE_BASE_URL:-}" ]] && base="${SBD_ACTIVE_UPDATE_BASE_URL}"
  if [[ -n "$remote" ]]; then
    log_success "$(msg "更新源可用: ${base} (remote=${remote})" "Update source reachable: ${base} (remote=${remote})")"
  else
    log_warn "$(msg "更新源已解析但版本探测失败: ${base}" "Update source resolved but version probe failed: ${base}")"
  fi
}

provider_doctor() {
  provider_doctor_check_service
  provider_doctor_check_runtime || return 0
  provider_doctor_check_config
  provider_doctor_check_ports
  provider_doctor_check_nodes
  provider_doctor_check_tls_cert
  provider_doctor_check_acme_renew
  provider_psiphon_doctor_check
  provider_doctor_check_cfg_snapshots
  provider_doctor_check_firewall_persistence
  provider_doctor_check_update_source
}
