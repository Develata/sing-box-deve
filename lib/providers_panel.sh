#!/usr/bin/env bash

provider_i18n_value() {
  local value="${1:-}"
  case "$value" in
    running) msg "运行中" "running" ;;
    stopped) msg "已停止" "stopped" ;;
    off) msg "关闭" "off" ;;
    unknown) msg "未知" "unknown" ;;
    yes) msg "是" "yes" ;;
    no) msg "否" "no" ;;
    direct) msg "直连" "direct" ;;
    global-proxy) msg "全局代理" "global-proxy" ;;
    cn-direct) msg "国内直连" "cn-direct" ;;
    cn-proxy) msg "国内代理" "cn-proxy" ;;
    auto) msg "自动" "auto" ;;
    self-signed) msg "自签名" "self-signed" ;;
    none) msg "无" "none" ;;
    n/a) msg "无" "n/a" ;;
    *) echo "$value" ;;
  esac
}

provider_i18n_upgrade() {
  local value="${1:-unknown}"
  case "$value" in
    yes) msg "可升级" "yes" ;;
    no) msg "无需升级" "no" ;;
    *) msg "未知" "unknown" ;;
  esac
}

provider_status_header() {
  local core_state="unknown"
  local argo_state="off"
  local psiphon_state="off"
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
  if [[ -f "$SBD_PSIPHON_SERVICE_FILE" ]]; then
    if systemctl is-active --quiet sing-box-deve-psiphon.service; then
      psiphon_state="running"
    else
      psiphon_state="stopped"
    fi
  fi
  log_info "$(msg "状态: 核心=$(provider_i18n_value "$core_state") argo=$(provider_i18n_value "$argo_state") psiphon=$(provider_i18n_value "$psiphon_state")" "State: core=${core_state} argo=${argo_state} psiphon=${psiphon_state}")"

  if [[ -f /etc/sing-box-deve/runtime.env ]]; then
    sbd_load_runtime_env /etc/sing-box-deve/runtime.env
    log_info "$(msg "环境: ${provider:-unknown} | 规格: ${profile:-unknown} | 内核: ${engine:-unknown}" "Provider: ${provider:-unknown} | Profile: ${profile:-unknown} | Engine: ${engine:-unknown}")"
    log_info "$(msg "协议: ${protocols:-none}" "Protocols: ${protocols:-none}")"
    log_info "$(msg "Argo: $(provider_i18n_value "${argo_mode:-off}") | Psiphon: enable=${psiphon_enable:-off},mode=${psiphon_mode:-off},region=${psiphon_region:-auto} | WARP: $(provider_i18n_value "${warp_mode:-off}") | 路由: $(provider_i18n_value "${route_mode:-direct}") | 出站: $(provider_i18n_value "${outbound_proxy_mode:-direct}")" "Argo: ${argo_mode:-off} | Psiphon: enable=${psiphon_enable:-off},mode=${psiphon_mode:-off},region=${psiphon_region:-auto} | WARP: ${warp_mode:-off} | Route: ${route_mode:-direct} | Egress: ${outbound_proxy_mode:-direct}")"
    log_info "$(msg "IP 优先级: $(provider_i18n_value "${ip_preference:-auto}") | TLS: $(provider_i18n_value "${tls_mode:-self-signed}") | CDN 主机: ${cdn_template_host:-$(provider_i18n_value auto)}" "IP preference: ${ip_preference:-auto} | TLS: ${tls_mode:-self-signed} | CDN host: ${cdn_template_host:-auto}")"
    log_info "$(msg "端口出站映射: ${port_egress_map:-<未设置>}" "Port egress map: ${port_egress_map:-<empty>}")"
    provider_panel_tls_warning "${tls_mode:-self-signed}" "${acme_cert_path:-}" "${acme_key_path:-}"
    log_info "$(msg "分流域名: 直连='${domain_split_direct:-}' 代理='${domain_split_proxy:-}' 屏蔽='${domain_split_block:-}'" "Domain split: direct='${domain_split_direct:-}' proxy='${domain_split_proxy:-}' block='${domain_split_block:-}'")"
    log_info "$(msg "分享出口: direct='${direct_share_endpoints:-}' proxy='${proxy_share_endpoints:-}' warp='${warp_share_endpoints:-}'" "Share endpoints: direct='${direct_share_endpoints:-}' proxy='${proxy_share_endpoints:-}' warp='${warp_share_endpoints:-}'")"

    local main_port="n/a"
    if [[ "${engine:-}" == "sing-box" && -f "${SBD_CONFIG_DIR}/config.json" ]]; then
      main_port="$(jq -r '.inbounds[0] | (.listen_port // .port // "n/a")' "${SBD_CONFIG_DIR}/config.json" 2>/dev/null || true)"
    elif [[ "${engine:-}" == "xray" && -f "${SBD_CONFIG_DIR}/xray-config.json" ]]; then
      main_port="$(jq -r '.inbounds[0] | (.port // "n/a")' "${SBD_CONFIG_DIR}/xray-config.json" 2>/dev/null || true)"
    fi
    local pub_ip
    pub_ip="$(detect_public_ip)"
    log_info "$(msg "公网IP: ${pub_ip} | 主端口: ${main_port}" "PublicIP: ${pub_ip} | MainPort: ${main_port}")"
  else
    log_warn "$(msg "未找到运行时状态文件 (/etc/sing-box-deve/runtime.env)" "Runtime state not found (/etc/sing-box-deve/runtime.env)")"
  fi

  if [[ -f "$SBD_SERVICE_FILE" ]]; then
    if systemctl is-active --quiet sing-box-deve.service; then
      log_success "$(msg "核心服务: 运行中" "Core service: running")"
    else
      log_warn "$(msg "核心服务: 未运行" "Core service: not running")"
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
  log_info "$(msg "脚本: 本地=${script_local} 远端=${script_remote:-n/a} 升级=$(provider_i18n_upgrade "$script_upgrade")" "Script: local=${script_local} remote=${script_remote:-n/a} upgrade=${script_upgrade}")"

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
      log_info "$(msg "sing-box: 本地=${sbver} 远端=${sb_remote:-n/a} 升级=$(provider_i18n_upgrade "$sb_upgrade")" "sing-box: local=${sbver} remote=${sb_remote:-n/a} upgrade=${sb_upgrade}")"
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
      log_info "$(msg "xray: 本地=${xver} 远端=${x_remote:-n/a} 升级=$(provider_i18n_upgrade "$x_upgrade")" "xray: local=${xver} remote=${x_remote:-n/a} upgrade=${x_upgrade}")"
    fi
  fi

  if [[ -x "${SBD_BIN_DIR}/cloudflared" ]]; then
    local cver
    cver="$("${SBD_BIN_DIR}/cloudflared" --version 2>/dev/null | awk '{print $3}' | head -n1)"
    [[ -n "$cver" ]] && log_info "$(msg "cloudflared 版本: ${cver}" "cloudflared version: ${cver}")"
    if [[ -f "$SBD_ARGO_SERVICE_FILE" ]]; then
      if systemctl is-active --quiet sing-box-deve-argo.service; then
        log_success "$(msg "Argo 边车: 运行中" "Argo sidecar: running")"
      else
        log_warn "$(msg "Argo 边车: 未运行" "Argo sidecar: not running")"
      fi
    fi
  fi

  if [[ -f "$SBD_PSIPHON_SERVICE_FILE" ]]; then
    local psiphon_ip
    if systemctl is-active --quiet sing-box-deve-psiphon.service; then
      psiphon_ip="$(provider_psiphon_detect_exit_ip || true)"
      log_success "$(msg "Psiphon 边车: 运行中 (出口IP=${psiphon_ip:-unknown})" "Psiphon sidecar: running (exit_ip=${psiphon_ip:-unknown})")"
    else
      log_warn "$(msg "Psiphon 边车: 未运行" "Psiphon sidecar: not running")"
    fi
  fi

  if [[ -f "$SBD_NODES_FILE" ]]; then
    log_info "$(msg "节点文件: $SBD_NODES_FILE" "Nodes file: $SBD_NODES_FILE")"
  fi
}

provider_panel_tls_warning() {
  local tls_mode="$1" acme_cert="$2" _acme_key="$3" cert="" days=""
  if [[ "$tls_mode" == "acme" && -n "$acme_cert" ]]; then
    cert="$acme_cert"
  elif [[ "$tls_mode" == "self-signed" ]]; then
    cert="${SBD_DATA_DIR}/cert.pem"
  fi
  [[ -n "$cert" && -f "$cert" ]] || return 0
  if declare -F provider_cert_days_left >/dev/null 2>&1; then
    days="$(provider_cert_days_left "$cert" 2>/dev/null || true)"
  fi
  [[ "$days" =~ ^-?[0-9]+$ ]] || return 0
  if (( days <= 7 )); then
    log_warn "$(msg "证书到期预警: ${days} 天（建议立即续签）" "Certificate expiry warning: ${days} days left (renew now)")"
  elif (( days <= 15 )); then
    log_warn "$(msg "证书到期提醒: ${days} 天（建议尽快续签）" "Certificate expiry notice: ${days} days left (renew soon)")"
  elif (( days <= 30 )); then
    log_info "$(msg "证书有效期提醒: ${days} 天（建议提前续签）" "Certificate notice: ${days} days left (plan renewal)")"
  fi
}

provider_panel() {
  local mode="${1:-compact}"
  log_info "$(msg "========== sing-box-deve 面板 ==========" "========== sing-box-deve panel ==========")"
  provider_status_header

  if [[ "$mode" == "full" ]]; then
    echo
    log_info "$(msg "----- 运行时详情 -----" "----- Runtime Details -----")"
    if [[ -f /etc/sing-box-deve/runtime.env ]]; then
      cat /etc/sing-box-deve/runtime.env
    else
      log_warn "$(msg "缺少 runtime.env" "runtime.env missing")"
    fi
    log_info "$(msg "----- 持久化设置 -----" "----- Settings -----")"
    show_settings
    log_info "$(msg "----- 防火墙托管规则 -----" "----- Managed Firewall Rules -----")"
    fw_status
  fi

  log_info "========================================="
}
