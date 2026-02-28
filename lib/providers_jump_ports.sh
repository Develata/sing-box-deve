#!/usr/bin/env bash

SBD_JUMP_RULES_FILE="${SBD_STATE_DIR}/jump-rules.db"
SBD_JUMP_SERVICE_FILE="/etc/systemd/system/sing-box-deve-jump.service"

load_jump_ports() {
  jump_store_load_first
}

jump_rule_tag() {
  local proto="$1" from_port="$2" to_port="$3"
  echo "MYBOX:JUMP:${proto}:${from_port}:${to_port}"
}

enable_jump_replay_service() {
  local script_cmd="${1:-/usr/local/bin/sb}"
  detect_init_system
  if [[ "$SBD_INIT_SYSTEM" == "systemd" ]]; then
    cat > "$SBD_JUMP_SERVICE_FILE" <<EOF_UNIT
[Unit]
Description=sing-box-deve jump replay
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${script_cmd} jump replay

[Install]
WantedBy=multi-user.target
EOF_UNIT
  fi
  sbd_service_enable_oneshot "sing-box-deve-jump" "${script_cmd} jump replay"
}

disable_jump_replay_service() {
  if sbd_service_unit_exists "sing-box-deve-jump"; then
    sbd_service_disable_oneshot "sing-box-deve-jump"
  fi
  rm -f "$SBD_JUMP_SERVICE_FILE"
  sbd_service_daemon_reload
}

ensure_nft_jump_chain() {
  nft list table inet sing_box_deve >/dev/null 2>&1 || nft add table inet sing_box_deve
  nft list chain inet sing_box_deve prerouting >/dev/null 2>&1 || \
    nft add chain inet sing_box_deve prerouting '{ type nat hook prerouting priority dstnat; policy accept; }'
}

clear_jump_rules() {
  [[ -f "$SBD_JUMP_RULES_FILE" ]] || return 0
  local backend proto from_port to_port tag handles h
  while IFS='|' read -r backend proto from_port to_port tag; do
    [[ -n "$backend" ]] || continue
    case "$backend" in
      nftables)
        handles="$(nft -a list chain inet sing_box_deve prerouting 2>/dev/null | grep -F "$tag" | awk '{print $NF}')"
        if [[ -n "$handles" ]]; then
          while IFS= read -r h; do
            [[ -n "$h" ]] || continue
            nft delete rule inet sing_box_deve prerouting handle "$h" >/dev/null 2>&1 || true
          done <<< "$handles"
        fi
        ;;
      iptables|ufw|firewalld)
        command -v iptables >/dev/null 2>&1 || continue
        while iptables -t nat -C PREROUTING -p "$proto" --dport "$from_port" -m comment --comment "$tag" -j REDIRECT --to-ports "$to_port" >/dev/null 2>&1; do
          iptables -t nat -D PREROUTING -p "$proto" --dport "$from_port" -m comment --comment "$tag" -j REDIRECT --to-ports "$to_port" >/dev/null 2>&1 || true
        done
        ;;
    esac
  done < "$SBD_JUMP_RULES_FILE"
  rm -f "$SBD_JUMP_RULES_FILE"
}

apply_jump_rules() {
  local backend="$1" proto="$2" main_port="$3" extras_csv="$4"
  IFS=',' read -r -a _extras <<< "$extras_csv"

  local p tag
  for p in "${_extras[@]}"; do
    p="$(echo "$p" | xargs)"
    [[ "$p" =~ ^[0-9]+$ ]] || continue
    (( p >= 1 && p <= 65535 )) || continue
    (( p == main_port )) && continue
    tag="$(jump_rule_tag "$proto" "$p" "$main_port")"

    case "$backend" in
      nftables)
        ensure_nft_jump_chain
        if ! nft -a list chain inet sing_box_deve prerouting 2>/dev/null | grep -Fq "$tag"; then
          nft add rule inet sing_box_deve prerouting "$proto" dport "$p" counter redirect to ":${main_port}" comment \"$tag\"
        fi
        ;;
      iptables|ufw|firewalld)
        command -v iptables >/dev/null 2>&1 || die "jump set requires iptables command"
        iptables -t nat -C PREROUTING -p "$proto" --dport "$p" -m comment --comment "$tag" -j REDIRECT --to-ports "$main_port" >/dev/null 2>&1 || \
          iptables -t nat -A PREROUTING -p "$proto" --dport "$p" -m comment --comment "$tag" -j REDIRECT --to-ports "$main_port"
        ;;
      *)
        die "$(msg "跳跃复用不支持该防火墙后端: ${backend}" "Unsupported firewall backend for jump: ${backend}")"
        ;;
    esac

    echo "${backend}|${proto}|${p}|${main_port}|${tag}" >> "$SBD_JUMP_RULES_FILE"
    fw_apply_rule "$proto" "$p"
  done
}

provider_jump_show() {
  ensure_root
  local count=0 protocol main_port extras_csv
  while IFS='|' read -r protocol main_port extras_csv; do
    [[ -n "$protocol" && -n "$main_port" ]] || continue
    log_info "$(msg "jump 协议=${protocol} 主端口=${main_port} 附加端口=${extras_csv:-}" "jump protocol=${protocol} main_port=${main_port} extra_ports=${extras_csv:-}")"
    count=$((count + 1))
  done < <(jump_store_records)
  if (( count == 0 )); then
    log_info "$(msg "jump 尚未配置" "jump not configured")"
  fi
}

provider_jump_replay() {
  ensure_root
  if [[ -z "$(jump_store_records)" ]]; then
    log_info "$(msg "jump 尚未配置，跳过重放" "jump not configured, replay skipped")"
    return 0
  fi
  fw_detect_backend
  clear_jump_rules
  local protocol main_port extras_csv map proto
  while IFS='|' read -r protocol main_port extras_csv; do
    [[ -n "$protocol" && -n "$main_port" && -n "$extras_csv" ]] || continue
    if ! contains_protocol "$protocol"; then
      log_warn "$(msg "跳过非法 jump 记录: ${protocol}|${main_port}|${extras_csv}" "Skip invalid jump record: ${protocol}|${main_port}|${extras_csv}")"
      continue
    fi
    map="$(protocol_port_map "$protocol")"
    proto="${map%%:*}"
    apply_jump_rules "$FW_BACKEND" "$proto" "$main_port" "$extras_csv"
  done < <(jump_store_records)
  log_success "$(msg "jump 规则已重放" "jump rules replayed")"
}

provider_jump_set() {
  ensure_root
  local protocol="$1" main_port="$2" extra_ports="$3"
  local script_cmd normalized_extras had_old="false" old_extras=""
  provider_cfg_load_runtime_exports
  normalized_extras="$(provider_jump_validate_target "$protocol" "$main_port" "$extra_ports")"
  if jump_store_has "$protocol" "$main_port"; then
    had_old="true"
    old_extras="$(jump_store_records | awk -F'|' -v p="$protocol" -v m="$main_port" '$1==p && $2==m {print $3; exit}')"
  fi
  jump_store_set "$protocol" "$main_port" "$normalized_extras"
  if ! ( provider_jump_replay ); then
    if [[ "$had_old" == "true" ]]; then
      jump_store_set "$protocol" "$main_port" "$old_extras"
    else
      jump_store_remove "$protocol" "$main_port"
    fi
    ( provider_jump_replay ) >/dev/null 2>&1 || true
    die "Failed to apply jump rules for ${protocol}:${main_port}, state restored"
  fi

  script_cmd="/usr/local/bin/sb"
  if [[ -n "${script_root:-}" && -x "${script_root}/sing-box-deve.sh" ]]; then
    script_cmd="${script_root}/sing-box-deve.sh"
  fi
  enable_jump_replay_service "$script_cmd"

  write_nodes_output "${engine:-sing-box}" "${protocols:-vless-reality}"
  log_success "$(msg "jump 端口复用已配置" "jump ports configured")"
}

provider_jump_clear_target() {
  local protocol="$1" main_port="$2"
  [[ -n "$protocol" && -n "$main_port" ]] || return 0
  jump_store_remove "$protocol" "$main_port"
}

provider_jump_clear() {
  ensure_root
  local protocol="${1:-}" main_port="${2:-}"
  if [[ (-n "$protocol" && -z "$main_port") || (-z "$protocol" && -n "$main_port") ]]; then
    die "Usage: jump clear [protocol main_port]"
  fi
  if [[ -n "$protocol" && -n "$main_port" ]]; then
    provider_jump_clear_target "$protocol" "$main_port"
  else
    jump_store_clear
  fi
  clear_jump_rules
  if [[ -n "$(jump_store_records)" ]]; then
    provider_jump_replay
  else
    disable_jump_replay_service
  fi
  if [[ -f "${SBD_CONFIG_DIR}/runtime.env" ]]; then
    sbd_load_runtime_env "${SBD_CONFIG_DIR}/runtime.env"
    write_nodes_output "${engine:-sing-box}" "${protocols:-vless-reality}"
  fi
  log_success "$(msg "jump 端口复用已清除" "jump ports cleared")"
}
