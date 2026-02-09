#!/usr/bin/env bash
FW_BACKEND=""
SBD_FW_REPLAY_SERVICE_FILE="/etc/systemd/system/sing-box-deve-fw-replay.service"

# Priority 1.3: Validate port and protocol to prevent injection attacks
fw_validate_port_proto() {
  local port="$1" proto="$2"
  # Validate port is numeric
  if [[ ! "$port" =~ ^[0-9]+$ ]]; then
    die "$(msg "无效端口: $port (必须是数字)" "Invalid port: $port (must be numeric)")"
  fi
  # Validate port range
  if [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
    die "$(msg "端口超出范围: $port (1-65535)" "Port out of range: $port (1-65535)")"
  fi
  # Validate protocol
  if [[ "$proto" != "tcp" && "$proto" != "udp" ]]; then
    die "$(msg "无效协议: $proto (必须是 tcp 或 udp)" "Invalid protocol: $proto (must be tcp or udp)")"
  fi
}

# Validate tag to prevent command injection (alphanumeric, colon, dash, underscore only)
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
  local service="$1"
  local proto="$2"
  local port="$3"
  load_install_context || die "$(msg "防火墙标记缺少安装上下文" "Install context missing for firewall tagging")"
  echo "MYBOX:${install_id:-unknown}:${service}:${proto}:${port}"
}

fw_record_rule() {
  local backend="$1"
  local proto="$2"
  local port="$3"
  local tag="$4"
  local created_at tmp_rules

  # Priority 1.3: Validate before recording
  fw_validate_port_proto "$port" "$proto"
  fw_validate_tag "$tag"

  created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  
  # Priority 3.3: Use atomic write pattern (write to temp, then rename)
  tmp_rules="${SBD_RULES_FILE}.tmp.$$"
  {
    [[ -f "$SBD_RULES_FILE" ]] && cat "$SBD_RULES_FILE"
    printf '%s|%s|%s|%s|%s\n' "$backend" "$proto" "$port" "$tag" "$created_at"
  } > "$tmp_rules"
  mv "$tmp_rules" "$SBD_RULES_FILE"
}

fw_enable_replay_service() {
  local script_cmd="/usr/local/bin/sb"
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
  systemctl daemon-reload
  systemctl enable sing-box-deve-fw-replay.service >/dev/null 2>&1 || true
}

fw_rule_exists_record() {
  local tag="$1"
  grep -Fq "|${tag}|" "$SBD_RULES_FILE"
}

fw_apply_rule() {
  local proto="$1"
  local port="$2"
  local service="core"
  local tag

  # Priority 1.3: Validate inputs before any firewall operation
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
      nft add rule inet sing_box_deve input "$proto" dport "$port" counter accept comment "$tag"
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

fw_replay() {
  [[ -s "$SBD_RULES_FILE" ]] || {
    log_info "$(msg "没有可重放的托管防火墙规则" "No managed firewall rules to replay")"
    return 0
  }

  local backend proto port tag _created
  while IFS='|' read -r backend proto port tag _created; do
    [[ -n "$backend" && -n "$proto" && -n "$port" && -n "$tag" ]] || continue
    FW_BACKEND="$backend"
    case "$backend" in
      ufw)
        ufw allow "${port}/${proto}" comment "$tag" >/dev/null 2>&1 || true
        ;;
      nftables)
        nft list table inet sing_box_deve >/dev/null 2>&1 || nft add table inet sing_box_deve
        nft list chain inet sing_box_deve input >/dev/null 2>&1 || nft add chain inet sing_box_deve input '{ type filter hook input priority 0; policy accept; }'
        nft add rule inet sing_box_deve input "$proto" dport "$port" counter accept comment "$tag" >/dev/null 2>&1 || true
        ;;
      firewalld)
        firewall-cmd --permanent --add-port="${port}/${proto}" >/dev/null 2>&1 || true
        firewall-cmd --add-port="${port}/${proto}" >/dev/null 2>&1 || true
        ;;
      iptables)
        iptables -N SING_BOX_DEVE_INPUT >/dev/null 2>&1 || true
        iptables -C INPUT -j SING_BOX_DEVE_INPUT >/dev/null 2>&1 || iptables -I INPUT -j SING_BOX_DEVE_INPUT
        iptables -C SING_BOX_DEVE_INPUT -p "$proto" --dport "$port" -m comment --comment "$tag" -j ACCEPT >/dev/null 2>&1 || \
          iptables -A SING_BOX_DEVE_INPUT -p "$proto" --dport "$port" -m comment --comment "$tag" -j ACCEPT
        ;;
    esac
  done < "$SBD_RULES_FILE"
  log_success "$(msg "托管防火墙规则重放完成" "Managed firewall rules replayed")"
}

fw_remove_rule_by_record() {
  local backend="$1"
  local proto="$2"
  local port="$3"
  local tag="$4"

  case "$backend" in
    ufw)
      local rule_numbers
      rule_numbers="$(ufw status numbered | grep -nF "$tag" | sed 's/:.*//')"
      if [[ -n "$rule_numbers" ]]; then
        local num
        while read -r num; do
          local ufw_num
          ufw_num="$(ufw status numbered | sed -n "${num}p" | sed -E 's/^\[ *([0-9]+)\].*/\1/')"
          if [[ -n "$ufw_num" ]]; then
            ufw --force delete "$ufw_num" >/dev/null || true
          fi
        done <<< "$rule_numbers"
      fi
      ;;
    nftables)
      local handles
      handles="$(nft -a list chain inet sing_box_deve input 2>/dev/null | grep -F "$tag" | awk '{print $NF}')"
      if [[ -n "$handles" ]]; then
        local h
        while read -r h; do
          if [[ -n "$h" ]]; then
            nft delete rule inet sing_box_deve input handle "$h" >/dev/null 2>&1 || true
          fi
        done <<< "$handles"
      fi
      ;;
    firewalld)
      firewall-cmd --permanent --remove-port="${port}/${proto}" >/dev/null 2>&1 || true
      firewall-cmd --remove-port="${port}/${proto}" >/dev/null 2>&1 || true
      ;;
    iptables)
      while iptables -C SING_BOX_DEVE_INPUT -p "$proto" --dport "$port" -m comment --comment "$tag" -j ACCEPT >/dev/null 2>&1; do
        iptables -D SING_BOX_DEVE_INPUT -p "$proto" --dport "$port" -m comment --comment "$tag" -j ACCEPT >/dev/null 2>&1 || true
      done
      ;;
    *)
      log_warn "$(msg "移除时跳过未知后端: $backend" "Skipping unknown backend during remove: $backend")"
      ;;
  esac
}

fw_clear_managed_rules() {
  if [[ ! -s "$SBD_RULES_FILE" ]]; then
    # Still try to clean up nftables table if it exists
    fw_cleanup_nftables_table
    return 0
  fi

  local backend proto port tag _created last_backend=""
  while IFS='|' read -r backend proto port tag _created; do
    [[ -z "$backend" ]] && continue
    fw_remove_rule_by_record "$backend" "$proto" "$port" "$tag"
    last_backend="$backend"
  done < "$SBD_RULES_FILE"

  : > "$SBD_RULES_FILE"

  # Priority 2.3: Clean up nftables table after clearing all rules
  if [[ "$last_backend" == "nftables" ]]; then
    fw_cleanup_nftables_table
  fi
}

# Priority 2.3: Clean up nftables table and chain
fw_cleanup_nftables_table() {
  if command -v nft >/dev/null 2>&1; then
    # Delete chain first (must be empty or this will fail, which is fine)
    nft delete chain inet sing_box_deve input 2>/dev/null || true
    # Then delete the table
    nft delete table inet sing_box_deve 2>/dev/null || true
  fi
}

fw_rollback() {
  if [[ ! -f "$SBD_FW_SNAPSHOT_FILE" ]]; then
    die "$(msg "未找到防火墙快照" "No firewall snapshot found")"
  fi

  log_warn "$(msg "正在回滚托管防火墙规则" "Rolling back managed firewall rules")"
  fw_clear_managed_rules

  if [[ -s "$SBD_FW_SNAPSHOT_FILE" ]]; then
    local backend proto port tag _created
    while IFS='|' read -r backend proto port tag _created; do
      [[ -z "$backend" ]] && continue
      FW_BACKEND="$backend"
      case "$FW_BACKEND" in
        ufw)
          ufw allow "${port}/${proto}" comment "$tag" >/dev/null || true
          ;;
        nftables)
          nft list table inet sing_box_deve >/dev/null 2>&1 || nft add table inet sing_box_deve
          nft list chain inet sing_box_deve input >/dev/null 2>&1 || nft add chain inet sing_box_deve input '{ type filter hook input priority 0; policy accept; }'
          nft add rule inet sing_box_deve input "$proto" dport "$port" counter accept comment "$tag" >/dev/null 2>&1 || true
          ;;
        firewalld)
          firewall-cmd --permanent --add-port="${port}/${proto}" >/dev/null 2>&1 || true
          firewall-cmd --add-port="${port}/${proto}" >/dev/null 2>&1 || true
          ;;
        iptables)
          iptables -N SING_BOX_DEVE_INPUT >/dev/null 2>&1 || true
          iptables -C INPUT -j SING_BOX_DEVE_INPUT >/dev/null 2>&1 || iptables -I INPUT -j SING_BOX_DEVE_INPUT
          iptables -C SING_BOX_DEVE_INPUT -p "$proto" --dport "$port" -m comment --comment "$tag" -j ACCEPT >/dev/null 2>&1 || \
            iptables -A SING_BOX_DEVE_INPUT -p "$proto" --dport "$port" -m comment --comment "$tag" -j ACCEPT
          ;;
      esac
      printf '%s|%s|%s|%s|%s\n' "$backend" "$proto" "$port" "$tag" "rollback" >> "$SBD_RULES_FILE"
    done < "$SBD_FW_SNAPSHOT_FILE"
  fi

  log_success "$(msg "防火墙回滚完成" "Firewall rollback complete")"
}

fw_status() {
  log_info "$(msg "托管防火墙规则文件: $SBD_RULES_FILE" "Managed firewall rules file: $SBD_RULES_FILE")"
  if [[ ! -s "$SBD_RULES_FILE" ]]; then
    log_info "$(msg "当前没有托管防火墙规则" "No managed firewall rules")"
    return 0
  fi

  awk -F'|' '{printf "- backend=%s proto=%s port=%s tag=%s\n", $1, $2, $3, $4}' "$SBD_RULES_FILE"
}
