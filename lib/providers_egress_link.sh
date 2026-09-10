#!/usr/bin/env bash

sbd_egress_link_parse() {
  local link="$1" format="${2:-info}"
  printf '%s' "$link" | python3 "$PROJECT_ROOT/scripts/egress-link.py" "$format"
}

# The link owns protocol-specific credentials. Existing fields are projections
# used by status/route consumers and are refreshed whenever the link is loaded.
sbd_egress_link_load() {
  [[ -n "${OUTBOUND_PROXY_LINK:-}" ]] || return 0
  local info
  info="$(sbd_egress_link_parse "$OUTBOUND_PROXY_LINK")" || return 1
  OUTBOUND_PROXY_MODE="$(jq -er .kind <<< "$info")" || return 1
  OUTBOUND_PROXY_HOST="$(jq -er .server <<< "$info")" || return 1
  OUTBOUND_PROXY_PORT="$(jq -er .port <<< "$info")" || return 1
  OUTBOUND_PROXY_USER=""
  OUTBOUND_PROXY_PASS=""
  if [[ "${OUTBOUND_PROXY_UDP_MODE:-proxy}" == proxy && "$(jq -r .udp <<< "$info")" != true ]]; then
    log_error "This node does not carry UDP; use --udp direct or --udp block"
    return 1
  fi
  export OUTBOUND_PROXY_MODE OUTBOUND_PROXY_HOST OUTBOUND_PROXY_PORT OUTBOUND_PROXY_USER OUTBOUND_PROXY_PASS OUTBOUND_PROXY_LINK
}

sbd_egress_validate_engine() {
  local target_engine="$1"
  [[ -n "${OUTBOUND_PROXY_LINK:-}" ]] || return 0
  sbd_egress_link_parse "$OUTBOUND_PROXY_LINK" "$target_engine" >/dev/null
}

sbd_egress_read_link_file() {
  local file="$1"
  [[ -f "$file" && -r "$file" ]] || { log_error "Node link file is not readable"; return 1; }
  python3 "$PROJECT_ROOT/scripts/egress-link.py" link < "$file"
}

sbd_egress_prompt_link() {
  local info udp_default=proxy
  IFS= read -r -s -p "$(msg "粘贴节点分享链接（不回显）" "Paste node share link (hidden)"): " OUTBOUND_PROXY_LINK || return 1
  printf '\n'
  info="$(sbd_egress_link_parse "$OUTBOUND_PROXY_LINK")" || return 1
  [[ "$(jq -r .udp <<< "$info")" == true ]] || udp_default=direct
  prompt_with_default "$(msg "UDP 策略 [proxy/direct/block]" "UDP policy [proxy/direct/block]")" "$udp_default" OUTBOUND_PROXY_UDP_MODE
  sbd_egress_link_load
}
