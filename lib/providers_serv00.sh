#!/usr/bin/env bash

validate_serv00_accounts_json() {
  local json="$1"
  echo "$json" | jq -e . >/dev/null 2>&1 || die "SERV00_ACCOUNTS_JSON is not valid JSON"
  echo "$json" | jq -e 'type=="array"' >/dev/null 2>&1 || die "SERV00_ACCOUNTS_JSON must be a JSON array"
  echo "$json" | jq -e 'length>0' >/dev/null 2>&1 || die "SERV00_ACCOUNTS_JSON array cannot be empty"

  local idx=0
  while IFS= read -r item; do
    idx=$((idx + 1))
    [[ "$(echo "$item" | jq -r 'type')" == "object" ]] || die "SERV00_ACCOUNTS_JSON item #${idx} must be an object"
    local required_key
    for required_key in host user pass; do
      if [[ -z "$(echo "$item" | jq -r --arg k "$required_key" '.[$k] // empty')" ]]; then
        die "SERV00_ACCOUNTS_JSON item #${idx} missing required key '${required_key}'"
      fi
    done
  done < <(echo "$json" | jq -c '.[]')
}

provider_serv00_install() {
  local profile="$1"
  local engine="$2"
  local protocols_csv="$3"

  validate_feature_modes
  install_apt_dependencies
  mkdir -p /etc/sing-box-deve
  cat > /etc/sing-box-deve/serv00.env <<EOF
profile=${profile}
engine=${engine}
protocols=${protocols_csv}
argo_mode=${ARGO_MODE:-off}
warp_mode=${WARP_MODE:-off}
outbound_proxy_mode=${OUTBOUND_PROXY_MODE:-direct}
outbound_proxy_host=${OUTBOUND_PROXY_HOST:-}
outbound_proxy_port=${OUTBOUND_PROXY_PORT:-}
generated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

  if ! command -v sshpass >/dev/null 2>&1; then
    apt-get update -y >/dev/null
    apt-get install -y sshpass >/dev/null
  fi

  local remote_cmd
  remote_cmd="${SERV00_BOOTSTRAP_CMD:-bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/serv00.sh)}"

  if [[ -n "${SERV00_ACCOUNTS_JSON:-}" ]]; then
    if ! command -v jq >/dev/null 2>&1; then
      die "jq is required for SERV00_ACCOUNTS_JSON"
    fi
    validate_serv00_accounts_json "$SERV00_ACCOUNTS_JSON"
    local count=0 success=0 failed=0 skipped=0
    local retries="${SERV00_RETRY_COUNT:-1}"
    [[ "$retries" =~ ^[0-9]+$ ]] || retries=1
    while IFS= read -r item; do
      [[ -z "$item" ]] && continue
      local host user pass cmd
      host="$(echo "$item" | jq -r '.host // empty')"
      user="$(echo "$item" | jq -r '.user // empty')"
      pass="$(echo "$item" | jq -r '.pass // empty')"
      cmd="$(echo "$item" | jq -r '.cmd // empty')"
      [[ -n "$cmd" ]] || cmd="$remote_cmd"
      count=$((count + 1))
      log_info "Executing remote Serv00 bootstrap for account #${count} (${user}@${host})"
      if ! prompt_yes_no "$(msg "确认为 ${user}@${host} 执行远程 Serv00 引导吗？" "Confirm remote bootstrap for ${user}@${host}?")" "Y"; then
        log_warn "$(msg "用户已跳过 ${user}@${host}" "Skipped ${user}@${host} by user choice")"
        skipped=$((skipped + 1))
        continue
      fi
      local attempt=0 ok=false
      while (( attempt <= retries )); do
        attempt=$((attempt + 1))
        if sshpass -p "$pass" ssh -o StrictHostKeyChecking=no "${user}@${host}" "$cmd"; then
          ok=true
          break
        fi
        log_warn "Serv00 bootstrap retry ${attempt}/${retries} failed for ${user}@${host}"
      done
      if [[ "$ok" == "true" ]]; then
        success=$((success + 1))
      else
        failed=$((failed + 1))
      fi
    done < <(echo "$SERV00_ACCOUNTS_JSON" | jq -c '.[]')
    log_info "Serv00 batch summary: total=${count} success=${success} failed=${failed} skipped=${skipped}"
    (( failed == 0 )) || die "Serv00 batch finished with failures"
    log_success "Serv00 remote bootstrap completed for ${success} account(s)"
  elif [[ -n "${SERV00_HOST:-}" && -n "${SERV00_USER:-}" && -n "${SERV00_PASS:-}" ]]; then
    log_info "Executing remote Serv00 bootstrap on ${SERV00_HOST}"
    if ! prompt_yes_no "$(msg "确认为 ${SERV00_USER}@${SERV00_HOST} 执行远程 Serv00 引导吗？" "Confirm remote bootstrap for ${SERV00_USER}@${SERV00_HOST}?")" "Y"; then
      log_warn "$(msg "用户取消了 Serv00 远程引导" "Serv00 remote bootstrap cancelled by user")"
      return 0
    fi
    sshpass -p "${SERV00_PASS}" ssh -o StrictHostKeyChecking=no "${SERV00_USER}@${SERV00_HOST}" "$remote_cmd" || \
      die "Remote Serv00 bootstrap failed"
    log_success "Serv00 remote bootstrap completed"
  else
    log_warn "SERV00 credentials not set; generated local bundle only"
  fi

  cat > /etc/sing-box-deve/serv00-run.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ -z "${SERV00_HOST:-}" ] || [ -z "${SERV00_USER:-}" ] || [ -z "${SERV00_PASS:-}" ]; then
  echo "Please export SERV00_HOST SERV00_USER SERV00_PASS first"
  exit 1
fi

cmd="${SERV00_BOOTSTRAP_CMD:-bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/serv00.sh)}"
sshpass -p "${SERV00_PASS}" ssh -o StrictHostKeyChecking=no "${SERV00_USER}@${SERV00_HOST}" "${cmd}"
EOF
  chmod +x /etc/sing-box-deve/serv00-run.sh
  log_success "Serv00 deployment bundle generated at /etc/sing-box-deve/serv00.env and /etc/sing-box-deve/serv00-run.sh"
  return 0
}
