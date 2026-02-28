#!/usr/bin/env bash

# SAP BTP Cloud Foundry region code → API endpoint mapping
# 30 regions covering AWS, Azure, GCP, Alibaba Cloud
sap_region_to_api() {
  case "$1" in
    SG)      echo "https://api.cf.ap21.hana.ondemand.com" ;;
    US)      echo "https://api.cf.us10-001.hana.ondemand.com" ;;
    AU-A)    echo "https://api.cf.ap10.hana.ondemand.com" ;;
    SG-A)    echo "https://api.cf.ap11.hana.ondemand.com" ;;
    KR-A)    echo "https://api.cf.ap12.hana.ondemand.com" ;;
    BR-A)    echo "https://api.cf.br10.hana.ondemand.com" ;;
    CA-A)    echo "https://api.cf.ca10.hana.ondemand.com" ;;
    DE-A)    echo "https://api.cf.eu10-005.hana.ondemand.com" ;;
    JP-A)    echo "https://api.cf.jp10.hana.ondemand.com" ;;
    US-V-A)  echo "https://api.cf.us10-001.hana.ondemand.com" ;;
    US-O-A)  echo "https://api.cf.us11.hana.ondemand.com" ;;
    AU-G)    echo "https://api.cf.ap30.hana.ondemand.com" ;;
    BR-G)    echo "https://api.cf.br30.hana.ondemand.com" ;;
    US-G)    echo "https://api.cf.us30.hana.ondemand.com" ;;
    DE-G)    echo "https://api.cf.eu30.hana.ondemand.com" ;;
    JP-O-G)  echo "https://api.cf.jp30.hana.ondemand.com" ;;
    JP-T-G)  echo "https://api.cf.jp31.hana.ondemand.com" ;;
    IL-G)    echo "https://api.cf.il30.hana.ondemand.com" ;;
    IN-G)    echo "https://api.cf.in30.hana.ondemand.com" ;;
    SA-G)    echo "https://api.cf.sa31.hana.ondemand.com" ;;
    AU-M)    echo "https://api.cf.ap20.hana.ondemand.com" ;;
    BR-M)    echo "https://api.cf.br20.hana.ondemand.com" ;;
    CA-M)    echo "https://api.cf.ca20.hana.ondemand.com" ;;
    US-V-M)  echo "https://api.cf.us21.hana.ondemand.com" ;;
    US-W-M)  echo "https://api.cf.us20.hana.ondemand.com" ;;
    NL-M)    echo "https://api.cf.eu20-001.hana.ondemand.com" ;;
    JP-M)    echo "https://api.cf.jp20.hana.ondemand.com" ;;
    SG-M)    echo "https://api.cf.ap21.hana.ondemand.com" ;;
    AE-N)    echo "https://api.cf.neo-ae1.hana.ondemand.com" ;;
    SA-N)    echo "https://api.cf.neo-sa1.hana.ondemand.com" ;;
    *) echo "" ;;
  esac
}

# List all available SAP region codes
sap_list_regions() {
  echo "SG US AU-A SG-A KR-A BR-A CA-A DE-A JP-A US-V-A US-O-A"
  echo "AU-G BR-G US-G DE-G JP-O-G JP-T-G IL-G IN-G SA-G"
  echo "AU-M BR-M CA-M US-V-M US-W-M NL-M JP-M SG-M AE-N SA-N"
}

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
    for required_key in username password org space app_name; do
      if [[ -z "$(echo "$item" | jq -r --arg k "$required_key" '.[$k] // empty')" ]]; then
        die "SAP_ACCOUNTS_JSON item #${idx} missing required key '${required_key}'"
      fi
    done
    # Either 'api' or 'region' must be provided
    local item_api item_region
    item_api="$(echo "$item" | jq -r '.api // empty')"
    item_region="$(echo "$item" | jq -r '.region // empty')"
    if [[ -z "$item_api" && -z "$item_region" ]]; then
      die "SAP_ACCOUNTS_JSON item #${idx} missing 'api' or 'region'"
    fi
    if [[ -n "$item_region" && -z "$item_api" ]]; then
      local resolved
      resolved="$(sap_region_to_api "$item_region")"
      [[ -n "$resolved" ]] || die "SAP_ACCOUNTS_JSON item #${idx} unknown region: ${item_region}"
    fi
  done < <(echo "$json" | jq -c '.[]')
}

provider_sap_install() {
  local profile="$1"
  local engine="$2"
  local protocols_csv="$3"

  validate_feature_modes
  mkdir -p "${SBD_CONFIG_DIR}"
  cat > "${SBD_CONFIG_DIR}/sap.env" <<EOF
profile=${profile}
engine=${engine}
protocols=${protocols_csv}
argo_mode=${ARGO_MODE:-off}
psiphon_enable=${PSIPHON_ENABLE:-off}
psiphon_mode=${PSIPHON_MODE:-off}
psiphon_region=${PSIPHON_REGION:-auto}
warp_mode=${WARP_MODE:-off}
outbound_proxy_mode=${OUTBOUND_PROXY_MODE:-direct}
outbound_proxy_host=${OUTBOUND_PROXY_HOST:-}
outbound_proxy_port=${OUTBOUND_PROXY_PORT:-}
generated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
  chmod 600 "${SBD_CONFIG_DIR}/sap.env" 2>/dev/null || true

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
      local api username password org space app memory image uuid agn agk region
      api="$(echo "$item" | jq -r '.api // empty')"
      region="$(echo "$item" | jq -r '.region // empty')"
      # Resolve region code to API endpoint if api is not provided
      if [[ -z "$api" && -n "$region" ]]; then
        api="$(sap_region_to_api "$region")"
        [[ -n "$api" ]] || { log_warn "Unknown region: ${region}, skipping"; skipped=$((skipped + 1)); continue; }
      fi
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
      log_info "$(msg "正在部署 SAP 账号 #${idx}: app=${app}" "Deploying SAP account #${idx}: app=${app}")"
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
        log_warn "$(msg "SAP 部署重试失败 ${attempt}/${retries}: app=${app}" "SAP deploy retry ${attempt}/${retries} failed for app=${app}")"
      done
      if [[ "$ok" == "true" ]]; then
        success=$((success + 1))
      else
        failed=$((failed + 1))
      fi
    done < <(echo "$SAP_ACCOUNTS_JSON" | jq -c '.[]')
    log_info "$(msg "SAP 批量汇总: total=${idx} success=${success} failed=${failed} skipped=${skipped}" "SAP batch summary: total=${idx} success=${success} failed=${failed} skipped=${skipped}")"
    (( failed == 0 )) || die "$(msg "SAP 批量部署存在失败项" "SAP batch finished with failures")"
    log_success "$(msg "SAP 批量部署完成，成功 ${success} 个账号" "SAP deployment completed for ${success} account(s)")"
  elif [[ -n "${SAP_CF_API:-}" && -n "${SAP_CF_USERNAME:-}" && -n "${SAP_CF_PASSWORD:-}" && -n "${SAP_CF_ORG:-}" && -n "${SAP_CF_SPACE:-}" && -n "${SAP_APP_NAME:-}" ]]; then
    ensure_cf_cli
    log_info "$(msg "正在部署单个 SAP 应用: ${SAP_APP_NAME}" "Deploying single SAP app: ${SAP_APP_NAME}")"
    if ! prompt_yes_no "$(msg "确认部署 SAP 应用 '${SAP_APP_NAME}' 吗？" "Confirm SAP deploy for app '${SAP_APP_NAME}'?")" "Y"; then
      log_warn "$(msg "用户取消了 SAP 部署" "SAP deployment cancelled by user")"
      return 0
    fi
    deploy_single_sap "${SAP_CF_API}" "${SAP_CF_USERNAME}" "${SAP_CF_PASSWORD}" "${SAP_CF_ORG}" "${SAP_CF_SPACE}" "${SAP_APP_NAME}" "${SAP_APP_MEMORY:-512M}" "${sap_image}" "${SAP_UUID:-}" "${ARGO_DOMAIN:-}" "${ARGO_TOKEN:-}"
    log_success "$(msg "SAP 部署完成" "SAP deployment completed")"
  else
    log_warn "$(msg "SAP 凭据未完整设置；仅生成模板文件" "SAP credentials not fully set; generated templates only")"
  fi

  cat > "${SBD_CONFIG_DIR}/sap-github-workflow.yml" <<'EOF'
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
  log_success "$(msg "SAP 部署模板已生成到 ${SBD_CONFIG_DIR}" "SAP deployment templates generated under ${SBD_CONFIG_DIR}")"
  return 0
}
