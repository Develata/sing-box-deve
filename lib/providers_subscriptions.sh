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
  render_singbox_client_json "${SBD_DATA_DIR}/sing_box_client.json"
  render_clash_meta_yaml "${SBD_DATA_DIR}/clash_meta_client.yaml"
  render_sfa_sfi_sfw "SFA" "${SBD_DATA_DIR}/sfa_client.json"
  render_sfa_sfi_sfw "SFI" "${SBD_DATA_DIR}/sfi_client.json"
  render_sfa_sfi_sfw "SFW" "${SBD_DATA_DIR}/sfw_client.json"
  share_generate_bundle "$SBD_NODES_FILE"
}

provider_sub_refresh() {
  ensure_root
  [[ -f /etc/sing-box-deve/runtime.env ]] || die "No runtime state found"
  # shellcheck disable=SC1091
  source /etc/sing-box-deve/runtime.env
  write_nodes_output "${engine:-sing-box}" "${protocols:-vless-reality}"
  generate_client_artifacts
  log_success "$(msg "订阅与分享产物已刷新" "Subscription artifacts refreshed")"
}

provider_sub_show() {
  load_subscription_env
  [[ -f "$SBD_NODES_FILE" ]] && log_info "$(msg "节点文件: $SBD_NODES_FILE" "nodes: $SBD_NODES_FILE")"
  [[ -f "$SBD_SUB_FILE" ]] && log_info "$(msg "聚合订阅: $SBD_SUB_FILE" "aggregate: $SBD_SUB_FILE")"
  [[ -f "${SBD_DATA_DIR}/sing_box_client.json" ]] && log_info "$(msg "sing-box 客户端配置: ${SBD_DATA_DIR}/sing_box_client.json" "sing-box client: ${SBD_DATA_DIR}/sing_box_client.json")"
  [[ -f "${SBD_DATA_DIR}/clash_meta_client.yaml" ]] && log_info "$(msg "clash-meta 客户端配置: ${SBD_DATA_DIR}/clash_meta_client.yaml" "clash-meta client: ${SBD_DATA_DIR}/clash_meta_client.yaml")"
  [[ -f "${SBD_DATA_DIR}/sfa_client.json" ]] && log_info "$(msg "SFA 客户端配置: ${SBD_DATA_DIR}/sfa_client.json" "SFA client: ${SBD_DATA_DIR}/sfa_client.json")"
  [[ -f "${SBD_DATA_DIR}/sfi_client.json" ]] && log_info "$(msg "SFI 客户端配置: ${SBD_DATA_DIR}/sfi_client.json" "SFI client: ${SBD_DATA_DIR}/sfi_client.json")"
  [[ -f "${SBD_DATA_DIR}/sfw_client.json" ]] && log_info "$(msg "SFW 客户端配置: ${SBD_DATA_DIR}/sfw_client.json" "SFW client: ${SBD_DATA_DIR}/sfw_client.json")"
  share_show_bundle true
  if [[ -f "${SBD_DATA_DIR}/gitlab_urls.txt" ]]; then
    cat "${SBD_DATA_DIR}/gitlab_urls.txt"
    if command -v qrencode >/dev/null 2>&1; then
      while IFS= read -r line; do
        [[ "$line" == *": "* ]] || continue
        qrencode -o - -t ANSIUTF8 "${line#*: }"
      done < "${SBD_DATA_DIR}/gitlab_urls.txt"
    fi
  fi
}

provider_sub_gitlab_set() {
  ensure_root
  load_subscription_env
  GITLAB_TOKEN="$1"
  GITLAB_PROJECT="$2"
  GITLAB_BRANCH="${3:-main}"
  GITLAB_SUB_PATH="${4:-subs}"
  [[ -n "$GITLAB_TOKEN" && -n "$GITLAB_PROJECT" ]] || die "Usage: sub gitlab-set <token> <group/project> [branch] [path]"
  save_subscription_env
  log_success "$(msg "GitLab 订阅配置已保存" "GitLab subscription settings saved")"
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
  cp "$SBD_SHARE_RAW_FILE" "$tmp/${GITLAB_SUB_PATH:-subs}/jhdy.txt"
  cp "$SBD_SHARE_BASE64_FILE" "$tmp/${GITLAB_SUB_PATH:-subs}/jh_sub.txt"
  if [[ -d "$SBD_SHARE_GROUP_DIR" ]]; then
    cp -r "$SBD_SHARE_GROUP_DIR" "$tmp/${GITLAB_SUB_PATH:-subs}/share-groups"
  fi
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
jh-raw: ${raw}/jhdy.txt
jh-base64: ${raw}/jh_sub.txt
group-v2rayn: ${raw}/share-groups/v2rayn.txt
group-v2rayng: ${raw}/share-groups/v2rayng.txt
group-nekobox: ${raw}/share-groups/nekobox.txt
group-shadowrocket: ${raw}/share-groups/shadowrocket.txt
group-singbox: ${raw}/share-groups/singbox.txt
group-clash-meta: ${raw}/clash_meta_client.yaml
SFA-client: ${raw}/sfa_client.json
SFI-client: ${raw}/sfi_client.json
SFW-client: ${raw}/sfw_client.json
EOF
  rm -rf "$tmp"
  log_success "$(msg "GitLab 订阅推送完成" "GitLab subscription pushed")"
  cat "${SBD_DATA_DIR}/gitlab_urls.txt"
}

provider_sub_tg_set() {
  ensure_root
  load_subscription_env
  TG_BOT_TOKEN="$1"
  TG_CHAT_ID="$2"
  [[ -n "$TG_BOT_TOKEN" && -n "$TG_CHAT_ID" ]] || die "Usage: sub tg-set <bot_token> <chat_id>"
  save_subscription_env
  log_success "$(msg "Telegram 推送配置已保存" "Telegram settings saved")"
}

provider_sub_tg_push() {
  ensure_root
  load_subscription_env
  [[ -n "${TG_BOT_TOKEN:-}" && -n "${TG_CHAT_ID:-}" ]] || die "Telegram settings missing, run: sub tg-set"
  provider_sub_refresh
  local text b64 c_all c_v2n c_v2g c_neko c_sr c_sb c_cm
  b64="$(cat "$SBD_SHARE_BASE64_FILE" 2>/dev/null || true)"
  c_all="$(share_group_count all)"
  c_v2n="$(share_group_count v2rayn)"
  c_v2g="$(share_group_count v2rayng)"
  c_neko="$(share_group_count nekobox)"
  c_sr="$(share_group_count shadowrocket)"
  c_sb="$(share_group_count singbox)"
  c_cm="$(share_group_count clash-meta)"
  text="sing-box-deve links

counts: all=${c_all} v2rayn=${c_v2n} v2rayng=${c_v2g} nekobox=${c_neko} shadowrocket=${c_sr} singbox=${c_sb} clash-meta-yaml=${c_cm}

four-in-one(base64):
${b64}

four-in-one(uri):
aggregate-base64://${b64}"
  if [[ -z "$b64" ]]; then
    text="sing-box-deve links

counts: all=${c_all} v2rayn=${c_v2n} v2rayng=${c_v2g} nekobox=${c_neko} shadowrocket=${c_sr} singbox=${c_sb} clash-meta-yaml=${c_cm}

four-in-one(base64): unavailable"
  fi
  curl -fsSL -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TG_CHAT_ID}" \
    --data-urlencode text="${text}" >/dev/null
  log_success "$(msg "Telegram 推送已发送" "Telegram push sent")"
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
