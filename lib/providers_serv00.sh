#!/usr/bin/env bash

validate_serv00_accounts_json() {
  jq -e 'type == "array" and length > 0 and all(.[];
    type == "object" and (.host|type == "string" and length > 0)
    and (.user|type == "string" and length > 0)
    and (.pass|type == "string" and length > 0)
    and ((has("cmd")|not) or (.cmd|type == "string")))' \
    <<< "$1" >/dev/null || { log_error "Invalid SERV00_ACCOUNTS_JSON account schema"; return 1; }
}

serv00_remote_command() {
  if [[ -n "${SERV00_BOOTSTRAP_CMD:-}" ]]; then
    printf '%s\n' "$SERV00_BOOTSTRAP_CMD"
    return 0
  fi
  local url="${SERV00_BOOTSTRAP_URL:-}" digest="${SERV00_BOOTSTRAP_SHA256:-}" quoted_url
  [[ "$url" == https://* && "$digest" =~ ^[a-fA-F0-9]{64}$ ]] || {
    log_error "Serv00 requires an explicitly trusted SERV00_BOOTSTRAP_URL + SHA256 or compatibility SERV00_BOOTSTRAP_CMD"
    return 1
  }
  printf -v quoted_url '%q' "$url"
  cat <<EOF
set -eu
runner=\$(command -v timeout || command -v gtimeout) || exit 127
artifact=\$(mktemp)
trap 'rm -f "\$artifact"' EXIT
curl -fsSL --connect-timeout 10 --max-time 60 ${quoted_url} -o "\$artifact"
if command -v sha256sum >/dev/null; then
  actual=\$(sha256sum "\$artifact"); actual=\${actual%% *}
else
  actual=\$(sha256 -q "\$artifact")
fi
[ "\$actual" = "${digest,,}" ] || exit 1
"\$runner" -k 5s 120s bash "\$artifact"
EOF
}

serv00_deploy_account() {
  local host="$1" user="$2" pass="$3" cmd="$4" attempt max_attempts
  local retries="${SERV00_RETRY_COUNT:-1}"
  [[ "$retries" =~ ^[0-9]+$ && "$retries" -le 5 ]] || { log_error "SERV00_RETRY_COUNT must be 0..5"; return 2; }
  max_attempts=$((retries + 1))
  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    if sbd_ssh_exec "$host" "$user" "$pass" "$cmd"; then return 0; fi
    log_warn "Serv00 attempt ${attempt}/${max_attempts} failed: ${user}@${host}"
    # A timed-out remote operation may still be running. Retrying arbitrary
    # bootstrap commands is unsafe unless the backend explicitly guarantees it.
    [[ "${SERV00_BOOTSTRAP_IDEMPOTENT:-false}" == true ]] || break
  done
  return 1
}

provider_serv00_install() {
  local profile="$1" engine="$2" protocols_csv="$3" remote_cmd="" item host user pass cmd
  local count=0 success=0 failed=0 skipped=0 accounts_fd
  reject_tls_auto_for_provider serv00 || return 1
  validate_feature_modes || return 1
  if [[ -n "${SERV00_ACCOUNTS_JSON:-}" || -n "${SERV00_HOST:-}${SERV00_USER:-}${SERV00_PASS:-}" ]]; then
    [[ "${AUTO_YES:-false}" == true || -t 0 ]] || { log_error "Remote bootstrap needs a terminal or explicit --yes"; return 1; }
    command -v sshpass >/dev/null || { log_error "Install sshpass before remote bootstrap"; return 1; }
    remote_cmd="$(serv00_remote_command)" || return 1
    if [[ -n "${SERV00_ACCOUNTS_JSON:-}" ]]; then
      validate_serv00_accounts_json "$SERV00_ACCOUNTS_JSON" || return 1
      exec {accounts_fd}< <(jq -c '.[]' <<< "$SERV00_ACCOUNTS_JSON")
      while IFS= read -r -u "$accounts_fd" item; do
        host="$(jq -r .host <<< "$item")"; user="$(jq -r .user <<< "$item")"; pass="$(jq -r .pass <<< "$item")"
        cmd="$(jq -r '.cmd // empty' <<< "$item")"; [[ -n "$cmd" ]] || cmd="$remote_cmd"
        count=$((count + 1))
        if ! prompt_yes_no "Remote bootstrap for ${user}@${host}?" N; then skipped=$((skipped + 1)); continue; fi
        if serv00_deploy_account "$host" "$user" "$pass" "$cmd"; then success=$((success + 1)); else failed=$((failed + 1)); fi
      done
      exec {accounts_fd}<&-
      log_info "Serv00 batch summary: total=${count} success=${success} failed=${failed} skipped=${skipped}"
      (( failed == 0 )) || return 1
    else
      [[ -n "${SERV00_HOST:-}" && -n "${SERV00_USER:-}" && -n "${SERV00_PASS:-}" ]] || { log_error "Incomplete Serv00 credentials"; return 1; }
      prompt_yes_no "Remote bootstrap for ${SERV00_USER}@${SERV00_HOST}?" N || return 1
      serv00_deploy_account "$SERV00_HOST" "$SERV00_USER" "$SERV00_PASS" "$remote_cmd" || return 1
    fi
  else
    log_info "SERV00 credentials not set; generating a local deployment bundle"
  fi
  provider_prepare_domain_runtime_artifacts "$protocols_csv" || return 1
  mkdir -p "$SBD_CONFIG_DIR" || return 1
  local tmp
  tmp="$(mktemp "$SBD_CONFIG_DIR/serv00.env.XXXXXX")" || return 1
  {
    sbd_write_env_kv profile "$profile"
    sbd_write_env_kv engine "$engine"
    sbd_write_env_kv protocols "$protocols_csv"
  } > "$tmp" || return 1
  sbd_commit_file_with_backups "$SBD_CONFIG_DIR/serv00.env" "$tmp" 600 || return 1
  tmp="$(mktemp "$SBD_CONFIG_DIR/serv00-run.XXXXXX")" || return 1
  {
    printf '#!/usr/bin/env bash\nset -euo pipefail\n'
    printf 'exec bash %q install --provider serv00 --profile %q --engine %q --protocols %q "$@"\n' \
      "$PROJECT_ROOT/sing-box-deve.sh" "$profile" "$engine" "$protocols_csv"
  } > "$tmp" || return 1
  sbd_commit_file_with_backups "$SBD_CONFIG_DIR/serv00-run.sh" "$tmp" 700 || return 1
  log_success "Serv00 deployment bundle generated at ${SBD_CONFIG_DIR}"
}
