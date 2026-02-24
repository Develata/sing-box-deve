#!/usr/bin/env bash

create_install_context() {
  local provider="$1"
  local profile="$2"
  local engine="$3"
  local protocols_csv="$4"
  local argo_mode="${ARGO_MODE:-off}"
  local argo_domain="${ARGO_DOMAIN:-}"
  local argo_token="${ARGO_TOKEN:-}"
  local argo_cdn_endpoints="${ARGO_CDN_ENDPOINTS:-}"
  local psiphon_enable="${PSIPHON_ENABLE:-off}"
  local psiphon_mode="${PSIPHON_MODE:-off}"
  local psiphon_region="${PSIPHON_REGION:-auto}"
  local warp_mode="${WARP_MODE:-off}"
  local route_mode="${ROUTE_MODE:-direct}"
  local ip_preference="${IP_PREFERENCE:-auto}"
  local cdn_template_host="${CDN_TEMPLATE_HOST:-}"
  local tls_mode="${TLS_MODE:-self-signed}"
  local acme_cert_path="${ACME_CERT_PATH:-}"
  local acme_key_path="${ACME_KEY_PATH:-}"
  local reality_server_name="${REALITY_SERVER_NAME:-}"
  local reality_fingerprint="${REALITY_FINGERPRINT:-}"
  local reality_handshake_port="${REALITY_HANDSHAKE_PORT:-443}"
  local tls_server_name="${TLS_SERVER_NAME:-}"
  local vmess_ws_path="${VMESS_WS_PATH:-/vmess}"
  local vless_ws_path="${VLESS_WS_PATH:-/vless}"
  local vless_xhttp_path="${VLESS_XHTTP_PATH:-}"
  local vless_xhttp_mode="${VLESS_XHTTP_MODE:-auto}"
  local xray_vless_enc="${XRAY_VLESS_ENC:-false}"
  local xray_xhttp_reality="${XRAY_XHTTP_REALITY:-false}"
  local cdn_host_vmess="${CDN_HOST_VMESS:-}"
  local cdn_host_vless_ws="${CDN_HOST_VLESS_WS:-}"
  local cdn_host_vless_xhttp="${CDN_HOST_VLESS_XHTTP:-}"
  local proxyip_vmess="${PROXYIP_VMESS:-}"
  local proxyip_vless_ws="${PROXYIP_VLESS_WS:-}"
  local proxyip_vless_xhttp="${PROXYIP_VLESS_XHTTP:-}"
  local domain_split_direct="${DOMAIN_SPLIT_DIRECT:-}"
  local domain_split_proxy="${DOMAIN_SPLIT_PROXY:-}"
  local domain_split_block="${DOMAIN_SPLIT_BLOCK:-}"
  local port_egress_map="${PORT_EGRESS_MAP:-}"
  local outbound_proxy_mode="${OUTBOUND_PROXY_MODE:-direct}"
  local outbound_proxy_host="${OUTBOUND_PROXY_HOST:-}"
  local outbound_proxy_port="${OUTBOUND_PROXY_PORT:-}"
  local outbound_proxy_user="${OUTBOUND_PROXY_USER:-}"
  local outbound_proxy_pass="${OUTBOUND_PROXY_PASS:-}"
  local direct_share_endpoints="${DIRECT_SHARE_ENDPOINTS:-}"
  local proxy_share_endpoints="${PROXY_SHARE_ENDPOINTS:-}"
  local warp_share_endpoints="${WARP_SHARE_ENDPOINTS:-}"

  local install_id
  install_id="$(rand_hex_8)"
  local created_at
  created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  cat > "$SBD_CONTEXT_FILE" <<EOF
install_id=${install_id}
created_at=${created_at}
provider=${provider}
profile=${profile}
engine=${engine}
protocols=${protocols_csv}
argo_mode=${argo_mode}
argo_domain=${argo_domain}
argo_token_set=$([[ -n "${argo_token}" ]] && echo true || echo false)
argo_cdn_endpoints=${argo_cdn_endpoints}
psiphon_enable=${psiphon_enable}
psiphon_mode=${psiphon_mode}
psiphon_region=${psiphon_region}
warp_mode=${warp_mode}
route_mode=${route_mode}
ip_preference=${ip_preference}
cdn_template_host=${cdn_template_host}
tls_mode=${tls_mode}
acme_cert_path=${acme_cert_path}
acme_key_path=${acme_key_path}
reality_server_name=${reality_server_name}
reality_fingerprint=${reality_fingerprint}
reality_handshake_port=${reality_handshake_port}
tls_server_name=${tls_server_name}
vmess_ws_path=${vmess_ws_path}
vless_ws_path=${vless_ws_path}
vless_xhttp_path=${vless_xhttp_path}
vless_xhttp_mode=${vless_xhttp_mode}
xray_vless_enc=${xray_vless_enc}
xray_xhttp_reality=${xray_xhttp_reality}
cdn_host_vmess=${cdn_host_vmess}
cdn_host_vless_ws=${cdn_host_vless_ws}
cdn_host_vless_xhttp=${cdn_host_vless_xhttp}
proxyip_vmess=${proxyip_vmess}
proxyip_vless_ws=${proxyip_vless_ws}
proxyip_vless_xhttp=${proxyip_vless_xhttp}
domain_split_direct=${domain_split_direct}
domain_split_proxy=${domain_split_proxy}
domain_split_block=${domain_split_block}
port_egress_map=${port_egress_map}
outbound_proxy_mode=${outbound_proxy_mode}
outbound_proxy_host=${outbound_proxy_host}
outbound_proxy_port=${outbound_proxy_port}
outbound_proxy_user_set=$([[ -n "${outbound_proxy_user}" ]] && echo true || echo false)
outbound_proxy_pass_set=$([[ -n "${outbound_proxy_pass}" ]] && echo true || echo false)
direct_share_endpoints=${direct_share_endpoints}
proxy_share_endpoints=${proxy_share_endpoints}
warp_share_endpoints=${warp_share_endpoints}
EOF
}

load_install_context() {
  if [[ -f "$SBD_CONTEXT_FILE" ]]; then
    sbd_safe_load_env_file "$SBD_CONTEXT_FILE"
    return 0
  fi
  return 1
}

auto_generate_config_snapshot() {
  local file_path="$1"
  load_install_context || die "Install context not found"

  cat > "$file_path" <<EOF
version: v1
generated_at: ${created_at}
provider: ${provider}
profile: ${profile}
engine: ${engine}
protocols:
$(echo "${protocols:-}" | tr ',' '\n' | sed 's/^/  - /')
security:
  firewall_managed: true
  firewall_mode: incremental_with_rollback
  destructive_firewall_actions: false
features:
  argo_mode: ${argo_mode:-off}
  argo_domain: ${argo_domain:-""}
  argo_token_set: ${argo_token_set:-false}
  argo_cdn_endpoints: ${argo_cdn_endpoints:-""}
  psiphon_enable: ${psiphon_enable:-off}
  psiphon_mode: ${psiphon_mode:-off}
  psiphon_region: ${psiphon_region:-auto}
  warp_mode: ${warp_mode:-off}
  route_mode: ${route_mode:-direct}
  ip_preference: ${ip_preference:-auto}
  cdn_template_host: ${cdn_template_host:-""}
  tls_mode: ${tls_mode:-self-signed}
  acme_cert_path: ${acme_cert_path:-""}
  acme_key_path: ${acme_key_path:-""}
  reality_server_name: ${reality_server_name:-apple.com}
  reality_fingerprint: ${reality_fingerprint:-chrome}
  reality_handshake_port: ${reality_handshake_port:-443}
  tls_server_name: ${tls_server_name:-www.bing.com}
  vmess_ws_path: ${vmess_ws_path:-/vmess}
  vless_ws_path: ${vless_ws_path:-/vless}
  vless_xhttp_path: ${vless_xhttp_path:-""}
  vless_xhttp_mode: ${vless_xhttp_mode:-auto}
  xray_vless_enc: ${xray_vless_enc:-false}
  xray_xhttp_reality: ${xray_xhttp_reality:-false}
  cdn_host_vmess: ${cdn_host_vmess:-""}
  cdn_host_vless_ws: ${cdn_host_vless_ws:-""}
  cdn_host_vless_xhttp: ${cdn_host_vless_xhttp:-""}
  proxyip_vmess: ${proxyip_vmess:-""}
  proxyip_vless_ws: ${proxyip_vless_ws:-""}
  proxyip_vless_xhttp: ${proxyip_vless_xhttp:-""}
  domain_split_direct: ${domain_split_direct:-""}
  domain_split_proxy: ${domain_split_proxy:-""}
  domain_split_block: ${domain_split_block:-""}
  port_egress_map: ${port_egress_map:-""}
  outbound_proxy_mode: ${outbound_proxy_mode:-direct}
  outbound_proxy_host: ${outbound_proxy_host:-""}
  outbound_proxy_port: ${outbound_proxy_port:-""}
  outbound_proxy_user_set: ${outbound_proxy_user_set:-false}
  outbound_proxy_pass_set: ${outbound_proxy_pass_set:-false}
  direct_share_endpoints: ${direct_share_endpoints:-""}
  proxy_share_endpoints: ${proxy_share_endpoints:-""}
  warp_share_endpoints: ${warp_share_endpoints:-""}
resources:
  default_profile: ${profile}
EOF

  log_info "$(msg "已自动生成配置快照: ${file_path}" "Auto-generated config snapshot: ${file_path}")"
}
