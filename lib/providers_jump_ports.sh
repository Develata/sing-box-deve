#!/usr/bin/env bash

SBD_JUMP_FILE="/var/lib/sing-box-deve/jump-ports.env"
SBD_JUMP_RULES_FILE="/var/lib/sing-box-deve/jump-rules.db"
SBD_JUMP_SERVICE_FILE="/etc/systemd/system/sing-box-deve-jump.service"

load_jump_ports() {
  [[ -f "$SBD_JUMP_FILE" ]] || return 1
  # shellcheck disable=SC1090
  source "$SBD_JUMP_FILE"
  return 0
}

jump_rule_tag() {
  local proto="$1" from_port="$2" to_port="$3"
  echo "MYBOX:JUMP:${proto}:${from_port}:${to_port}"
}

enable_jump_replay_service() {
  local script_cmd="${1:-/usr/local/bin/sb}"
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
  systemctl daemon-reload
  systemctl enable sing-box-deve-jump.service >/dev/null 2>&1 || true
}

disable_jump_replay_service() {
  if systemctl list-unit-files | grep -q '^sing-box-deve-jump.service'; then
    systemctl disable --now sing-box-deve-jump.service >/dev/null 2>&1 || true
  fi
  rm -f "$SBD_JUMP_SERVICE_FILE"
  systemctl daemon-reload
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
  : > "$SBD_JUMP_RULES_FILE"
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
          nft add rule inet sing_box_deve prerouting "$proto" dport "$p" counter redirect to ":${main_port}" comment "$tag"
        fi
        ;;
      iptables|ufw|firewalld)
        command -v iptables >/dev/null 2>&1 || die "jump set requires iptables command"
        iptables -t nat -C PREROUTING -p "$proto" --dport "$p" -m comment --comment "$tag" -j REDIRECT --to-ports "$main_port" >/dev/null 2>&1 || \
          iptables -t nat -A PREROUTING -p "$proto" --dport "$p" -m comment --comment "$tag" -j REDIRECT --to-ports "$main_port"
        ;;
      *)
        die "Unsupported firewall backend for jump: ${backend}"
        ;;
    esac

    echo "${backend}|${proto}|${p}|${main_port}|${tag}" >> "$SBD_JUMP_RULES_FILE"
    fw_apply_rule "$proto" "$p"
  done
}

provider_jump_show() {
  ensure_root
  if load_jump_ports; then
    log_info "jump protocol=${JUMP_PROTOCOL:-}"
    log_info "jump main_port=${JUMP_MAIN_PORT:-}"
    log_info "jump extra_ports=${JUMP_EXTRA_PORTS:-}"
  else
    log_info "jump not configured"
  fi
}

provider_jump_replay() {
  ensure_root
  load_jump_ports || {
    log_info "jump not configured, replay skipped"
    return 0
  }
  [[ -n "${JUMP_PROTOCOL:-}" && -n "${JUMP_MAIN_PORT:-}" && -n "${JUMP_EXTRA_PORTS:-}" ]] || die "jump config is incomplete"
  fw_detect_backend
  local map proto
  map="$(protocol_port_map "$JUMP_PROTOCOL")"
  proto="${map%%:*}"
  clear_jump_rules
  apply_jump_rules "$FW_BACKEND" "$proto" "$JUMP_MAIN_PORT" "$JUMP_EXTRA_PORTS"
  log_success "jump rules replayed"
}

provider_jump_set() {
  ensure_root
  local protocol="$1" main_port="$2" extra_ports="$3"
  [[ "$main_port" =~ ^[0-9]+$ ]] || die "main port must be numeric"
  (( main_port >= 1 && main_port <= 65535 )) || die "main port out of range"
  fw_detect_backend

  local map proto
  map="$(protocol_port_map "$protocol")"
  proto="${map%%:*}"
  mkdir -p /var/lib/sing-box-deve

  clear_jump_rules
  apply_jump_rules "$FW_BACKEND" "$proto" "$main_port" "$extra_ports"

  local script_cmd
  script_cmd="/usr/local/bin/sb"
  if [[ -f /etc/sing-box-deve/runtime.env ]]; then
    # shellcheck disable=SC1091
    source /etc/sing-box-deve/runtime.env
    if [[ -n "${script_root:-}" && -x "${script_root}/sing-box-deve.sh" ]]; then
      script_cmd="${script_root}/sing-box-deve.sh"
    fi
  fi

  cat > "$SBD_JUMP_FILE" <<EOF_JUMP
JUMP_PROTOCOL=${protocol}
JUMP_MAIN_PORT=${main_port}
JUMP_EXTRA_PORTS=${extra_ports}
EOF_JUMP

  enable_jump_replay_service "$script_cmd"

  if [[ -f /etc/sing-box-deve/runtime.env ]]; then
    # shellcheck disable=SC1091
    source /etc/sing-box-deve/runtime.env
    write_nodes_output "${engine:-sing-box}" "${protocols:-vless-reality}"
  fi
  log_success "jump ports configured"
}

provider_jump_clear() {
  ensure_root
  clear_jump_rules
  rm -f "$SBD_JUMP_FILE"
  disable_jump_replay_service
  if [[ -f /etc/sing-box-deve/runtime.env ]]; then
    # shellcheck disable=SC1091
    source /etc/sing-box-deve/runtime.env
    write_nodes_output "${engine:-sing-box}" "${protocols:-vless-reality}"
  fi
  log_success "jump ports cleared"
}
