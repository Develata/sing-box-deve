#!/usr/bin/env bash

SBD_SUB_ENV_FILE="/etc/sing-box-deve/subscription.env"

load_subscription_env() {
  [[ -f "$SBD_SUB_ENV_FILE" ]] || return 0
  # shellcheck disable=SC1090
  source "$SBD_SUB_ENV_FILE"
}

save_subscription_env() {
  mkdir -p /etc/sing-box-deve
  cat > "$SBD_SUB_ENV_FILE" <<EOF
GITLAB_TOKEN=${GITLAB_TOKEN:-}
GITLAB_PROJECT=${GITLAB_PROJECT:-}
GITLAB_BRANCH=${GITLAB_BRANCH:-main}
GITLAB_SUB_PATH=${GITLAB_SUB_PATH:-subs}
TG_BOT_TOKEN=${TG_BOT_TOKEN:-}
TG_CHAT_ID=${TG_CHAT_ID:-}
EOF
}

generate_client_artifacts() {
  mkdir -p "$SBD_DATA_DIR"
  [[ -f "$SBD_NODES_FILE" ]] || die "nodes file not found"
  [[ -f "$SBD_SUB_FILE" ]] || build_aggregate_subscription

  cat > "${SBD_DATA_DIR}/sing_box_client.json" <<EOF
{
  "version": "sbd-subscription-v1",
  "generated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "aggregate_base64": "$(cat "$SBD_SUB_FILE")",
  "nodes_file": "${SBD_NODES_FILE}"
}
EOF

  cat > "${SBD_DATA_DIR}/clash_meta_client.yaml" <<EOF
# sing-box-deve generated subscription bundle
# generated_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# aggregate_base64:
# $(cat "$SBD_SUB_FILE")
# nodes:
EOF
  sed 's/^/# /' "$SBD_NODES_FILE" >> "${SBD_DATA_DIR}/clash_meta_client.yaml"

  cat > "${SBD_DATA_DIR}/sfa_client.json" <<EOF
{
  "app": "SFA",
  "generated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "subscription_base64": "$(cat "$SBD_SUB_FILE")",
  "source_nodes": "${SBD_NODES_FILE}"
}
EOF
  cp "${SBD_DATA_DIR}/sfa_client.json" "${SBD_DATA_DIR}/sfi_client.json"
  cp "${SBD_DATA_DIR}/sfa_client.json" "${SBD_DATA_DIR}/sfw_client.json"
  sed -i 's/"SFA"/"SFI"/g' "${SBD_DATA_DIR}/sfi_client.json"
  sed -i 's/"SFA"/"SFW"/g' "${SBD_DATA_DIR}/sfw_client.json"

  cp "$SBD_NODES_FILE" "${SBD_DATA_DIR}/jh_sub.txt"
  cp "$SBD_NODES_FILE" "${SBD_DATA_DIR}/jhdy.txt"
}

provider_sub_refresh() {
  ensure_root
  [[ -f /etc/sing-box-deve/runtime.env ]] || die "No runtime state found"
  # shellcheck disable=SC1091
  source /etc/sing-box-deve/runtime.env
  write_nodes_output "${engine:-sing-box}" "${protocols:-vless-reality}"
  generate_client_artifacts
  log_success "Subscription artifacts refreshed"
}

provider_sub_show() {
  load_subscription_env
  [[ -f "$SBD_NODES_FILE" ]] && log_info "nodes: $SBD_NODES_FILE"
  [[ -f "$SBD_SUB_FILE" ]] && log_info "aggregate: $SBD_SUB_FILE"
  [[ -f "${SBD_DATA_DIR}/sing_box_client.json" ]] && log_info "sing-box client: ${SBD_DATA_DIR}/sing_box_client.json"
  [[ -f "${SBD_DATA_DIR}/clash_meta_client.yaml" ]] && log_info "clash-meta client: ${SBD_DATA_DIR}/clash_meta_client.yaml"
  [[ -f "${SBD_DATA_DIR}/sfa_client.json" ]] && log_info "SFA client: ${SBD_DATA_DIR}/sfa_client.json"
  [[ -f "${SBD_DATA_DIR}/sfi_client.json" ]] && log_info "SFI client: ${SBD_DATA_DIR}/sfi_client.json"
  [[ -f "${SBD_DATA_DIR}/sfw_client.json" ]] && log_info "SFW client: ${SBD_DATA_DIR}/sfw_client.json"
  if [[ -f "$SBD_SUB_FILE" ]]; then
    log_info "aggregate base64:"
    cat "$SBD_SUB_FILE"
    if command -v qrencode >/dev/null 2>&1; then
      qrencode -o - -t ANSIUTF8 "aggregate-base64://$(cat "$SBD_SUB_FILE")"
    fi
  fi
  [[ -f "${SBD_DATA_DIR}/gitlab_urls.txt" ]] && cat "${SBD_DATA_DIR}/gitlab_urls.txt"
}

provider_sub_gitlab_set() {
  ensure_root
  GITLAB_TOKEN="$1"
  GITLAB_PROJECT="$2"
  GITLAB_BRANCH="${3:-main}"
  GITLAB_SUB_PATH="${4:-subs}"
  [[ -n "$GITLAB_TOKEN" && -n "$GITLAB_PROJECT" ]] || die "Usage: sub gitlab-set <token> <group/project> [branch] [path]"
  save_subscription_env
  log_success "GitLab subscription settings saved"
}

provider_sub_gitlab_push() {
  ensure_root
  load_subscription_env
  [[ -n "${GITLAB_TOKEN:-}" && -n "${GITLAB_PROJECT:-}" ]] || die "GitLab settings missing, run: sub gitlab-set"
  provider_sub_refresh

  local tmp
  tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  git -C "$tmp" checkout -B "${GITLAB_BRANCH:-main}" >/dev/null 2>&1
  mkdir -p "$tmp/${GITLAB_SUB_PATH:-subs}"
  cp "$SBD_NODES_FILE" "$tmp/${GITLAB_SUB_PATH:-subs}/nodes.txt"
  cp "$SBD_SUB_FILE" "$tmp/${GITLAB_SUB_PATH:-subs}/nodes-sub.txt"
  cp "${SBD_DATA_DIR}/sing_box_client.json" "$tmp/${GITLAB_SUB_PATH:-subs}/sing_box_client.json"
  cp "${SBD_DATA_DIR}/clash_meta_client.yaml" "$tmp/${GITLAB_SUB_PATH:-subs}/clash_meta_client.yaml"
  cp "${SBD_DATA_DIR}/sfa_client.json" "$tmp/${GITLAB_SUB_PATH:-subs}/sfa_client.json"
  cp "${SBD_DATA_DIR}/sfi_client.json" "$tmp/${GITLAB_SUB_PATH:-subs}/sfi_client.json"
  cp "${SBD_DATA_DIR}/sfw_client.json" "$tmp/${GITLAB_SUB_PATH:-subs}/sfw_client.json"
  git -C "$tmp" add .
  git -C "$tmp" -c user.name='sing-box-deve' -c user.email='noreply@example.com' commit -m "update subscription $(date -u +"%F %T")" >/dev/null 2>&1 || true
  git -C "$tmp" remote add origin "https://oauth2:${GITLAB_TOKEN}@gitlab.com/${GITLAB_PROJECT}.git"
  git -C "$tmp" push -f origin "${GITLAB_BRANCH:-main}" >/dev/null

  local raw="https://gitlab.com/${GITLAB_PROJECT}/-/raw/${GITLAB_BRANCH:-main}/${GITLAB_SUB_PATH:-subs}"
  cat > "${SBD_DATA_DIR}/gitlab_urls.txt" <<EOF
sing-box-sub: ${raw}/nodes-sub.txt
nodes-list: ${raw}/nodes.txt
sing-box-client-json: ${raw}/sing_box_client.json
clash-meta-yaml: ${raw}/clash_meta_client.yaml
SFA-client: ${raw}/sfa_client.json
SFI-client: ${raw}/sfi_client.json
SFW-client: ${raw}/sfw_client.json
EOF
  rm -rf "$tmp"
  log_success "GitLab subscription pushed"
  cat "${SBD_DATA_DIR}/gitlab_urls.txt"
}

provider_sub_tg_set() {
  ensure_root
  TG_BOT_TOKEN="$1"
  TG_CHAT_ID="$2"
  [[ -n "$TG_BOT_TOKEN" && -n "$TG_CHAT_ID" ]] || die "Usage: sub tg-set <bot_token> <chat_id>"
  save_subscription_env
  log_success "Telegram settings saved"
}

provider_sub_tg_push() {
  ensure_root
  load_subscription_env
  [[ -n "${TG_BOT_TOKEN:-}" && -n "${TG_CHAT_ID:-}" ]] || die "Telegram settings missing, run: sub tg-set"
  provider_sub_refresh
  local text
  text="$(cat "$SBD_NODES_FILE")"
  curl -fsSL -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TG_CHAT_ID}" \
    --data-urlencode text="sing-box-deve links\n\n${text}\n\naggregate-base64://$(cat "$SBD_SUB_FILE")" >/dev/null
  log_success "Telegram push sent"
}

provider_sub_command() {
  local action="${1:-show}"
  shift || true
  case "$action" in
    refresh) provider_sub_refresh ;;
    show) provider_sub_show ;;
    gitlab-set) provider_sub_gitlab_set "$@" ;;
    gitlab-push) provider_sub_gitlab_push ;;
    tg-set) provider_sub_tg_set "$@" ;;
    tg-push) provider_sub_tg_push ;;
    *)
      die "Usage: sub [refresh|show|gitlab-set <token> <group/project> [branch] [path]|gitlab-push|tg-set <bot_token> <chat_id>|tg-push]"
      ;;
  esac
}
