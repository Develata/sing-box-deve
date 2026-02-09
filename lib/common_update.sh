#!/usr/bin/env bash
# shellcheck disable=SC2034

current_script_version() {
  local version_file="${PROJECT_ROOT}/version"
  if [[ -f "$version_file" ]]; then
    tr -d '[:space:]' < "$version_file"
  else
    echo "v0.0.0-dev"
  fi
}

update_url_with_cache_bust() {
  local url="$1" token="${2:-}"
  [[ -n "$token" ]] || {
    echo "$url"
    return 0
  }
  if [[ "$url" == *\?* ]]; then
    echo "${url}&_cb=${token}"
  else
    echo "${url}?_cb=${token}"
  fi
}

fetch_remote_script_version() {
  local mode="${1:-${UPDATE_SOURCE:-auto}}" base_url version cb version_url
  cb="$(date +%s)"
  while IFS= read -r base_url; do
    [[ -n "$base_url" ]] || continue
    version_url="$(update_url_with_cache_bust "${base_url}/version" "$cb")"
    version="$(curl -fsSL "$version_url" 2>/dev/null | tr -d '[:space:]' || true)"
    if [[ -n "$version" ]]; then
      SBD_ACTIVE_UPDATE_BASE_URL="$base_url"
      echo "$version"
      return 0
    fi
  done < <(update_base_candidates "$mode")
  return 1
}

perform_script_self_update() {
  local mode="${UPDATE_SOURCE:-auto}" base_url ok="false" cb
  cb="$(date +%s)"

  local files=(
    "sing-box-deve.sh"
    "version"
    "README.md"
    "CHANGELOG.md"
    "CONTRIBUTING.md"
    "LICENSE"
    "config.env.example"
    "lib/common.sh"
    "lib/common_base.sh"
    "lib/common_settings.sh"
    "lib/common_update_sources.sh"
    "lib/common_update.sh"
    "lib/common_context.sh"
    "lib/common_doctor.sh"
    "lib/protocols.sh"
    "lib/security.sh"
    "lib/legacy_compat.sh"
    "lib/providers.sh"
    "lib/providers_base.sh"
    "lib/providers_params.sh"
    "lib/providers_release.sh"
    "lib/providers_outbound.sh"
    "lib/providers_routing_port_egress.sh"
    "lib/providers_routing.sh"
    "lib/providers_argo.sh"
    "lib/providers_share.sh"
    "lib/providers_config_shared.sh"
    "lib/providers_config_singbox.sh"
    "lib/providers_config_xray.sh"
    "lib/providers_nodes.sh"
    "lib/providers_client_templates.sh"
    "lib/providers_install.sh"
    "lib/providers_serv00.sh"
    "lib/providers_sap.sh"
    "lib/providers_docker.sh"
    "lib/providers_manage.sh"
    "lib/providers_port_seed.sh"
    "lib/providers_ports.sh"
    "lib/providers_port_egress.sh"
    "lib/providers_config_ops.sh"
    "lib/providers_protocol_ops.sh"
    "lib/providers_config_lock.sh"
    "lib/providers_config_flow.sh"
    "lib/providers_split3.sh"
    "lib/providers_jump_ports.sh"
    "lib/providers_system_tools.sh"
    "lib/providers_subscriptions.sh"
    "lib/providers_panel.sh"
    "lib/providers_doctor.sh"
    "lib/providers_uninstall.sh"
    "lib/output.sh"
    "lib/menu.sh"
    "lib/menu_base.sh"
    "lib/menu_sections.sh"
    "lib/menu_subscriptions.sh"
    "lib/menu_config_center.sh"
    "lib/menu_ops.sh"
    "lib/menu_main.sh"
    "lib/cli_args.sh"
    "lib/cli_args_port_egress.sh"
    "lib/cli_args_update.sh"
    "lib/cli_commands.sh"
    "lib/cli_wizard.sh"
    "lib/cli_main_handlers.sh"
    "lib/cli_main.sh"
    "docs/README.md"
    "docs/V1-SPEC.md"
    "docs/CONVENTIONS.md"
    "docs/ACCEPTANCE-MATRIX.md"
    "docs/PANEL-TEMPLATE.md"
    "docs/REAL-WORLD-VALIDATION.md"
    "docs/Serv00.md"
    "docs/SAP.md"
    "docs/Docker.md"
    "examples/vps-lite.env"
    "examples/vps-full-argo.env"
    "examples/docker.env"
    "examples/settings.conf"
    "examples/serv00-accounts.json"
    "examples/sap-accounts.json"
    "web-generator/index.html"
    "providers/entry.sh"
    "providers/vps.sh"
    "providers/serv00.sh"
    "providers/sap.sh"
    "providers/docker.sh"
    "scripts/acceptance-matrix.sh"
    "scripts/integration-smoke.sh"
    "scripts/consistency-check.sh"
    "scripts/regression-docker.sh"
    "scripts/update-checksums.sh"
    ".github/workflows/main.yml"
    ".github/workflows/mainh.yml"
    ".github/workflows/ci.yml"
    "workers/_worker.js"
    "workers/workers_keep.js"
  )

  while IFS= read -r base_url; do
    [[ -n "$base_url" ]] || continue
    local tmp_dir checksums_file failed rel expected actual
    tmp_dir="$(mktemp -d)"
    checksums_file="${tmp_dir}/checksums.txt"
    failed="false"
    log_info "$(msg "尝试更新源" "Trying update source"): ${base_url}"
    if ! download_file "$(update_url_with_cache_bust "${base_url}/checksums.txt" "$cb")" "$checksums_file"; then
      failed="true"
    fi

    if [[ "$failed" == "false" ]]; then
      for rel in "${files[@]}"; do
        mkdir -p "${tmp_dir}/$(dirname "$rel")"
        if ! download_file "$(update_url_with_cache_bust "${base_url}/${rel}" "$cb")" "${tmp_dir}/${rel}"; then
          failed="true"; break
        fi
        expected="$(grep -E "[[:space:]]${rel}$" "$checksums_file" | awk '{print $1}' | head -n1)"
        if [[ -z "$expected" ]]; then
          log_warn "$(msg "校验表缺少条目: ${rel}" "Checksum entry missing: ${rel}")"
          failed="true"
          break
        fi
        actual="$(sha256sum "${tmp_dir}/${rel}" | awk '{print $1}')"
        if [[ "$expected" != "$actual" ]]; then
          log_warn "$(msg "校验失败: ${rel} 期望=${expected} 实际=${actual}" "Checksum mismatch: ${rel} expected=${expected} actual=${actual}")"
          failed="true"
          break
        fi
      done
    fi

    if [[ "$failed" == "false" ]]; then
      for rel in "${files[@]}"; do
        install -D -m 0644 "${tmp_dir}/${rel}" "${PROJECT_ROOT}/${rel}"
      done
      install -D -m 0644 "$checksums_file" "${PROJECT_ROOT}/checksums.txt"
      chmod +x "${PROJECT_ROOT}/sing-box-deve.sh" \
        "${PROJECT_ROOT}/lib/common.sh" "${PROJECT_ROOT}/lib/protocols.sh" "${PROJECT_ROOT}/lib/security.sh" "${PROJECT_ROOT}/lib/providers.sh" "${PROJECT_ROOT}/lib/output.sh" \
        "${PROJECT_ROOT}/providers/entry.sh" "${PROJECT_ROOT}/providers/vps.sh" "${PROJECT_ROOT}/providers/serv00.sh" "${PROJECT_ROOT}/providers/sap.sh" "${PROJECT_ROOT}/providers/docker.sh" \
        "${PROJECT_ROOT}/scripts/acceptance-matrix.sh" "${PROJECT_ROOT}/scripts/integration-smoke.sh" "${PROJECT_ROOT}/scripts/consistency-check.sh" "${PROJECT_ROOT}/scripts/regression-docker.sh" "${PROJECT_ROOT}/scripts/update-checksums.sh" || true
      rm -rf "$tmp_dir"
      SBD_ACTIVE_UPDATE_BASE_URL="$base_url"
      ok="true"
      break
    fi
    rm -rf "$tmp_dir"
    log_warn "$(msg "该更新源失败，尝试下一个" "Update source failed, trying next one")"
  done < <(update_base_candidates "$mode")

  [[ "$ok" == "true" ]] || die "$(msg "安全更新失败：所有更新源不可用或校验失败" "Secure update failed: all update sources unavailable or checksum verification failed")"
}
