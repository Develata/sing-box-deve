#!/usr/bin/env bash

current_script_version() {
  local version_file="${PROJECT_ROOT}/version"
  if [[ -f "$version_file" ]]; then
    tr -d '[:space:]' < "$version_file"
  else
    echo "v0.0.0-dev"
  fi
}

resolve_update_base_url() {
  if [[ -n "${SBD_UPDATE_BASE_URL:-}" ]]; then
    echo "$SBD_UPDATE_BASE_URL"
    return 0
  fi

  local origin=""
  if command -v git >/dev/null 2>&1 && [[ -d "${PROJECT_ROOT}/.git" ]]; then
    origin="$(git -C "$PROJECT_ROOT" config --get remote.origin.url 2>/dev/null || true)"
  fi

  if [[ "$origin" =~ ^git@github.com:([^/]+)/([^/.]+)(\.git)?$ ]]; then
    echo "https://raw.githubusercontent.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}/main"
    return 0
  fi

  if [[ "$origin" =~ ^https://github.com/([^/]+)/([^/.]+)(\.git)?$ ]]; then
    echo "https://raw.githubusercontent.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}/main"
    return 0
  fi

  echo ""
}

fetch_remote_script_version() {
  local base_url
  base_url="$(resolve_update_base_url)"
  [[ -n "$base_url" ]] || return 1
  curl -fsSL "${base_url}/version" 2>/dev/null | tr -d '[:space:]'
}

perform_script_self_update() {
  local base_url
  base_url="$(resolve_update_base_url)"
  [[ -n "$base_url" ]] || die "Cannot resolve update URL. Set SBD_UPDATE_BASE_URL first."

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
    "lib/common_update.sh"
    "lib/common_context.sh"
    "lib/common_doctor.sh"
    "lib/protocols.sh"
    "lib/security.sh"
    "lib/legacy_compat.sh"
    "lib/providers.sh"
    "lib/providers_base.sh"
    "lib/providers_release.sh"
    "lib/providers_outbound.sh"
    "lib/providers_routing.sh"
    "lib/providers_argo.sh"
    "lib/providers_config_singbox.sh"
    "lib/providers_config_xray.sh"
    "lib/providers_nodes.sh"
    "lib/providers_install.sh"
    "lib/providers_serv00.sh"
    "lib/providers_sap.sh"
    "lib/providers_docker.sh"
    "lib/providers_manage.sh"
    "lib/providers_ports.sh"
    "lib/providers_config_ops.sh"
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
    "lib/cli_commands.sh"
    "lib/cli_wizard.sh"
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
    "scripts/acceptance-matrix.sh"
    "scripts/update-checksums.sh"
    ".github/workflows/main.yml"
    ".github/workflows/mainh.yml"
    ".github/workflows/ci.yml"
    "workers/_worker.js"
    "workers/workers_keep.js"
  )

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local checksums_file="${tmp_dir}/checksums.txt"
  if ! download_file "${base_url}/checksums.txt" "$checksums_file"; then
    die "Secure update requires checksums.txt at update source"
  fi

  local rel
  for rel in "${files[@]}"; do
    mkdir -p "${tmp_dir}/$(dirname "$rel")"
    download_file "${base_url}/${rel}" "${tmp_dir}/${rel}"
    local expected actual
    expected="$(grep -E "[[:space:]]${rel}$" "$checksums_file" | awk '{print $1}' | head -n1)"
    [[ -n "$expected" ]] || die "Missing checksum entry for ${rel}"
    actual="$(sha256sum "${tmp_dir}/${rel}" | awk '{print $1}')"
    [[ "$expected" == "$actual" ]] || die "Checksum mismatch for ${rel}"
  done

  for rel in "${files[@]}"; do
    install -D -m 0644 "${tmp_dir}/${rel}" "${PROJECT_ROOT}/${rel}"
  done

  install -D -m 0644 "$checksums_file" "${PROJECT_ROOT}/checksums.txt"

  chmod +x "${PROJECT_ROOT}/sing-box-deve.sh" \
    "${PROJECT_ROOT}/lib/common.sh" "${PROJECT_ROOT}/lib/protocols.sh" "${PROJECT_ROOT}/lib/security.sh" "${PROJECT_ROOT}/lib/providers.sh" "${PROJECT_ROOT}/lib/output.sh" \
    "${PROJECT_ROOT}/scripts/acceptance-matrix.sh" "${PROJECT_ROOT}/scripts/update-checksums.sh" || true
  rm -rf "$tmp_dir"
}
