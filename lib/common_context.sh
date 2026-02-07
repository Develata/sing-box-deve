#!/usr/bin/env bash

create_install_context() {
  local provider="$1"
  local profile="$2"
  local engine="$3"
  local protocols_csv="$4"
  local argo_mode="${ARGO_MODE:-off}"
  local argo_domain="${ARGO_DOMAIN:-}"
  local argo_token="${ARGO_TOKEN:-}"
  local warp_mode="${WARP_MODE:-off}"
  local outbound_proxy_mode="${OUTBOUND_PROXY_MODE:-direct}"
  local outbound_proxy_host="${OUTBOUND_PROXY_HOST:-}"
  local outbound_proxy_port="${OUTBOUND_PROXY_PORT:-}"
  local outbound_proxy_user="${OUTBOUND_PROXY_USER:-}"
  local outbound_proxy_pass="${OUTBOUND_PROXY_PASS:-}"

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
warp_mode=${warp_mode}
outbound_proxy_mode=${outbound_proxy_mode}
outbound_proxy_host=${outbound_proxy_host}
outbound_proxy_port=${outbound_proxy_port}
outbound_proxy_user_set=$([[ -n "${outbound_proxy_user}" ]] && echo true || echo false)
outbound_proxy_pass_set=$([[ -n "${outbound_proxy_pass}" ]] && echo true || echo false)
EOF
}

load_install_context() {
  if [[ -f "$SBD_CONTEXT_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$SBD_CONTEXT_FILE"
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
  warp_mode: ${warp_mode:-off}
  outbound_proxy_mode: ${outbound_proxy_mode:-direct}
  outbound_proxy_host: ${outbound_proxy_host:-""}
  outbound_proxy_port: ${outbound_proxy_port:-""}
  outbound_proxy_user_set: ${outbound_proxy_user_set:-false}
  outbound_proxy_pass_set: ${outbound_proxy_pass_set:-false}
resources:
  default_profile: ${profile}
EOF

  log_info "Auto-generated config snapshot: ${file_path}"
}
