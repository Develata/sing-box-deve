#!/usr/bin/env bash

provider_install() {
  local provider="$1"
  local profile="$2"
  local engine="$3"
  local protocols_csv="$4"

  case "$provider" in
    vps)
      provider_vps_install "$profile" "$engine" "$protocols_csv"
      ;;
    serv00)
      provider_serv00_install "$profile" "$engine" "$protocols_csv"
      ;;
    sap)
      provider_sap_install "$profile" "$engine" "$protocols_csv"
      ;;
    docker)
      provider_docker_install "$profile" "$engine" "$protocols_csv"
      ;;
    *)
      die "Unsupported provider: $provider"
      ;;
  esac
}

provider_vps_install() {
  local profile="$1"
  local engine="$2"
  local protocols_csv="$3"

  log_info "Installing for provider=vps profile=${profile} engine=${engine}"
  install_apt_dependencies
  validate_feature_modes
  assert_engine_protocol_compatibility "$engine" "$protocols_csv"

  local protocols=()
  protocols_to_array "$protocols_csv" protocols
  local protocol mapping proto port
  for protocol in "${protocols[@]}"; do
    if [[ "$protocol" == "argo" || "$protocol" == "warp" ]]; then
      continue
    fi
    mapping="$(protocol_port_map "$protocol")"
    proto="${mapping%%:*}"
    port="$(get_protocol_port "$protocol")"
    fw_apply_rule "$proto" "$port"
  done

  install_engine_binary "$engine"

  case "$engine" in
    sing-box) build_sing_box_config "$protocols_csv" ;;
    xray) build_xray_config "$protocols_csv" ;;
  esac

  validate_generated_config "$engine"
  write_systemd_service "$engine"
  configure_argo_tunnel "$protocols_csv"
  write_nodes_output "$engine" "$protocols_csv"

  mkdir -p /etc/sing-box-deve
  persist_runtime_state "vps" "$profile" "$engine" "$protocols_csv"

  cat > /usr/local/bin/sb <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

script_root=""
if [[ -f /etc/sing-box-deve/runtime.env ]]; then
  # shellcheck disable=SC1091
  source /etc/sing-box-deve/runtime.env
  script_root="${script_root:-}"
fi

if [[ -z "$script_root" || ! -x "$script_root/sing-box-deve.sh" ]]; then
  script_root="/home/develata/gitclone/sing-box-deve"
fi

if [[ $# -eq 0 ]]; then
  exec "$script_root/sing-box-deve.sh" menu
fi

exec "$script_root/sing-box-deve.sh" "$@"
EOF
  chmod +x /usr/local/bin/sb

  log_success "VPS provider setup complete"
}

persist_runtime_state() {
  local provider="$1"
  local profile="$2"
  local engine="$3"
  local protocols_csv="$4"
  cat > /etc/sing-box-deve/runtime.env <<EOF
provider=${provider}
profile=${profile}
engine=${engine}
protocols=${protocols_csv}
argo_mode=${ARGO_MODE:-off}
warp_mode=${WARP_MODE:-off}
route_mode=${ROUTE_MODE:-direct}
outbound_proxy_mode=${OUTBOUND_PROXY_MODE:-direct}
outbound_proxy_host=${OUTBOUND_PROXY_HOST:-}
outbound_proxy_port=${OUTBOUND_PROXY_PORT:-}
direct_share_endpoints=${DIRECT_SHARE_ENDPOINTS:-}
proxy_share_endpoints=${PROXY_SHARE_ENDPOINTS:-}
warp_share_endpoints=${WARP_SHARE_ENDPOINTS:-}
script_root=${PROJECT_ROOT}
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
}
