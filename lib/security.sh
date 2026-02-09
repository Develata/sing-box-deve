#!/usr/bin/env bash
FW_BACKEND=""
SBD_FW_REPLAY_SERVICE_FILE="/etc/systemd/system/sing-box-deve-fw-replay.service"

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
  local created_at
  created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  printf '%s|%s|%s|%s|%s\n' "$backend" "$proto" "$port" "$tag" "$created_at" >> "$SBD_RULES_FILE"
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
  tag="$(fw_tag "$service" "$proto" "$port")"

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
    return 0
  fi

  local backend proto port tag _created
  while IFS='|' read -r backend proto port tag _created; do
    [[ -z "$backend" ]] && continue
    fw_remove_rule_by_record "$backend" "$proto" "$port" "$tag"
  done < "$SBD_RULES_FILE"

  : > "$SBD_RULES_FILE"
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
