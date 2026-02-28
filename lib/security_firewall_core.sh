#!/usr/bin/env bash

fw_validate_port_proto() {
  local port="$1" proto="$2"
  if [[ ! "$port" =~ ^[0-9]+$ ]]; then
    die "$(msg "无效端口: $port (必须是数字)" "Invalid port: $port (must be numeric)")"
  fi
  if [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
    die "$(msg "端口超出范围: $port (1-65535)" "Port out of range: $port (1-65535)")"
  fi
  if [[ "$proto" != "tcp" && "$proto" != "udp" ]]; then
    die "$(msg "无效协议: $proto (必须是 tcp 或 udp)" "Invalid protocol: $proto (must be tcp or udp)")"
  fi
}

fw_validate_tag() {
  local tag="$1"
  if [[ ! "$tag" =~ ^[a-zA-Z0-9:_-]+$ ]]; then
    die "$(msg "无效标签格式: $tag" "Invalid tag format: $tag")"
  fi
}

fw_detect_backend() {
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    FW_BACKEND="ufw"
  elif command -v nft >/dev/null 2>&1 && nft list ruleset >/dev/null 2>&1; then
    FW_BACKEND="nftables"
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    FW_BACKEND="firewalld"
  elif command -v iptables >/dev/null 2>&1; then
    FW_BACKEND="iptables"
  else
    die "$(msg "未找到受支持的防火墙后端" "No supported firewall backend found")"
  fi
  log_info "$(msg "防火墙后端: ${FW_BACKEND}" "Firewall backend: ${FW_BACKEND}")"
}

fw_snapshot_create() {
  cp -f "$SBD_RULES_FILE" "$SBD_FW_SNAPSHOT_FILE"
  log_info "$(msg "已创建防火墙快照: $SBD_FW_SNAPSHOT_FILE" "Firewall snapshot created: $SBD_FW_SNAPSHOT_FILE")"
}

fw_tag() {
  local service="$1" proto="$2" port="$3"
  load_install_context || die "$(msg "防火墙标记缺少安装上下文" "Install context missing for firewall tagging")"
  echo "MYBOX:${install_id:-unknown}:${service}:${proto}:${port}"
}

fw_record_rule() {
  local backend="$1" proto="$2" port="$3" tag="$4"
  local created_at tmp_rules

  fw_validate_port_proto "$port" "$proto"
  fw_validate_tag "$tag"

  created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  tmp_rules="${SBD_RULES_FILE}.tmp.$$"
  {
    [[ -f "$SBD_RULES_FILE" ]] && cat "$SBD_RULES_FILE"
    printf '%s|%s|%s|%s|%s\n' "$backend" "$proto" "$port" "$tag" "$created_at"
  } > "$tmp_rules"
  mv "$tmp_rules" "$SBD_RULES_FILE"
}

fw_enable_replay_service() {
  local script_cmd="/usr/local/bin/sb"
  detect_init_system
  if [[ "$SBD_INIT_SYSTEM" == "systemd" ]]; then
    cat > "$SBD_FW_REPLAY_SERVICE_FILE" <<EOF
[Unit]
Description=sing-box-deve firewall replay
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${script_cmd} fw replay

[Install]
WantedBy=multi-user.target
EOF
  fi
  sbd_service_enable_oneshot "sing-box-deve-fw-replay" "${script_cmd} fw replay"
}

fw_rule_exists_record() {
  local tag="$1"
  grep -Fq "|${tag}|" "$SBD_RULES_FILE"
}

fw_apply_rule() {
  local proto="$1" port="$2" service="core" tag

  fw_validate_port_proto "$port" "$proto"
  tag="$(fw_tag "$service" "$proto" "$port")"
  fw_validate_tag "$tag"

  if fw_rule_exists_record "$tag"; then
    log_info "$(msg "防火墙规则已存在记录: $tag" "Firewall rule already tracked: $tag")"
    return 0
  fi

  case "$FW_BACKEND" in
    ufw)
      ufw allow "${port}/${proto}" comment "$tag" >/dev/null
      ;;
    nftables)
      nft list table inet sing_box_deve >/dev/null 2>&1 || nft add table inet sing_box_deve
      nft list chain inet sing_box_deve input >/dev/null 2>&1 || nft add chain inet sing_box_deve input '{ type filter hook input priority 0; policy accept; }'
      nft add rule inet sing_box_deve input "$proto" dport "$port" counter accept comment \""$tag"\"
      ;;
    firewalld)
      firewall-cmd --permanent --add-port="${port}/${proto}" >/dev/null
      firewall-cmd --add-port="${port}/${proto}" >/dev/null
      ;;
    iptables)
      iptables -N SING_BOX_DEVE_INPUT >/dev/null 2>&1 || true
      iptables -C INPUT -j SING_BOX_DEVE_INPUT >/dev/null 2>&1 || iptables -I INPUT -j SING_BOX_DEVE_INPUT
      iptables -C SING_BOX_DEVE_INPUT -p "$proto" --dport "$port" -m comment --comment "$tag" -j ACCEPT >/dev/null 2>&1 || \
        iptables -A SING_BOX_DEVE_INPUT -p "$proto" --dport "$port" -m comment --comment "$tag" -j ACCEPT
      ;;
    *) die "$(msg "不支持的防火墙后端: $FW_BACKEND" "Unsupported firewall backend: $FW_BACKEND")" ;;
  esac

  fw_record_rule "$FW_BACKEND" "$proto" "$port" "$tag"
  fw_enable_replay_service
  log_success "$(msg "已应用防火墙规则: ${proto}/${port}" "Firewall rule applied: ${proto}/${port}")"
}
