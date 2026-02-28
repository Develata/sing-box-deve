#!/usr/bin/env bash
# serv00keep.sh — Independent keepalive script for Serv00 FreeBSD environment
# Can be deployed standalone on Serv00 without the full sing-box-deve framework
#
# Features:
#   - Checks if sing-box/xray process is running, restarts if dead
#   - Checks if cloudflared (argo) is running, restarts if dead
#   - Checks if Node.js web service is running, restarts if dead
#   - Designed to be called by crontab, /up endpoint, or GitHub Actions
#
# Usage: bash serv00keep.sh

USERNAME="$(whoami | tr '[:upper:]' '[:lower:]')"
USERNAME_RAW="$(whoami)"
HOME_DIR="${HOME:-/home/${USERNAME_RAW}}"
LOGS_DIR="${HOME_DIR}/domains/${USERNAME}.serv00.net/logs"
DATA_DIR="${HOME_DIR}/sing-box-deve/data"

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

# ── Check and restart core engine (sing-box or xray) ─────────────

restart_engine() {
  local engine_bin config_file

  # Try to find which engine to use
  if [[ -f "${LOGS_DIR}/sb.txt" ]]; then
    engine_bin="$(cat "${LOGS_DIR}/sb.txt" 2>/dev/null)"
  elif [[ -f "${DATA_DIR}/engine" ]]; then
    engine_bin="$(cat "${DATA_DIR}/engine" 2>/dev/null)"
  fi

  # Default to sing-box
  engine_bin="${engine_bin:-sing-box}"

  # Find config file
  if [[ -f "${LOGS_DIR}/config.json" ]]; then
    config_file="${LOGS_DIR}/config.json"
  elif [[ -f "${HOME_DIR}/sing-box-deve/config/config.json" ]]; then
    config_file="${HOME_DIR}/sing-box-deve/config/config.json"
  fi

  if [[ -z "$config_file" ]]; then
    log "WARN: No config.json found, skipping engine restart"
    return 1
  fi

  local bin_path
  if [[ -x "${LOGS_DIR}/${engine_bin}" ]]; then
    bin_path="${LOGS_DIR}/${engine_bin}"
  elif [[ -x "${HOME_DIR}/sing-box-deve/bin/${engine_bin}" ]]; then
    bin_path="${HOME_DIR}/sing-box-deve/bin/${engine_bin}"
  else
    log "WARN: ${engine_bin} binary not found"
    return 1
  fi

  if pgrep -f "run -c con" >/dev/null 2>&1; then
    log "OK: Core engine is running"
    return 0
  fi

  log "RESTART: Core engine (${engine_bin})"
  cd "$(dirname "$bin_path")" || true
  nohup "$bin_path" run -c "$config_file" >/dev/null 2>&1 &
  sleep 2

  if pgrep -f "run -c con" >/dev/null 2>&1; then
    log "OK: Core engine restarted successfully"
  else
    log "FAIL: Core engine failed to restart"
  fi
}

# ── Check and restart cloudflared ─────────────────────────────────

restart_argo() {
  local cf_bin argo_log

  if [[ -x "${LOGS_DIR}/cloudflared" ]]; then
    cf_bin="${LOGS_DIR}/cloudflared"
  elif [[ -x "${HOME_DIR}/sing-box-deve/bin/cloudflared" ]]; then
    cf_bin="${HOME_DIR}/sing-box-deve/bin/cloudflared"
  else
    return 0  # Argo not configured
  fi

  argo_log="${DATA_DIR}/argo.log"
  [[ -f "$argo_log" ]] || argo_log="${LOGS_DIR}/argo.log"

  if pgrep -f "cloudflared" >/dev/null 2>&1; then
    log "OK: Cloudflared is running"
    return 0
  fi

  # Read argo config
  local argo_mode="temp" argo_token="" target_port="8080"

  if [[ -f "${DATA_DIR}/argo_mode" ]]; then
    argo_mode="$(cat "${DATA_DIR}/argo_mode" 2>/dev/null)"
  fi

  if [[ -f "${DATA_DIR}/argo_token" ]]; then
    argo_token="$(cat "${DATA_DIR}/argo_token" 2>/dev/null)"
  fi

  log "RESTART: Cloudflared (mode=${argo_mode})"
  if [[ "$argo_mode" == "fixed" && -n "$argo_token" ]]; then
    nohup "$cf_bin" tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token "$argo_token" >> "$argo_log" 2>&1 &
  else
    nohup "$cf_bin" tunnel --url "http://127.0.0.1:${target_port}" --edge-ip-version auto --no-autoupdate --protocol http2 >> "$argo_log" 2>&1 &
  fi
  sleep 3
  log "OK: Cloudflared restart attempted"
}

# ── Check and restart Node.js web service ─────────────────────────

restart_web() {
  local app_js

  if [[ -f "${HOME_DIR}/app.js" ]]; then
    app_js="${HOME_DIR}/app.js"
  elif [[ -f "${HOME_DIR}/sing-box-deve/scripts/serv00-app.js" ]]; then
    app_js="${HOME_DIR}/sing-box-deve/scripts/serv00-app.js"
  else
    return 0  # Web service not configured
  fi

  if pgrep -f "node.*app.js\|node.*serv00-app" >/dev/null 2>&1; then
    log "OK: Web service is running"
    return 0
  fi

  log "RESTART: Node.js web service"
  cd "$(dirname "$app_js")" || true
  nohup node "$app_js" >/dev/null 2>&1 &
  sleep 1
  log "OK: Web service restart attempted"
}

# ── Main ──────────────────────────────────────────────────────────

main() {
  log "═══ sing-box-deve Serv00 Keepalive ═══"
  log "User: ${USERNAME_RAW} | Host: $(hostname 2>/dev/null || echo 'unknown')"

  restart_engine
  restart_argo
  restart_web

  log "═══ Keepalive check complete ═══"
}

main "$@"
