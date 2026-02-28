#!/usr/bin/env bash
# kp.sh — Local keepalive script for VPS / router / crontab
# Usage:
#   bash kp.sh                     # Run once
#   bash kp.sh --loop [INTERVAL]   # Run in loop (default: 135 minutes)
#   bash kp.sh --install-cron      # Install as crontab entry
#
# Env vars:
#   KP_URLS         — Space/comma-separated keepalive URLs
#   KP_INTERVAL     — Loop interval in minutes (default: 135)
#   KP_CONFIG_FILE  — Path to file with one URL per line

set -euo pipefail

KP_URLS="${KP_URLS:-}"
KP_INTERVAL="${KP_INTERVAL:-135}"
KP_CONFIG_FILE="${KP_CONFIG_FILE:-${HOME}/.sbd-keepalive-urls}"

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

load_urls() {
  local urls=()

  # From env
  if [[ -n "$KP_URLS" ]]; then
    IFS=$',， ' read -r -a env_urls <<< "$KP_URLS"
    urls+=("${env_urls[@]}")
  fi

  # From config file
  if [[ -f "$KP_CONFIG_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%%#*}"
      line="$(echo "$line" | xargs)"
      [[ -n "$line" ]] && urls+=("$line")
    done < "$KP_CONFIG_FILE"
  fi

  if [[ ${#urls[@]} -eq 0 ]]; then
    log "ERROR: No keepalive URLs found."
    log "Set KP_URLS env or create ${KP_CONFIG_FILE} with one URL per line."
    exit 1
  fi

  printf '%s\n' "${urls[@]}"
}

ping_urls() {
  local alive=0 down=0

  while IFS= read -r url; do
    [[ -z "$url" ]] && continue
    local response code
    response="$(curl -sk --max-time 15 "$url" 2>/dev/null || true)"

    if echo "$response" | grep -iqE 'keepalive|UP|running|保活|重启成功|vless|ok|sing-box'; then
      log "✅ ${url}"
      ((alive++))
    else
      code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 "$url" 2>/dev/null || echo "000")"
      if [[ "$code" =~ ^[23] ]]; then
        log "✅ ${url} (HTTP ${code})"
        ((alive++))
      else
        log "❌ ${url} (HTTP ${code})"
        ((down++))
      fi
    fi
  done < <(load_urls)

  log "── Summary: alive=${alive} down=${down} ──"
}

install_cron() {
  local script_path
  script_path="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  local tag="# sbd:keepalive"

  local existing
  existing="$(crontab -l 2>/dev/null || true)"
  existing="$(echo "$existing" | grep -v "$tag" || true)"

  local entry="*/${KP_INTERVAL} * * * * bash ${script_path} >> /tmp/sbd-keepalive.log 2>&1 ${tag}"
  if [[ -n "$existing" ]]; then
    printf '%s\n%s\n' "$existing" "$entry" | crontab -
  else
    printf '%s\n' "$entry" | crontab -
  fi
  log "Crontab installed: every ${KP_INTERVAL} minutes"
  log "Logs: /tmp/sbd-keepalive.log"
}

case "${1:-}" in
  --loop)
    interval="${2:-$KP_INTERVAL}"
    log "Running keepalive loop every ${interval} minutes"
    while true; do
      ping_urls
      sleep "$((interval * 60))"
    done
    ;;
  --install-cron)
    install_cron
    ;;
  --help|-h)
    echo "Usage: bash kp.sh [--loop [INTERVAL]] [--install-cron]"
    echo "  Env: KP_URLS='http://url1 http://url2'  or  create ~/.sbd-keepalive-urls"
    ;;
  *)
    ping_urls
    ;;
esac
