#!/usr/bin/env bash

fw_command() { sbd_run_deadline "${SBD_FIREWALL_TIMEOUT:-15}" "$@"; }

# Save new tagged effects before touching the backend. A failed/partial apply
# must remain recoverable even before it enters the confirmed rule inventory.
fw_pending_rule() {
  [[ -n "${SBD_ACTIVE_TRANSACTION:-}" ]] || return 0
  printf '%s|%s|%s|%s|pending\n' "$@" >> "$SBD_ACTIVE_TRANSACTION/firewall-pending" || return 1
  sbd_sync_directory "$SBD_ACTIVE_TRANSACTION"
}

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

fw_detect_backend_optional() {
  FW_BACKEND=""
  if [[ -n "${SBD_FW_BACKEND:-}" ]]; then
    case "$SBD_FW_BACKEND" in
      ufw|firewalld|iptables|nftables) FW_BACKEND="$SBD_FW_BACKEND" ;;
      *) return 1 ;;
    esac
  elif command -v ufw >/dev/null 2>&1 && fw_command ufw status 2>/dev/null | grep -q "Status: active"; then
    FW_BACKEND="ufw"
  elif command -v firewall-cmd >/dev/null 2>&1 && fw_command firewall-cmd --state >/dev/null 2>&1; then
    FW_BACKEND="firewalld"
  elif command -v iptables >/dev/null 2>&1 && fw_command iptables -S >/dev/null 2>&1; then
    FW_BACKEND="iptables"
  elif command -v nft >/dev/null 2>&1 && fw_command nft list ruleset >/dev/null 2>&1; then
    FW_BACKEND="nftables"
  else
    return 1
  fi
  [[ -n "$FW_BACKEND" ]]
}

fw_detect_backend() {
  if ! fw_detect_backend_optional; then
    if [[ -n "${SBD_FW_BACKEND:-}" ]]; then
      die "$(msg "不支持的防火墙后端: ${SBD_FW_BACKEND}" "Unsupported firewall backend: ${SBD_FW_BACKEND}")"
    fi
    die "$(msg "未找到受支持的防火墙后端" "No supported firewall backend found")"
  fi
  log_info "$(msg "防火墙后端: ${FW_BACKEND}" "Firewall backend: ${FW_BACKEND}")"
}

fw_snapshot_create() {
  mkdir -p "$(dirname "$SBD_FW_SNAPSHOT_FILE")" || return 1
  if [[ -f "$SBD_RULES_FILE" ]]; then
    cp -f "$SBD_RULES_FILE" "$SBD_FW_SNAPSHOT_FILE" || return 1
  else
    : > "$SBD_FW_SNAPSHOT_FILE" || return 1
  fi
  log_info "$(msg "已创建防火墙快照: $SBD_FW_SNAPSHOT_FILE" "Firewall snapshot created: $SBD_FW_SNAPSHOT_FILE")"
}

fw_tag() {
  local service="$1" proto="$2" port="$3"
  load_install_context || die "$(msg "防火墙标记缺少安装上下文" "Install context missing for firewall tagging")"
  echo "MYBOX:${install_id:-unknown}:${service}:${proto}:${port}"
}

fw_endpoint_suffix_from_tag() {
  local tag="$1" rest service tag_proto tag_port
  [[ "$tag" == MYBOX:* ]] || return 1
  rest="${tag#MYBOX:*:}"
  service="${rest%%:*}"
  rest="${rest#*:}"
  tag_proto="${rest%%:*}"
  tag_port="${rest##*:}"
  [[ -n "$service" && -n "$tag_proto" && -n "$tag_port" ]] || return 1
  printf ':%s:%s:%s' "$service" "$tag_proto" "$tag_port"
}

fw_record_tag_for_endpoint() {
  local backend="$1" proto="$2" port="$3" service="${4:-core}" suffix
  [[ -f "$SBD_RULES_FILE" ]] || return 1
  suffix=":${service}:${proto}:${port}"
  awk -F'|' -v b="$backend" -v pr="$proto" -v po="$port" -v s="$suffix" '
    $1 == b && $2 == pr && $3 == po && index($4, "MYBOX:") == 1 && substr($4, length($4) - length(s) + 1) == s { print $4; exit }
  ' "$SBD_RULES_FILE"
}

fw_records_for_endpoint() {
  local backend="$1" proto="$2" port="$3" service="${4:-core}" suffix
  [[ -f "$SBD_RULES_FILE" ]] || return 0
  suffix=":${service}:${proto}:${port}"
  awk -F'|' -v b="$backend" -v pr="$proto" -v po="$port" -v s="$suffix" '
    (b == "" || $1 == b) && $2 == pr && $3 == po && index($4, "MYBOX:") == 1 && substr($4, length($4) - length(s) + 1) == s { print $1 "|" $2 "|" $3 "|" $4 }
  ' "$SBD_RULES_FILE"
}

fw_apply_protocol_rule() {
  local transports proto
  transports="$(protocol_transports "$1")" || return 1
  for proto in $transports; do
    fw_apply_rule "$proto" "$2" || return 1
  done
}

fw_records_for_protocol_endpoint() {
  local transports proto
  transports="$(protocol_transports "$2")" || return 1
  for proto in $transports; do
    fw_records_for_endpoint "$1" "$proto" "$3" core || return 1
  done
}

fw_record_rule() {
  local backend="$1" proto="$2" port="$3" tag="$4"
  local created_at tmp_rules endpoint_suffix

  fw_validate_port_proto "$port" "$proto"
  fw_validate_tag "$tag"
  endpoint_suffix="$(fw_endpoint_suffix_from_tag "$tag" 2>/dev/null || true)"

  created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  tmp_rules="${SBD_RULES_FILE}.tmp.$$"
  mkdir -p "$(dirname "$SBD_RULES_FILE")" || return 1
  (
    if [[ -f "$SBD_RULES_FILE" ]]; then
      if [[ -n "$endpoint_suffix" ]]; then
        awk -F'|' -v b="$backend" -v pr="$proto" -v po="$port" -v t="$tag" -v s="$endpoint_suffix" '
          $4 == t { next }
          $1 == b && $2 == pr && $3 == po && index($4, "MYBOX:") == 1 && substr($4, length($4) - length(s) + 1) == s { next }
          { print }
        ' "$SBD_RULES_FILE" || return 1
      else
        awk -F'|' -v t="$tag" '$4 != t' "$SBD_RULES_FILE" || return 1
      fi
    fi
    printf '%s|%s|%s|%s|%s\n' "$backend" "$proto" "$port" "$tag" "$created_at"
  ) > "$tmp_rules" || { rm -f "$tmp_rules"; return 1; }
  mv "$tmp_rules" "$SBD_RULES_FILE" || { rm -f "$tmp_rules"; return 1; }
}

fw_enable_replay_service() {
  local script_cmd="${SBD_LAUNCHER_PATH:-/usr/local/bin/sb}"
  [[ "${SBD_USER_MODE:-false}" != true || -n "${SBD_LAUNCHER_PATH:-}" ]] || script_cmd="$HOME/.local/bin/sb"
  detect_init_system
  if [[ "$SBD_INIT_SYSTEM" == "systemd" ]]; then
    local service_tmp
    mkdir -p "$(dirname "$SBD_FW_REPLAY_SERVICE_FILE")" || return 1
    service_tmp="$(mktemp "$SBD_FW_REPLAY_SERVICE_FILE.tmp.XXXXXX")" || return 1
    cat > "$service_tmp" <<EOF
# Managed by sing-box-deve: service-v1
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
    sbd_host_file_publish "$SBD_FW_REPLAY_SERVICE_FILE" "$service_tmp" || return 1
  fi
  sbd_service_enable_oneshot "sing-box-deve-fw-replay" "${script_cmd} fw replay"
}

fw_rule_exists_record() {
  local tag="$1"
  [[ -f "$SBD_RULES_FILE" ]] && grep -Fq "|${tag}|" "$SBD_RULES_FILE"
}

fw_remove_record_by_tag() {
  local tag="$1" tmp_rules
  [[ -n "$tag" && -f "$SBD_RULES_FILE" ]] || return 0
  tmp_rules="${SBD_RULES_FILE}.tmp.$$"
  awk -F'|' -v t="$tag" '$4 != t' "$SBD_RULES_FILE" > "$tmp_rules" || { rm -f "$tmp_rules"; return 1; }
  mv "$tmp_rules" "$SBD_RULES_FILE" || return 1
}

# nft uses the same exit status for a missing chain and an inspection error.
# A successful table/chain inventory is required to prove absence.
fw_nft_chain_output() {
  local output
  output="$(fw_command nft list tables)" || return 2
  grep -Fxq 'table inet sing_box_deve' <<< "$output" || return 1
  output="$(fw_command nft list table inet sing_box_deve)" || return 2
  grep -Eq '^[[:space:]]*chain input \{' <<< "$output" || return 1
  fw_command nft -a list chain inet sing_box_deve input || return 2
}

# Presence is tri-state: 0 present, 1 absent, 2 inspection failed.
fw_backend_rule_present() {
  local backend="$1" proto="$2" port="$3" tag="$4" output rc
  case "$backend" in
    ufw)
      output="$(fw_command ufw status numbered)" || return 2
      awk -v tag="$tag" '$NF == tag {found=1} END {exit !found}' <<< "$output" ;;
    nftables)
      output="$(fw_nft_chain_output)" || {
        rc=$?; (( rc == 1 )) && return 1; return 2;
      }
      grep -Fq "comment \"$tag\"" <<< "$output" ;;
    firewalld)
      fw_command firewall-cmd --query-port="${port}/${proto}" >/dev/null 2>&1 || {
        rc=$?; (( rc == 1 )) && return 1; return 2;
      }
      fw_command firewall-cmd --permanent --query-port="${port}/${proto}" >/dev/null 2>&1 || {
        rc=$?; (( rc == 1 )) && return 1; return 2;
      } ;;
    iptables)
      fw_command iptables -C SING_BOX_DEVE_INPUT -p "$proto" --dport "$port" -m comment --comment "$tag" -j ACCEPT >/dev/null 2>&1 || {
        rc=$?; (( rc == 1 )) && return 1; return 2;
      } ;;
    *) return 2 ;;
  esac
}

fw_apply_rule_to_backend() {
  local backend="$1" proto="$2" port="$3" tag="$4" rc
  fw_validate_port_proto "$port" "$proto" || return 1
  fw_validate_tag "$tag" || return 1
  if fw_backend_rule_present "$backend" "$proto" "$port" "$tag"; then return 0
  else rc=$?; (( rc == 1 )) || return 1; fi
  case "$backend" in
    ufw)
      fw_command ufw allow "${port}/${proto}" comment "$tag" >/dev/null || return 1 ;;
    nftables)
      fw_command nft list table inet sing_box_deve >/dev/null 2>&1 || fw_command nft add table inet sing_box_deve || return 1
      fw_command nft list chain inet sing_box_deve input >/dev/null 2>&1 || fw_command nft add chain inet sing_box_deve input '{ type filter hook input priority 0; policy accept; }' || return 1
      fw_command nft add rule inet sing_box_deve input "$proto" dport "$port" counter accept comment \""$tag"\" || return 1 ;;
    firewalld)
      fw_command firewall-cmd --permanent --add-port="${port}/${proto}" >/dev/null || return 1
      fw_command firewall-cmd --add-port="${port}/${proto}" >/dev/null || return 1 ;;
    iptables)
      fw_command iptables -N SING_BOX_DEVE_INPUT >/dev/null 2>&1 || fw_command iptables -S SING_BOX_DEVE_INPUT >/dev/null || return 1
      fw_command iptables -C INPUT -j SING_BOX_DEVE_INPUT >/dev/null 2>&1 || fw_command iptables -I INPUT -j SING_BOX_DEVE_INPUT || return 1
      fw_command iptables -A SING_BOX_DEVE_INPUT -p "$proto" --dport "$port" -m comment --comment "$tag" -j ACCEPT || return 1 ;;
    *) return 1 ;;
  esac
  fw_backend_rule_present "$backend" "$proto" "$port" "$tag"
}

fw_apply_rule() {
  local proto="$1" port="$2" service="${3:-core}" tag tracked_tag rc

  fw_validate_port_proto "$port" "$proto"
  tag="$(fw_tag "$service" "$proto" "$port")"
  fw_validate_tag "$tag"

  tracked_tag="$(fw_record_tag_for_endpoint "$FW_BACKEND" "$proto" "$port" "$service" 2>/dev/null || true)"
  if [[ -n "$tracked_tag" ]]; then
    fw_validate_tag "$tracked_tag"
    if fw_backend_rule_present "$FW_BACKEND" "$proto" "$port" "$tracked_tag"; then
      log_info "$(msg "防火墙规则已存在且后端可见: $tracked_tag" "Firewall rule already tracked and present: $tracked_tag")"
      return 0
    fi
    log_warn "$(msg "防火墙记录存在但后端缺失，正在重放: $tracked_tag" "Firewall record exists but backend rule is missing; replaying: $tracked_tag")"
    fw_apply_rule_to_backend "$FW_BACKEND" "$proto" "$port" "$tracked_tag" || return 1
    fw_enable_replay_service || return 1
    log_success "$(msg "已恢复防火墙规则: ${proto}/${port}" "Firewall rule restored: ${proto}/${port}")"
    return 0
  fi

  if [[ "$FW_BACKEND" == firewalld ]]; then
    local scope
    for scope in runtime permanent; do
      local flags=()
      [[ "$scope" != permanent ]] || flags=(--permanent)
      if fw_command firewall-cmd "${flags[@]}" --query-port="${port}/${proto}" >/dev/null 2>&1; then
        log_warn "firewalld port ${port}/${proto} already exists; leaving it unmanaged"
        return 0
      else rc=$?; (( rc == 1 )) || return 1; fi
    done
  fi

  fw_pending_rule "$FW_BACKEND" "$proto" "$port" "$tag" || return 1
  fw_apply_rule_to_backend "$FW_BACKEND" "$proto" "$port" "$tag" || return 1

  fw_record_rule "$FW_BACKEND" "$proto" "$port" "$tag" || return 1
  fw_enable_replay_service || return 1
  log_success "$(msg "已应用防火墙规则: ${proto}/${port}" "Firewall rule applied: ${proto}/${port}")"
}
