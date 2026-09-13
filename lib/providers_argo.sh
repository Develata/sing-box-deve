#!/usr/bin/env bash

install_cloudflared_binary() {
  local stored actual
  if [[ -x "$SBD_BIN_DIR/cloudflared" && -f "$SBD_DATA_DIR/cloudflared.sha256" ]]; then
    stored="$(cat "$SBD_DATA_DIR/cloudflared.sha256")" || return 1
    actual="$(sha256sum "$SBD_BIN_DIR/cloudflared")" || return 1
    [[ "${actual%% *}" != "$stored" ]] || return 0
  fi
  local arch
  arch="$(get_arch)"
  local asset="cloudflared-linux-amd64"
  [[ "$arch" == "arm64" ]] && asset="cloudflared-linux-arm64"

  local release url digest expected
  release="$(fetch_release_metadata cloudflare/cloudflared latest)" || return 1
  url="$(jq -er --arg name "$asset" '.assets[] | select(.name == $name) | .browser_download_url' <<< "$release")" || return 1
  digest="$(jq -er --arg name "$asset" '.assets[] | select(.name == $name) | .digest' <<< "$release")" || return 1
  [[ "$digest" == sha256:* ]] || { log_error "Missing cloudflared digest"; return 1; }
  expected="${digest#sha256:}"

  local bin_out candidate
  bin_out="${SBD_BIN_DIR}/cloudflared"
  mkdir -p "$SBD_BIN_DIR" || return 1
  candidate="$(mktemp "${bin_out}.candidate.XXXXXX")" || return 1
  if ! download_file "$url" "$candidate" || ! (verify_sha256_expected "$candidate" "$expected"); then
    rm -f "$candidate"
    return 1
  fi
  chmod 0755 "$candidate" || { rm -f "$candidate"; return 1; }
  mv -f "$candidate" "$bin_out" || { rm -f "$candidate"; return 1; }
  printf '%s\n' "$expected" > "$SBD_DATA_DIR/cloudflared.sha256" || return 1
}

argo_write_token_file() {
  local token="$1"
  [[ -n "$token" ]] || die "Argo fixed mode requires a non-empty token"
  mkdir -p "$(dirname "$SBD_ARGO_TOKEN_FILE")"
  (umask 077; printf '%s\n' "$token" > "$SBD_ARGO_TOKEN_FILE")
  chmod 0600 "$SBD_ARGO_TOKEN_FILE"
}

argo_fixed_exec_command() {
  sbd_join_command_argv "$SBD_BIN_DIR/cloudflared" tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token-file "$SBD_ARGO_TOKEN_FILE"
}

argo_ensure_fixed_token_file() {
  local token="${ARGO_TOKEN:-}" legacy_token_file="${SBD_DATA_DIR}/argo_token"
  if [[ -s "$SBD_ARGO_TOKEN_FILE" ]]; then
    chmod 0600 "$SBD_ARGO_TOKEN_FILE"
    return 0
  fi
  if [[ -s "$legacy_token_file" ]]; then
    (umask 077; cp "$legacy_token_file" "$SBD_ARGO_TOKEN_FILE")
    chmod 0600 "$SBD_ARGO_TOKEN_FILE"
    return 0
  fi
  [[ -n "$token" ]] || die "Argo fixed mode token is unavailable for nohup migration"
  argo_write_token_file "$token"
}

argo_build_exec_command() {
  local -a argv=()
  argo_build_exec_argv argv "$@" || return 1
  sbd_join_command_argv "${argv[@]}"
}

# shellcheck disable=SC2034 # argo_argv writes through a caller-owned nameref
argo_build_exec_argv() {
  local -n argo_argv="$1"
  shift
  local protocols_csv="$1" engine="${2:-sing-box}" target_port
  local protocols=()
  protocols_to_array "$protocols_csv" protocols
  protocol_enabled "vless-ws" "${protocols[@]}" || die "Argo requires vless-ws protocol"
  case "${ARGO_MODE:-off}" in
    fixed)
      argo_ensure_fixed_token_file || return 1
      argo_argv=("$SBD_BIN_DIR/cloudflared" tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token-file "$SBD_ARGO_TOKEN_FILE")
      ;;
    temp)
      target_port="$(resolve_protocol_port_for_engine "$engine" "vless-ws")"
      argo_argv=("$SBD_BIN_DIR/cloudflared" tunnel --url "http://127.0.0.1:$target_port" --edge-ip-version auto --no-autoupdate --protocol http2)
      ;;
    *)
      die "Cannot build Argo command for ARGO_MODE=${ARGO_MODE:-off}"
      ;;
  esac
}

argo_write_exec_command() {
  local exec_cmd="$1"
  mkdir -p "$(dirname "$SBD_ARGO_EXEC_FILE")"
  (umask 077; printf '%s\n' "$exec_cmd" > "$SBD_ARGO_EXEC_FILE")
  chmod 0600 "$SBD_ARGO_EXEC_FILE"
}

argo_restore_nohup_exec_command() {
  provider_cfg_load_runtime_exports
  [[ "${ARGO_MODE:-off}" != "off" ]] || die "Argo is disabled in runtime state"
  local exec_cmd
  exec_cmd="$(argo_build_exec_command "${protocols:-vless-ws}" "${engine:-sing-box}")"
  argo_write_exec_command "$exec_cmd" || return 1
  printf '%s\n' "$exec_cmd"
}

configure_argo_tunnel() {
  local protocols_csv="$1"
  local engine="${2:-sing-box}"
  local protocols=()
  protocols_to_array "$protocols_csv" protocols
  if [[ "${ARGO_MODE:-off}" == "off" ]]; then
    return 0
  fi

  if ! protocol_enabled "vless-ws" "${protocols[@]}"; then
    die "Argo requires vless-ws protocol"
  fi

  install_cloudflared_binary

  local mode="${ARGO_MODE:-temp}"
  local token="${ARGO_TOKEN:-}"
  local domain="${ARGO_DOMAIN:-}"
  local argo_log="${SBD_DATA_DIR}/argo.log"

  if [[ "$mode" == "fixed" && -z "$token" ]]; then
    die "Argo fixed mode requires ARGO_TOKEN or --argo-token"
  fi

  local exec_cmd
  local -a argv=()
  if [[ "$mode" == "fixed" ]]; then
    argo_write_token_file "$token" || return 1
    argo_build_exec_argv argv "$protocols_csv" "$engine" || return 1
  else
    mode="temp"
    rm -f "$SBD_ARGO_TOKEN_FILE"
    rm -f "${SBD_DATA_DIR}/argo_domain" || return 1
    : > "$argo_log" || return 1
    argo_build_exec_argv argv "$protocols_csv" "$engine" || return 1
  fi
  exec_cmd="$(sbd_join_command_argv "${argv[@]}")" || return 1
  argo_write_exec_command "$exec_cmd" || return 1

  local service_tmp
  mkdir -p "$(dirname "$SBD_ARGO_SERVICE_FILE")" || return 1
  service_tmp="$(mktemp "$SBD_ARGO_SERVICE_FILE.tmp.XXXXXX")" || return 1
  cat > "$service_tmp" <<EOF
# Managed by sing-box-deve: service-v1
[Unit]
Description=sing-box-deve argo tunnel
After=network.target sing-box-deve.service
Requires=sing-box-deve.service

[Service]
Type=simple
ExecStart=${exec_cmd}
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=read-only
StandardOutput=journal
StandardError=journal
SyslogIdentifier=sing-box-deve-argo
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
  sbd_host_file_publish "$SBD_ARGO_SERVICE_FILE" "$service_tmp" || return 1

  sbd_service_enable_and_start "sing-box-deve-argo" "${argv[@]}" || return 1

  echo "$mode" > "${SBD_DATA_DIR}/argo_mode"
  [[ -n "$domain" ]] && echo "$domain" > "${SBD_DATA_DIR}/argo_domain"

  if [[ "$mode" == "temp" ]]; then
    local temp_domain="" deadline=$((SECONDS + 20)) invocation remaining
    if [[ "${SBD_INIT_SYSTEM:-}" == systemd ]]; then
      invocation="$(sbd_service_op systemctl show -p InvocationID --value sing-box-deve-argo.service)" || return 1
      [[ "$invocation" =~ ^[a-f0-9]{32}$ ]] || return 1
    fi
    while (( SECONDS < deadline )); do
      remaining=$((deadline - SECONDS))
      if [[ "${SBD_INIT_SYSTEM:-}" == systemd ]]; then
        SBD_SERVICE_TIMEOUT="$remaining" sbd_service_op journalctl "_SYSTEMD_INVOCATION_ID=$invocation" -n 200 --no-pager > "$argo_log" || return 1
      elif [[ "${SBD_INIT_SYSTEM:-}" == nohup && -f "$SBD_DATA_DIR/sing-box-deve-argo.log" ]]; then
        tail -n 200 "$SBD_DATA_DIR/sing-box-deve-argo.log" > "$argo_log" || return 1
      fi
      temp_domain="$(grep -aEo 'https://[^ ]*trycloudflare.com' "$argo_log" 2>/dev/null | tail -n1 | sed 's#https://##')"
      [[ -n "$temp_domain" ]] && break
      sleep 1
    done
    if [[ -n "$temp_domain" ]]; then
      echo "$temp_domain" > "${SBD_DATA_DIR}/argo_domain"
    else
      log_warn "$(msg "未能在 20 秒内提取 Argo 临时域名，请稍后执行 regen-nodes" "Unable to extract temporary Argo domain within 20s; run regen-nodes later")"
    fi
  fi
}
