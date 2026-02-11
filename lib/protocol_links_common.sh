#!/usr/bin/env bash

protocol_csv_has() {
  local protocols_csv="$1" needle="$2"
  local items=()
  protocols_to_array "$protocols_csv" items
  protocol_enabled "$needle" "${items[@]}"
}

rewrite_link_with_endpoint() {
  local link="$1" endpoint="$2" label="$3" host port payload json out
  if [[ "$endpoint" =~ ^(\[[^]]+\]|[^:]+):([0-9]+)$ ]]; then
    host="${BASH_REMATCH[1]}"; port="${BASH_REMATCH[2]}"
  else
    return 1
  fi

  case "$link" in
    vmess://*)
      payload="${link#vmess://}"
      json="$(printf '%s' "$payload" | base64 -d 2>/dev/null || true)"
      [[ -n "$json" ]] || return 1
      if ! command -v jq >/dev/null 2>&1; then return 1; fi
      out="$(printf '%s' "$json" | jq -c --arg add "$host" --arg port "$port" '.add=$add | .port=$port | .ps=(.ps + "-'"${label}"'")' 2>/dev/null || true)"
      [[ -n "$out" ]] || return 1
      echo "vmess://$(printf '%s' "$out" | base64 -w 0)"
      ;;
    vless://*|trojan://*|hysteria2://*|anytls://*|socks://*|wireguard://*|tuic://*|ss://*)
      local pre after hp suffix
      if [[ "$link" == *"@"* ]]; then
        pre="${link%%@*}@"; after="${link#*@}"
      else
        pre="${link%%://*}://"; after="${link#*://}"
      fi
      hp="${after%%[?#]*}"; suffix="${after#"$hp"}"
      echo "${pre}${host}:${port}${suffix}"
      ;;
    *) return 1 ;;
  esac
}

extract_link_host() {
  local link="$1" payload json
  case "$link" in
    vmess://*)
      payload="${link#vmess://}"
      json="$(printf '%s' "$payload" | base64 -d 2>/dev/null || true)"
      [[ -n "$json" ]] && printf '%s' "$json" | jq -r '.add // empty' 2>/dev/null
      ;;
    *)
      if [[ "$link" =~ ^[^:]+://[^@]+@([^:/?]+) ]]; then
        echo "${BASH_REMATCH[1]}"
      elif [[ "$link" =~ ^[^:]+://([^:/?]+) ]]; then
        echo "${BASH_REMATCH[1]}"
      fi
      ;;
  esac
}
