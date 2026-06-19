#!/usr/bin/env bash

protocol_csv_has() {
  local protocols_csv="$1" needle="$2"
  local protocol_items=()
  protocols_to_array "$protocols_csv" protocol_items
  protocol_enabled "$needle" "${protocol_items[@]}"
}

rewrite_link_with_endpoint() {
  local link="$1" endpoint="$2" host port
  shift 2 || true
  if [[ "$endpoint" =~ ^(\[[^]]+\]|[^:]+):([0-9]+)$ ]]; then
    host="${BASH_REMATCH[1]}"; port="${BASH_REMATCH[2]}"
  else
    return 1
  fi

  case "$link" in
    vless://*|hysteria2://*|tuic://*|ss://*|naive+https://*)
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
  local link="$1"
  case "$link" in
    *)
      if [[ "$link" =~ ^[^:]+://[^@]+@([^:/?]+) ]]; then
        echo "${BASH_REMATCH[1]}"
      elif [[ "$link" =~ ^[^:]+://([^:/?]+) ]]; then
        echo "${BASH_REMATCH[1]}"
      fi
      ;;
  esac
}

extract_link_port() {
  local link="$1"
  case "$link" in
    *)
      if [[ "$link" =~ @(\[[^]]+\]|[^:/?#]+):([0-9]+) ]]; then
        echo "${BASH_REMATCH[2]}"
      elif [[ "$link" =~ :([0-9]+)([/?#]|$) ]]; then
        echo "${BASH_REMATCH[1]}"
      fi
      ;;
  esac
}
