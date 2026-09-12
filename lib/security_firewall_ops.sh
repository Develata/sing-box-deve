#!/usr/bin/env bash

fw_replay() {
  [[ -s "$SBD_RULES_FILE" ]] || {
    log_info "$(msg "没有可重放的托管防火墙规则" "No managed firewall rules to replay")"
    return 0
  }

  local backend proto port tag _created
  while IFS='|' read -r backend proto port tag _created; do
    [[ -n "$backend" && -n "$proto" && -n "$port" && -n "$tag" ]] || continue
    if ! ( fw_validate_port_proto "$port" "$proto"; fw_validate_tag "$tag" ); then
      log_warn "$(msg "非法防火墙规则记录: ${backend}|${proto}|${port}|${tag}" "Invalid firewall rule record: ${backend}|${proto}|${port}|${tag}")"
      return 1
    fi
    fw_apply_rule_to_backend "$backend" "$proto" "$port" "$tag" || return 1
  done < "$SBD_RULES_FILE"
  log_success "$(msg "托管防火墙规则重放完成" "Managed firewall rules replayed")"
}

fw_remove_rule_by_record() {
  local backend="$1" proto="$2" port="$3" tag="$4" output item rc
  fw_validate_port_proto "$port" "$proto" || return 1
  fw_validate_tag "$tag" || return 1
  sbd_positive_seconds "${SBD_FIREWALL_TIMEOUT:-15}" || return 2
  case "$backend" in
    ufw)
      output="$(fw_command ufw status numbered)" || return 1
      output="$(awk -v tag="$tag" '$NF == tag' <<< "$output" | sed -nE 's/^\[ *([0-9]+)\].*/\1/p' | sort -rn)" || return 1
      while read -r item; do
        [[ -n "$item" ]] || continue
        fw_command ufw --force delete "$item" >/dev/null || return 1
      done <<< "$output" ;;
    nftables)
      output="$(fw_nft_chain_output)" || {
        rc=$?; (( rc == 1 )) && return 0; return 1;
      }
      output="$(awk -v tag="\"$tag\"" '{for(i=1;i<=NF;i++) if($i=="comment" && $(i+1)==tag) print $NF}' <<< "$output")" || return 1
      while read -r item; do
        [[ -n "$item" ]] || continue
        [[ "$item" =~ ^[0-9]+$ ]] || return 1
        fw_command nft delete rule inet sing_box_deve input handle "$item" || return 1
      done <<< "$output" ;;
    firewalld)
      local scope flags
      for scope in runtime permanent; do
        flags=()
        [[ "$scope" != permanent ]] || flags=(--permanent)
        if fw_command firewall-cmd "${flags[@]}" --query-port="${port}/${proto}" >/dev/null 2>&1; then
          fw_command firewall-cmd "${flags[@]}" --remove-port="${port}/${proto}" >/dev/null || return 1
          if fw_command firewall-cmd "${flags[@]}" --query-port="${port}/${proto}" >/dev/null 2>&1; then return 1
          else rc=$?; (( rc == 1 )) || return 1; fi
        else rc=$?; (( rc == 1 )) || return 1; fi
      done ;;
    iptables)
      local deadline=$((SECONDS + ${SBD_FIREWALL_TIMEOUT:-15})) remaining
      while (( SECONDS < deadline )); do
        remaining=$((deadline - SECONDS))
        if SBD_FIREWALL_TIMEOUT="$remaining" fw_backend_rule_present "$backend" "$proto" "$port" "$tag"; then
          remaining=$((deadline - SECONDS))
          (( remaining > 0 )) || break
          SBD_FIREWALL_TIMEOUT="$remaining" fw_command iptables -D SING_BOX_DEVE_INPUT -p "$proto" --dport "$port" -m comment --comment "$tag" -j ACCEPT >/dev/null 2>&1 || return 1
        else rc=$?; (( rc == 1 )) && return 0; return 1; fi
      done
      log_error "Firewall rule removal timed out: $tag"
      return 1 ;;
    *) return 1 ;;
  esac
  if fw_backend_rule_present "$backend" "$proto" "$port" "$tag"; then return 1
  else rc=$?; (( rc == 1 )); fi
}

fw_clear_managed_rules() {
  if [[ ! -s "$SBD_RULES_FILE" ]]; then
    fw_cleanup_nftables_table
    return $?
  fi

  local backend proto port tag _created last_backend=""
  while IFS='|' read -r backend proto port tag _created; do
    [[ -z "$backend" ]] && continue
    fw_remove_rule_by_record "$backend" "$proto" "$port" "$tag" || return 1
    last_backend="$backend"
  done < "$SBD_RULES_FILE"

  : > "$SBD_RULES_FILE" || return 1
  if [[ "$last_backend" == "nftables" ]]; then
    fw_cleanup_nftables_table
  fi
}

fw_collect_core_ports() {
  [[ -s "$SBD_RULES_FILE" ]] || return 0
  awk -F'|' '
    $4 ~ /^MYBOX:[^|]+:core:/ && $3 ~ /^[0-9]+$/ { print $3 }
  ' "$SBD_RULES_FILE" | sort -n -u
}

fw_clear_legacy_iptables_core_rules() {
  command -v iptables >/dev/null 2>&1 || return 0
  [[ -s "$SBD_RULES_FILE" ]] || return 0

  local port proto deadline remaining rc
  sbd_positive_seconds "${SBD_FIREWALL_TIMEOUT:-15}" || return 2
  while read -r port; do
    [[ -n "$port" ]] || continue
    for proto in tcp udp; do
      deadline=$((SECONDS + ${SBD_FIREWALL_TIMEOUT:-15}))
      while true; do
        remaining=$((deadline - SECONDS))
        (( remaining > 0 )) || return 1
        if SBD_FIREWALL_TIMEOUT="$remaining" fw_command iptables -C INPUT -p "$proto" --dport "$port" -j ACCEPT >/dev/null 2>&1; then
          remaining=$((deadline - SECONDS))
          (( remaining > 0 )) || return 1
          SBD_FIREWALL_TIMEOUT="$remaining" fw_command iptables -D INPUT -p "$proto" --dport "$port" -j ACCEPT >/dev/null 2>&1 || return 1
          log_info "Removed legacy direct firewall rule: ${proto}/${port}"
        else rc=$?; (( rc == 1 )) || return 1; break; fi
      done
    done
  done < <(fw_collect_core_ports)
  return 0
}

fw_cleanup_nftables_table() {
  if command -v nft >/dev/null 2>&1; then
    fw_command nft delete chain inet sing_box_deve input 2>/dev/null || true
    fw_command nft delete table inet sing_box_deve 2>/dev/null || true
  fi
}

fw_rollback() {
  if [[ ! -f "$SBD_FW_SNAPSHOT_FILE" ]]; then
    die "$(msg "未找到防火墙快照" "No firewall snapshot found")"
  fi

  log_warn "$(msg "正在回滚托管防火墙规则" "Rolling back managed firewall rules")"
  fw_clear_managed_rules || return 1

  if [[ -s "$SBD_FW_SNAPSHOT_FILE" ]]; then
    local backend proto port tag _created
    while IFS='|' read -r backend proto port tag _created; do
      [[ -z "$backend" ]] && continue
      if ! ( fw_validate_port_proto "$port" "$proto"; fw_validate_tag "$tag" ); then
        log_warn "$(msg "非法防火墙快照记录: ${backend}|${proto}|${port}|${tag}" "Invalid firewall snapshot record: ${backend}|${proto}|${port}|${tag}")"
        return 1
      fi
      fw_apply_rule_to_backend "$backend" "$proto" "$port" "$tag" || return 1
      printf '%s|%s|%s|%s|%s\n' "$backend" "$proto" "$port" "$tag" "rollback" >> "$SBD_RULES_FILE" || return 1
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

  local detected_backend="" backend proto port tag _created state
  log_info "$(msg "托管防火墙规则:" "Managed firewall records:")"
  awk -F'|' '{printf "- backend=%s proto=%s port=%s tag=%s\n", $1, $2, $3, $4}' "$SBD_RULES_FILE"

  if fw_detect_backend_optional; then
    detected_backend="$FW_BACKEND"
    log_info "$(msg "当前可检测后端: ${detected_backend}" "Detected backend: ${detected_backend}")"
  else
    log_warn "$(msg "未能检测可用防火墙后端；跳过后端存在性检查" "No usable firewall backend detected; backend presence check skipped")"
    return 0
  fi

  log_info "$(msg "后端规则存在性:" "Backend rule presence:")"
  while IFS='|' read -r backend proto port tag _created; do
    [[ -n "$backend" && -n "$proto" && -n "$port" && -n "$tag" ]] || continue
    if ! ( fw_validate_port_proto "$port" "$proto"; fw_validate_tag "$tag" ) >/dev/null 2>&1; then
      printf -- '- backend=%s proto=%s port=%s tag=%s state=invalid-record\n' "$backend" "$proto" "$port" "$tag"
      continue
    fi
    if [[ "$backend" != "$detected_backend" ]]; then
      printf -- '- backend=%s proto=%s port=%s tag=%s state=skipped-current-backend-%s\n' "$backend" "$proto" "$port" "$tag" "$detected_backend"
      continue
    fi
    if fw_backend_rule_present "$backend" "$proto" "$port" "$tag"; then
      state="present"
    else
      state="missing"
    fi
    printf -- '- backend=%s proto=%s port=%s tag=%s state=%s\n' "$backend" "$proto" "$port" "$tag" "$state"
  done < "$SBD_RULES_FILE"
}
