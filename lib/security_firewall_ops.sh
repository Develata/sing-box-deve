#!/usr/bin/env bash

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
        nft add rule inet sing_box_deve input "$proto" dport "$port" counter accept comment \"$tag\" >/dev/null 2>&1 || true
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
  local backend="$1" proto="$2" port="$3" tag="$4"

  case "$backend" in
    ufw)
      local rule_numbers
      rule_numbers="$(ufw status numbered | grep -nF "$tag" | sed 's/:.*//' || true)"
      if [[ -n "$rule_numbers" ]]; then
        local num ufw_num
        while read -r num; do
          ufw_num="$(ufw status numbered | sed -n "${num}p" | sed -E 's/^\[ *([0-9]+)\].*/\1/')"
          if [[ -n "$ufw_num" ]]; then
            ufw --force delete "$ufw_num" >/dev/null || true
          fi
        done <<< "$rule_numbers"
      fi
      ;;
    nftables)
      local handles h
      handles="$(nft -a list chain inet sing_box_deve input 2>/dev/null | grep -F "$tag" | awk '{print $NF}')"
      if [[ -n "$handles" ]]; then
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
  if [[ "$last_backend" == "nftables" ]]; then
    fw_cleanup_nftables_table
  fi
}

fw_cleanup_nftables_table() {
  if command -v nft >/dev/null 2>&1; then
    nft delete chain inet sing_box_deve input 2>/dev/null || true
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
          nft add rule inet sing_box_deve input "$proto" dport "$port" counter accept comment \"$tag\" >/dev/null 2>&1 || true
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
