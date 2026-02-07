#!/usr/bin/env bash

provider_list() {
  local mode="${1:-all}"

  if [[ "$mode" == "runtime" || "$mode" == "all" ]]; then
    if [[ -f /etc/sing-box-deve/runtime.env ]]; then
      log_info "Current runtime state:"
      cat /etc/sing-box-deve/runtime.env
    else
      log_warn "No runtime state found"
    fi
  fi

  if [[ "$mode" == "settings" || "$mode" == "all" ]]; then
    echo
    log_info "Persistent settings:"
    show_settings
  fi

  if [[ "$mode" == "nodes" || "$mode" == "all" ]]; then
    print_nodes_with_qr
  fi
}

provider_restart() {
  local target="${1:-all}"

  if [[ "$target" == "core" || "$target" == "all" ]]; then
    if [[ -f "$SBD_SERVICE_FILE" ]]; then
      safe_service_restart
      log_success "sing-box-deve service restarted"
    else
      log_warn "Service not installed"
    fi
  fi

  if [[ "$target" == "argo" || "$target" == "all" ]]; then
    if [[ -f "$SBD_ARGO_SERVICE_FILE" ]]; then
      systemctl restart sing-box-deve-argo.service
      log_success "sing-box-deve argo service restarted"
    else
      log_warn "Argo service file not found"
    fi
  fi
}

provider_logs() {
  ensure_root
  local target="${1:-core}"
  case "$target" in
    core)
      if [[ ! -f "$SBD_SERVICE_FILE" ]]; then
        die "Core service is not installed"
      fi
      journalctl -u sing-box-deve.service -n 120 --no-pager
      ;;
    argo)
      if [[ ! -f "$SBD_ARGO_SERVICE_FILE" ]]; then
        die "Argo service is not installed"
      fi
      journalctl -u sing-box-deve-argo.service -n 120 --no-pager
      ;;
    *)
      die "Unsupported logs target: $target"
      ;;
  esac
}

provider_regen_nodes() {
  ensure_root
  [[ -f /etc/sing-box-deve/runtime.env ]] || die "No runtime state found"
  # shellcheck disable=SC1091
  source /etc/sing-box-deve/runtime.env
  local runtime_engine="${engine:-sing-box}"
  local runtime_protocols="${protocols:-vless-reality}"
  write_nodes_output "$runtime_engine" "$runtime_protocols"
  log_success "Nodes regenerated: $SBD_NODES_FILE"
}

provider_update() {
  if [[ ! -f /etc/sing-box-deve/runtime.env ]]; then
    die "No installed runtime found"
  fi

  # shellcheck disable=SC1091
  source /etc/sing-box-deve/runtime.env
  install_engine_binary "$engine"
  safe_service_restart
  if [[ -f "$SBD_ARGO_SERVICE_FILE" ]]; then
    systemctl restart sing-box-deve-argo.service
  fi
  log_success "Engine updated and service restarted"
  provider_panel
}

provider_kernel_show() {
  local sb_local xr_local sb_remote xr_remote
  if [[ -x "${SBD_BIN_DIR}/sing-box" ]]; then
    sb_local="$("${SBD_BIN_DIR}/sing-box" version 2>/dev/null | awk '/version/{print $NF}' | head -n1)"
  else
    sb_local=""
  fi
  if [[ -x "${SBD_BIN_DIR}/xray" ]]; then
    xr_local="$("${SBD_BIN_DIR}/xray" version 2>/dev/null | awk '/^Xray/{print $2}' | head -n1)"
  else
    xr_local=""
  fi
  sb_remote="$(fetch_latest_release_tag "SagerNet/sing-box" 2>/dev/null || true)"
  xr_remote="$(fetch_latest_release_tag "XTLS/Xray-core" 2>/dev/null || true)"
  log_info "sing-box local=${sb_local:-n/a} remote=${sb_remote:-n/a}"
  log_info "xray local=${xr_local:-n/a} remote=${xr_remote:-n/a}"
}

provider_kernel_set() {
  ensure_root
  local target_engine="$1" target_tag="${2:-latest}"
  validate_engine "$target_engine"

  local has_runtime="false"
  if [[ -f /etc/sing-box-deve/runtime.env ]]; then
    has_runtime="true"
    # shellcheck disable=SC1091
    source /etc/sing-box-deve/runtime.env
  fi

  install_engine_binary "$target_engine" "$target_tag"

  if [[ "$has_runtime" == "true" ]]; then
    provider_cfg_load_runtime_exports

    assert_engine_protocol_compatibility "$target_engine" "${protocols:-vless-reality}"
    case "$target_engine" in
      sing-box) build_sing_box_config "${protocols:-vless-reality}" ;;
      xray) build_xray_config "${protocols:-vless-reality}" ;;
    esac
    validate_generated_config "$target_engine"
    write_systemd_service "$target_engine"
    write_nodes_output "$target_engine" "${protocols:-vless-reality}"
    persist_runtime_state "${provider:-vps}" "${profile:-lite}" "$target_engine" "${protocols:-vless-reality}"
  fi

  log_success "Kernel set: engine=${target_engine} tag=${target_tag}"
}

provider_warp_status() {
  local w4 w6
  w4="$(curl -s4m5 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | awk -F= '/^warp=/{print $2}' | head -n1)"
  w6="$(curl -s6m5 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | awk -F= '/^warp=/{print $2}' | head -n1)"
  log_info "warp status ipv4=${w4:-unknown} ipv6=${w6:-unknown}"
}

provider_warp_register() {
  ensure_root
  local keypair private_key public_key response reserved_str reserved_hex reserved_dec
  keypair="$(openssl genpkey -algorithm X25519 | openssl pkey -text -noout)"
  private_key="$(echo "$keypair" | awk '/priv:/{flag=1;next}/pub:/{flag=0}flag' | tr -d '[:space:]' | xxd -r -p | base64)"
  public_key="$(echo "$keypair" | awk '/pub:/{flag=1}flag' | tr -d '[:space:]' | xxd -r -p | base64)"
  response="$(curl -fsSL --tlsv1.3 -X POST 'https://api.cloudflareclient.com/v0a2158/reg' -H 'CF-Client-Version: a-7.21-0721' -H 'Content-Type: application/json' -d '{"key":"'"$public_key"'","tos":"'"$(date -u +'%Y-%m-%dT%H:%M:%S.000Z')"'"}')"
  reserved_str="$(echo "$response" | jq -r '.config.client_id // empty')"
  reserved_hex="$(echo "$reserved_str" | base64 -d 2>/dev/null | xxd -p -c 256 || true)"
  reserved_dec="$(python3 - <<PY
h='${reserved_hex}'
try:
    vals=[int(h[i:i+2],16) for i in range(0,6,2)]
    print(f'[{vals[0]},{vals[1]},{vals[2]}]')
except Exception:
    print('[0,0,0]')
PY
)"
  mkdir -p "$SBD_DATA_DIR"
  cat > "${SBD_DATA_DIR}/warp-account.env" <<EOF
WARP_PRIVATE_KEY=${private_key}
WARP_PEER_PUBLIC_KEY=bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=
WARP_RESERVED=${reserved_dec:-[0,0,0]}
EOF
  log_success "WARP account generated: ${SBD_DATA_DIR}/warp-account.env"
}
