#!/usr/bin/env bash

provider_set_port_info() {
  ensure_root
  [[ -f /etc/sing-box-deve/runtime.env ]] || die "No runtime state found"
  # shellcheck disable=SC1091
  source /etc/sing-box-deve/runtime.env

  local whitelist cfg
  case "${engine:-sing-box}" in
    sing-box)
      whitelist="vless-reality,vmess-ws,vless-ws,shadowsocks-2022,hysteria2,tuic,trojan,wireguard,anytls,any-reality"
      cfg="${SBD_CONFIG_DIR}/config.json"
      ;;
    xray)
      whitelist="vless-reality,vmess-ws,vless-ws,vless-xhttp,trojan,socks5"
      cfg="${SBD_CONFIG_DIR}/xray-config.json"
      ;;
    *)
      die "Unknown engine in runtime state: ${engine:-unknown}"
      ;;
  esac

  log_info "Whitelist (engine=${engine}): ${whitelist}"
  [[ -f "$cfg" ]] || die "Config file not found: $cfg"
  command -v jq >/dev/null 2>&1 || die "jq is required for set-port --list"

  log_info "Current protocol ports:"
  if [[ "${engine}" == "sing-box" ]]; then
    jq -r '.inbounds[] | [.tag, (.listen_port // .port // "n/a")] | @tsv' "$cfg" | while IFS=$'\t' read -r tag port; do
      case "$tag" in
        vless-reality|vmess-ws|vless-ws|ss-2022|hy2|tuic|trojan|wireguard|anytls|any-reality)
          log_info "- ${tag}: ${port}"
          ;;
      esac
    done
  else
    jq -r '.inbounds[] | [.tag, (.port // "n/a")] | @tsv' "$cfg" | while IFS=$'\t' read -r tag port; do
      case "$tag" in
        vless-reality|vmess-ws|vless-ws|vless-xhttp|trojan|socks5)
          log_info "- ${tag}: ${port}"
          ;;
      esac
    done
  fi

  log_info "Usage: ./sing-box-deve.sh set-port --protocol <name> --port <1-65535>"
}

provider_set_port() {
  ensure_root
  [[ -f /etc/sing-box-deve/runtime.env ]] || die "No runtime state found"
  # shellcheck disable=SC1091
  source /etc/sing-box-deve/runtime.env
  local runtime_provider="${provider:-vps}"
  local runtime_engine="${engine:-sing-box}"
  validate_provider "$runtime_provider"
  validate_engine "$runtime_engine"
  [[ "$runtime_provider" == "vps" ]] || die "set-port currently supports provider=vps only"
  [[ "$2" =~ ^[0-9]+$ ]] || die "Port must be numeric"
  (( $2 >= 1 && $2 <= 65535 )) || die "Port must be between 1 and 65535"

  local protocol="$1"
  local new_port="$2"
  local tag
  tag="$(protocol_inbound_tag "$protocol" || true)"
  [[ -n "$tag" ]] || die "Unsupported protocol for set-port: $protocol"
  local fw_proto
  fw_proto="$(protocol_port_map "$protocol")"
  fw_proto="${fw_proto%%:*}"

  local cfg tmp_cfg old_port
  if [[ "$runtime_engine" == "sing-box" ]]; then
    cfg="${SBD_CONFIG_DIR}/config.json"
    [[ -f "$cfg" ]] || die "Config file missing: $cfg"
    old_port="$(jq -r --arg t "$tag" '.inbounds[] | select(.tag==$t) | (.listen_port // .port)' "$cfg" | head -n1)"
    [[ -n "$old_port" ]] || die "Protocol tag not found in config: $tag"
    tmp_cfg="${SBD_RUNTIME_DIR}/config.json.tmp"
    jq --arg t "$tag" --argjson p "$new_port" '(.inbounds[] | select(.tag==$t) | .listen_port) = $p | (.inbounds[] | select(.tag==$t) | .port) = $p' "$cfg" > "$tmp_cfg"
    mv "$tmp_cfg" "$cfg"
    validate_generated_config "sing-box"
  else
    cfg="${SBD_CONFIG_DIR}/xray-config.json"
    [[ -f "$cfg" ]] || die "Config file missing: $cfg"
    old_port="$(jq -r --arg t "$tag" '.inbounds[] | select(.tag==$t) | .port' "$cfg" | head -n1)"
    [[ -n "$old_port" ]] || die "Protocol tag not found in config: $tag"
    tmp_cfg="${SBD_RUNTIME_DIR}/xray-config.json.tmp"
    jq --arg t "$tag" --argjson p "$new_port" '(.inbounds[] | select(.tag==$t) | .port) = $p' "$cfg" > "$tmp_cfg"
    mv "$tmp_cfg" "$cfg"
    validate_generated_config "xray"
  fi

  fw_detect_backend
  load_install_context || true
  if [[ -n "${install_id:-}" && -n "$old_port" ]]; then
    local old_tag
    old_tag="MYBOX:${install_id}:core:${fw_proto}:${old_port}"
    fw_remove_rule_by_record "$FW_BACKEND" "$fw_proto" "$old_port" "$old_tag" || true
    if [[ -f "$SBD_RULES_FILE" ]]; then
      awk -F'|' -v tag="$old_tag" '$4 != tag' "$SBD_RULES_FILE" > "${SBD_RULES_FILE}.tmp" && mv "${SBD_RULES_FILE}.tmp" "$SBD_RULES_FILE"
    fi
  fi
  fw_apply_rule "$fw_proto" "$new_port"

  provider_restart core
  log_success "Protocol port updated: ${protocol} -> ${new_port}"
}

provider_set_egress() {
  ensure_root
  [[ -f /etc/sing-box-deve/runtime.env ]] || die "No runtime state found"
  local mode="$1" host="$2" port="$3" user="$4" pass="$5"
  case "$mode" in
    direct|socks|http|https) ;;
    *) die "Unsupported egress mode: $mode" ;;
  esac
  if [[ "$mode" != "direct" ]]; then
    [[ -n "$host" && -n "$port" ]] || die "host and port are required when mode != direct"
    [[ "$port" =~ ^[0-9]+$ ]] || die "egress port must be numeric"
  fi

  # shellcheck disable=SC1091
  source /etc/sing-box-deve/runtime.env
  local runtime_provider="${provider:-vps}"
  local runtime_profile="${profile:-lite}"
  local runtime_engine="${engine:-sing-box}"
  local runtime_protocols="${protocols:-vless-reality}"
  export OUTBOUND_PROXY_MODE="$mode"
  export OUTBOUND_PROXY_HOST="$host"
  export OUTBOUND_PROXY_PORT="$port"
  export OUTBOUND_PROXY_USER="$user"
  export OUTBOUND_PROXY_PASS="$pass"
  export DIRECT_SHARE_ENDPOINTS="${direct_share_endpoints:-}"
  export PROXY_SHARE_ENDPOINTS="${proxy_share_endpoints:-}"
  export WARP_SHARE_ENDPOINTS="${warp_share_endpoints:-}"
  export IP_PREFERENCE="${ip_preference:-auto}"
  export CDN_TEMPLATE_HOST="${cdn_template_host:-}"
  export TLS_MODE="${tls_mode:-self-signed}"
  export ACME_CERT_PATH="${acme_cert_path:-}"
  export ACME_KEY_PATH="${acme_key_path:-}"
  export DOMAIN_SPLIT_DIRECT="${domain_split_direct:-}"
  export DOMAIN_SPLIT_PROXY="${domain_split_proxy:-}"
  export DOMAIN_SPLIT_BLOCK="${domain_split_block:-}"
  export ARGO_MODE="${argo_mode:-off}"
  export WARP_MODE="${warp_mode:-off}"
  export ROUTE_MODE="${route_mode:-direct}"
  export ARGO_DOMAIN="${argo_domain:-${ARGO_DOMAIN:-}}"
  export ARGO_TOKEN="${argo_token:-${ARGO_TOKEN:-}}"

  validate_feature_modes
  case "$runtime_engine" in
    sing-box) build_sing_box_config "$runtime_protocols" && validate_generated_config "sing-box" ;;
    xray) build_xray_config "$runtime_protocols" && validate_generated_config "xray" ;;
  esac
  persist_runtime_state "$runtime_provider" "$runtime_profile" "$runtime_engine" "$runtime_protocols"
  provider_restart core
  log_success "Egress mode updated: ${mode}"
}

provider_set_route() {
  ensure_root
  [[ -f /etc/sing-box-deve/runtime.env ]] || die "No runtime state found"
  local mode="$1"
  case "$mode" in
    direct|global-proxy|cn-direct|cn-proxy) ;;
    *) die "Unsupported route mode: $mode" ;;
  esac

  # shellcheck disable=SC1091
  source /etc/sing-box-deve/runtime.env
  local runtime_provider="${provider:-vps}"
  local runtime_profile="${profile:-lite}"
  local runtime_engine="${engine:-sing-box}"
  local runtime_protocols="${protocols:-vless-reality}"
  export ARGO_MODE="${argo_mode:-off}"
  export WARP_MODE="${warp_mode:-off}"
  export ROUTE_MODE="$mode"
  export OUTBOUND_PROXY_MODE="${outbound_proxy_mode:-direct}"
  export OUTBOUND_PROXY_HOST="${outbound_proxy_host:-}"
  export OUTBOUND_PROXY_PORT="${outbound_proxy_port:-}"
  export OUTBOUND_PROXY_USER="${outbound_proxy_user:-}"
  export OUTBOUND_PROXY_PASS="${outbound_proxy_pass:-}"
  export DIRECT_SHARE_ENDPOINTS="${direct_share_endpoints:-}"
  export PROXY_SHARE_ENDPOINTS="${proxy_share_endpoints:-}"
  export WARP_SHARE_ENDPOINTS="${warp_share_endpoints:-}"
  export IP_PREFERENCE="${ip_preference:-auto}"
  export CDN_TEMPLATE_HOST="${cdn_template_host:-}"
  export TLS_MODE="${tls_mode:-self-signed}"
  export ACME_CERT_PATH="${acme_cert_path:-}"
  export ACME_KEY_PATH="${acme_key_path:-}"
  export DOMAIN_SPLIT_DIRECT="${domain_split_direct:-}"
  export DOMAIN_SPLIT_PROXY="${domain_split_proxy:-}"
  export DOMAIN_SPLIT_BLOCK="${domain_split_block:-}"

  validate_feature_modes
  case "$runtime_engine" in
    sing-box) build_sing_box_config "$runtime_protocols" && validate_generated_config "sing-box" ;;
    xray) build_xray_config "$runtime_protocols" && validate_generated_config "xray" ;;
  esac
  persist_runtime_state "$runtime_provider" "$runtime_profile" "$runtime_engine" "$runtime_protocols"
  provider_restart core
  log_success "Route mode updated: ${mode}"
}

provider_set_share_endpoints() {
  ensure_root
  [[ -f /etc/sing-box-deve/runtime.env ]] || die "No runtime state found"
  local kind="$1" endpoints="$2"
  [[ "$endpoints" == *:* ]] || die "Endpoints must be host:port[,host:port...]"

  # shellcheck disable=SC1091
  source /etc/sing-box-deve/runtime.env
  local runtime_provider="${provider:-vps}"
  local runtime_profile="${profile:-lite}"
  local runtime_engine="${engine:-sing-box}"
  local runtime_protocols="${protocols:-vless-reality}"

  export ARGO_MODE="${argo_mode:-off}"
  export WARP_MODE="${warp_mode:-off}"
  export ROUTE_MODE="${route_mode:-direct}"
  export OUTBOUND_PROXY_MODE="${outbound_proxy_mode:-direct}"
  export OUTBOUND_PROXY_HOST="${outbound_proxy_host:-}"
  export OUTBOUND_PROXY_PORT="${outbound_proxy_port:-}"
  export OUTBOUND_PROXY_USER="${outbound_proxy_user:-}"
  export OUTBOUND_PROXY_PASS="${outbound_proxy_pass:-}"
  export DIRECT_SHARE_ENDPOINTS="${direct_share_endpoints:-}"
  export PROXY_SHARE_ENDPOINTS="${proxy_share_endpoints:-}"
  export WARP_SHARE_ENDPOINTS="${warp_share_endpoints:-}"
  export IP_PREFERENCE="${ip_preference:-auto}"
  export CDN_TEMPLATE_HOST="${cdn_template_host:-}"
  export TLS_MODE="${tls_mode:-self-signed}"
  export ACME_CERT_PATH="${acme_cert_path:-}"
  export ACME_KEY_PATH="${acme_key_path:-}"
  export DOMAIN_SPLIT_DIRECT="${domain_split_direct:-}"
  export DOMAIN_SPLIT_PROXY="${domain_split_proxy:-}"
  export DOMAIN_SPLIT_BLOCK="${domain_split_block:-}"

  case "$kind" in
    direct) DIRECT_SHARE_ENDPOINTS="$endpoints" ;;
    proxy) PROXY_SHARE_ENDPOINTS="$endpoints" ;;
    warp) WARP_SHARE_ENDPOINTS="$endpoints" ;;
    *) die "Unsupported share endpoint kind: $kind" ;;
  esac

  write_nodes_output "$runtime_engine" "$runtime_protocols"
  persist_runtime_state "$runtime_provider" "$runtime_profile" "$runtime_engine" "$runtime_protocols"
  log_success "Share endpoints updated for ${kind}"
}
