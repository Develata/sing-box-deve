#!/usr/bin/env bash

SBD_SHARE_RAW_FILE="${SBD_DATA_DIR}/jhdy.txt"
SBD_SHARE_BASE64_FILE="${SBD_DATA_DIR}/jh_sub.txt"
SBD_SHARE_GROUP_DIR="${SBD_DATA_DIR}/share-groups"

share_filter_supported_links() {
  local src="$1" out="$2"
  awk '
    /^(vless|vmess|trojan|ss|hysteria2|tuic|socks|wireguard|anytls):\/\// {print}
  ' "$src" > "$out"
}

share_encode_base64_file() {
  local src="$1" out="$2"
  if [[ -s "$src" ]]; then
    base64 -w 0 < "$src" > "$out"
  else
    : > "$out"
  fi
}

share_build_group_file() {
  local regex="$1" out="$2"
  if [[ -s "$SBD_SHARE_RAW_FILE" ]]; then
    grep -E "$regex" "$SBD_SHARE_RAW_FILE" > "$out" || true
  else
    : > "$out"
  fi
}

share_generate_groups() {
  mkdir -p "$SBD_SHARE_GROUP_DIR"
  cp "$SBD_SHARE_RAW_FILE" "$SBD_SHARE_GROUP_DIR/all.txt"

  share_build_group_file '^(vless|vmess|trojan|ss|hysteria2|tuic|socks|wireguard|anytls)://' "$SBD_SHARE_GROUP_DIR/v2rayn.txt"
  share_build_group_file '^(vless|vmess|trojan|ss|hysteria2|tuic|socks)://' "$SBD_SHARE_GROUP_DIR/v2rayng.txt"
  share_build_group_file '^(vless|vmess|trojan|ss|hysteria2|tuic|socks|wireguard|anytls)://' "$SBD_SHARE_GROUP_DIR/nekobox.txt"
  share_build_group_file '^(vless|vmess|trojan|ss)://' "$SBD_SHARE_GROUP_DIR/shadowrocket.txt"
  share_build_group_file '^(vless|vmess|trojan|ss|hysteria2|tuic|wireguard|socks|anytls)://' "$SBD_SHARE_GROUP_DIR/singbox.txt"
  cat > "$SBD_SHARE_GROUP_DIR/clash-meta.txt" <<EOF_CLASH_META
# clash-meta 建议直接使用 YAML 配置文件，而不是通用协议链接
${SBD_DATA_DIR}/clash_meta_client.yaml
EOF_CLASH_META

  cat > "$SBD_SHARE_GROUP_DIR/index.txt" <<EOF_INDEX
all: all.txt
v2rayn: v2rayn.txt
v2rayng: v2rayng.txt
nekobox: nekobox.txt
shadowrocket: shadowrocket.txt
sing-box-client: singbox.txt
clash-meta-client: clash-meta.txt (yaml path)
EOF_INDEX
}

share_generate_bundle() {
  local nodes_file="${1:-$SBD_NODES_FILE}"
  [[ -f "$nodes_file" ]] || die "nodes file not found: ${nodes_file}"
  mkdir -p "$SBD_DATA_DIR"
  mkdir -p "$SBD_SHARE_GROUP_DIR"

  share_filter_supported_links "$nodes_file" "$SBD_SHARE_RAW_FILE"
  if [[ ! -s "$SBD_SHARE_RAW_FILE" ]]; then
    cp "$nodes_file" "$SBD_SHARE_RAW_FILE"
  fi

  share_encode_base64_file "$SBD_SHARE_RAW_FILE" "$SBD_SHARE_BASE64_FILE"
  cp "$SBD_SHARE_BASE64_FILE" "$SBD_SUB_FILE"
  share_generate_groups
}

share_group_path() {
  local name="$1"
  case "$name" in
    all) echo "$SBD_SHARE_GROUP_DIR/all.txt" ;;
    v2rayn) echo "$SBD_SHARE_GROUP_DIR/v2rayn.txt" ;;
    v2rayng) echo "$SBD_SHARE_GROUP_DIR/v2rayng.txt" ;;
    nekobox) echo "$SBD_SHARE_GROUP_DIR/nekobox.txt" ;;
    shadowrocket) echo "$SBD_SHARE_GROUP_DIR/shadowrocket.txt" ;;
    singbox) echo "$SBD_SHARE_GROUP_DIR/singbox.txt" ;;
    clash-meta) echo "$SBD_SHARE_GROUP_DIR/clash-meta.txt" ;;
    *) return 1 ;;
  esac
}

share_group_count() {
  local name="$1" file
  file="$(share_group_path "$name" 2>/dev/null || true)"
  [[ -f "$file" ]] || {
    echo 0
    return 0
  }
  awk 'NF && $1 !~ /^#/{c++} END{print c+0}' "$file"
}

share_print_group() {
  local title="$1" file="$2" with_qr="${3:-false}"
  [[ -f "$file" ]] || return 0
  local count
  count="$(awk 'NF && $1 !~ /^#/{c++} END{print c+0}' "$file")"
  [[ "$count" -gt 0 ]] || return 0

  echo
  log_info "${title} (${count})"
  cat "$file"

  if [[ "$with_qr" == "true" ]] && command -v qrencode >/dev/null 2>&1; then
    local line
    while IFS= read -r line; do
      [[ -n "$line" && "$line" != \#* ]] || continue
      qrencode -o - -t ANSIUTF8 "$line"
    done < "$file"
  fi
}

share_show_bundle() {
  local with_qr="${1:-false}"
  [[ -f "$SBD_SHARE_RAW_FILE" ]] || return 0

  log_info "four-in-one raw: $SBD_SHARE_RAW_FILE"
  log_info "four-in-one base64: $SBD_SHARE_BASE64_FILE"
  if [[ -f "$SBD_SHARE_BASE64_FILE" ]]; then
    local b64
    b64="$(cat "$SBD_SHARE_BASE64_FILE")"
    echo "$b64"
    if [[ "$with_qr" == "true" ]] && command -v qrencode >/dev/null 2>&1; then
      qrencode -o - -t ANSIUTF8 "$b64"
      qrencode -o - -t ANSIUTF8 "aggregate-base64://${b64}"
    fi
  fi

  share_print_group "group:v2rayn" "$SBD_SHARE_GROUP_DIR/v2rayn.txt" "$with_qr"
  share_print_group "group:v2rayng" "$SBD_SHARE_GROUP_DIR/v2rayng.txt" "$with_qr"
  share_print_group "group:nekobox" "$SBD_SHARE_GROUP_DIR/nekobox.txt" "$with_qr"
  share_print_group "group:shadowrocket" "$SBD_SHARE_GROUP_DIR/shadowrocket.txt" "$with_qr"
  share_print_group "group:sing-box-client" "$SBD_SHARE_GROUP_DIR/singbox.txt" "$with_qr"
  share_print_group "group:clash-meta-client" "$SBD_SHARE_GROUP_DIR/clash-meta.txt" "$with_qr"
}
