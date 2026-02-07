#!/usr/bin/env bash

validate_sap_accounts_json() {
  local json="$1"
  echo "$json" | jq -e . >/dev/null 2>&1 || die "SAP_ACCOUNTS_JSON is not valid JSON"
  echo "$json" | jq -e 'type=="array"' >/dev/null 2>&1 || die "SAP_ACCOUNTS_JSON must be a JSON array"
  echo "$json" | jq -e 'length>0' >/dev/null 2>&1 || die "SAP_ACCOUNTS_JSON array cannot be empty"

  local idx=0
  while IFS= read -r item; do
    idx=$((idx + 1))
    [[ "$(echo "$item" | jq -r 'type')" == "object" ]] || die "SAP_ACCOUNTS_JSON item #${idx} must be an object"
    local required_key
    for required_key in api username password org space app_name; do
      if [[ -z "$(echo "$item" | jq -r --arg k "$required_key" '.[$k] // empty')" ]]; then
        die "SAP_ACCOUNTS_JSON item #${idx} missing required key '${required_key}'"
      fi
    done
  done < <(echo "$json" | jq -c '.[]')
}

provider_sap_install() {
  local profile="$1"
  local engine="$2"
  local protocols_csv="$3"

  validate_feature_modes
  mkdir -p /etc/sing-box-deve
  cat > /etc/sing-box-deve/sap.env <<EOF
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

  local sap_image
  sap_image="${SAP_DOCKER_IMAGE:-ygkkk/argosbx}"

  ensure_cf_cli() {
    if command -v cf >/dev/null 2>&1; then
      return 0
    fi
    local cf_tgz="${SBD_RUNTIME_DIR}/cf8-cli.tgz"
    download_file "https://github.com/cloudfoundry/cli/releases/download/v8.16.0/cf8-cli_8.16.0_linux_x86-64.tgz" "$cf_tgz"
    tar -xzf "$cf_tgz" -C "$SBD_RUNTIME_DIR"
    install -m 0755 "${SBD_RUNTIME_DIR}/cf8" /usr/local/bin/cf
  }

  deploy_single_sap() {
    local api="$1" username="$2" password="$3" org="$4" space="$5" app="$6" memory="$7" image="$8" uuid="$9"
    local agn="${10}" agk="${11}"
    [[ -n "$api" && -n "$username" && -n "$password" && -n "$org" && -n "$space" && -n "$app" ]] || \
      die "SAP single deployment parameters missing"

    cf login -a "$api" -u "$username" -p "$password" -o "$org" -s "$space" >/dev/null
    cf push "$app" --docker-image "$image" -m "$memory" --health-check-type port >/dev/null
    [[ -n "$uuid" ]] && cf set-env "$app" uuid "$uuid" >/dev/null
    [[ -n "$agn" ]] && cf set-env "$app" agn "$agn" >/dev/null
    if [[ -n "$agk" ]]; then
      cf set-env "$app" agk "$agk" >/dev/null
      cf set-env "$app" argo "y" >/dev/null
    fi
    cf restage "$app" >/dev/null
  }

  if [[ -n "${SAP_ACCOUNTS_JSON:-}" ]]; then
    ensure_cf_cli
    if ! command -v jq >/dev/null 2>&1; then
      die "jq is required for SAP_ACCOUNTS_JSON"
    fi
    validate_sap_accounts_json "$SAP_ACCOUNTS_JSON"
    local idx=0 success=0 failed=0 skipped=0
    local retries="${SAP_RETRY_COUNT:-1}"
    [[ "$retries" =~ ^[0-9]+$ ]] || retries=1
    while IFS= read -r item; do
      [[ -z "$item" ]] && continue
      local api username password org space app memory image uuid agn agk
      api="$(echo "$item" | jq -r '.api // empty')"
      username="$(echo "$item" | jq -r '.username // empty')"
      password="$(echo "$item" | jq -r '.password // empty')"
      org="$(echo "$item" | jq -r '.org // empty')"
      space="$(echo "$item" | jq -r '.space // empty')"
      app="$(echo "$item" | jq -r '.app_name // empty')"
      memory="$(echo "$item" | jq -r '.memory // "512M"')"
      image="$(echo "$item" | jq -r '.image // "'"${sap_image}"'"')"
      uuid="$(echo "$item" | jq -r '.uuid // empty')"
      agn="$(echo "$item" | jq -r '.agn // empty')"
      agk="$(echo "$item" | jq -r '.agk // empty')"
      idx=$((idx + 1))
      log_info "Deploying SAP account #${idx}: app=${app}"
      if ! prompt_yes_no "$(msg "确认部署 SAP 应用 '${app}'（账号 #${idx}）吗？" "Confirm SAP deploy for app '${app}' (account #${idx})?")" "Y"; then
        log_warn "$(msg "用户已跳过 SAP 应用 ${app}" "Skipped SAP app ${app} by user choice")"
        skipped=$((skipped + 1))
        continue
      fi
      local attempt=0 ok=false
      while (( attempt <= retries )); do
        attempt=$((attempt + 1))
        if deploy_single_sap "$api" "$username" "$password" "$org" "$space" "$app" "$memory" "$image" "$uuid" "$agn" "$agk"; then
          ok=true
          break
        fi
        log_warn "SAP deploy retry ${attempt}/${retries} failed for app=${app}"
      done
      if [[ "$ok" == "true" ]]; then
        success=$((success + 1))
      else
        failed=$((failed + 1))
      fi
    done < <(echo "$SAP_ACCOUNTS_JSON" | jq -c '.[]')
    log_info "SAP batch summary: total=${idx} success=${success} failed=${failed} skipped=${skipped}"
    (( failed == 0 )) || die "SAP batch finished with failures"
    log_success "SAP deployment completed for ${success} account(s)"
  elif [[ -n "${SAP_CF_API:-}" && -n "${SAP_CF_USERNAME:-}" && -n "${SAP_CF_PASSWORD:-}" && -n "${SAP_CF_ORG:-}" && -n "${SAP_CF_SPACE:-}" && -n "${SAP_APP_NAME:-}" ]]; then
    ensure_cf_cli
    log_info "Deploying single SAP app: ${SAP_APP_NAME}"
    if ! prompt_yes_no "$(msg "确认部署 SAP 应用 '${SAP_APP_NAME}' 吗？" "Confirm SAP deploy for app '${SAP_APP_NAME}'?")" "Y"; then
      log_warn "$(msg "用户取消了 SAP 部署" "SAP deployment cancelled by user")"
      return 0
    fi
    deploy_single_sap "${SAP_CF_API}" "${SAP_CF_USERNAME}" "${SAP_CF_PASSWORD}" "${SAP_CF_ORG}" "${SAP_CF_SPACE}" "${SAP_APP_NAME}" "${SAP_APP_MEMORY:-512M}" "${sap_image}" "${SAP_UUID:-}" "${ARGO_DOMAIN:-}" "${ARGO_TOKEN:-}"
    log_success "SAP deployment completed"
  else
    log_warn "SAP credentials not fully set; generated templates only"
  fi

  cat > /etc/sing-box-deve/sap-github-workflow.yml <<'EOF'
name: SAP Deploy
on:
  workflow_dispatch:
jobs:
  deploy:
    runs-on: ubuntu-latest
    env:
      SAP_CF_API: ${{ secrets.SAP_CF_API }}
      SAP_CF_USERNAME: ${{ secrets.SAP_CF_USERNAME }}
      SAP_CF_PASSWORD: ${{ secrets.SAP_CF_PASSWORD }}
      SAP_CF_ORG: ${{ secrets.SAP_CF_ORG }}
      SAP_CF_SPACE: ${{ secrets.SAP_CF_SPACE }}
      SAP_APP_NAME: ${{ secrets.SAP_APP_NAME }}
    steps:
      - uses: actions/checkout@v4
      - name: Install CF CLI
        run: |
          wget -q https://github.com/cloudfoundry/cli/releases/download/v8.16.0/cf8-cli_8.16.0_linux_x86-64.tgz
          tar -xzf cf8-cli_8.16.0_linux_x86-64.tgz
          sudo mv cf8 /usr/local/bin/cf
      - name: Deploy
        run: |
          cf login -a "$SAP_CF_API" -u "$SAP_CF_USERNAME" -p "$SAP_CF_PASSWORD" -o "$SAP_CF_ORG" -s "$SAP_CF_SPACE"
          cf push "$SAP_APP_NAME" --docker-image ${SAP_DOCKER_IMAGE:-ygkkk/argosbx} -m 512M --health-check-type port
EOF
  log_success "SAP deployment templates generated under /etc/sing-box-deve"
  return 0
}
