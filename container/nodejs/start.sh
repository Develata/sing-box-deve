#!/bin/bash
# sing-box-deve container bootstrap script
# Runs inside Docker / Clawcloud / SAP CF containers
# All configuration is received via environment variables
set -euo pipefail

export LANG=en_US.UTF-8
export HOME="${HOME:-/root}"
SBD_DIR="${HOME}/sing-box-deve"

echo "================================================="
echo "  sing-box-deve container bootstrap"
echo "  https://github.com/Develata/sing-box-deve"
echo "================================================="

case "$(uname -m)" in
  aarch64|arm64) ARCH="arm64" ;;
  x86_64|amd64)  ARCH="amd64" ;;
  *) echo "Unsupported arch: $(uname -m)"; exit 1 ;;
esac

mkdir -p "${SBD_DIR}/bin" "${SBD_DIR}/data" "${SBD_DIR}/config"

detect_ip() {
  local url="https://icanhazip.com"
  local v4 v6
  v4=$(curl -s4m5 -k "$url" 2>/dev/null || true)
  v6=$(curl -s6m5 -k "$url" 2>/dev/null || true)
  [[ -n "$v4" ]] && echo "IPv4: $v4"
  [[ -n "$v6" ]] && echo "IPv6: $v6"
  SERVER_IP="${v4:-$v6}"
  echo "$SERVER_IP" > "${SBD_DIR}/data/server_ip"
}

generate_uuid() {
  local u="${UUID:-${uuid:-}}"
  if [[ -z "$u" ]]; then
    if [[ -f "${SBD_DIR}/data/uuid" ]]; then
      u="$(cat "${SBD_DIR}/data/uuid")"
    elif command -v uuidgen >/dev/null 2>&1; then
      u="$(uuidgen | tr '[:upper:]' '[:lower:]')"
    else
      u="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16 | sed 's/\(.\{8\}\)\(.\{4\}\)\(.\{4\}\)\(.\{4\}\)/\1-\2-\3-\4-/')"
    fi
  fi
  echo "$u" > "${SBD_DIR}/data/uuid"
  UUID="$u"
  echo "UUID: $UUID"
}

download_engine() {
  local engine="${ENGINE:-sing-box}"
  local bin_path="${SBD_DIR}/bin/${engine}"
  if [[ -f "$bin_path" ]]; then
    echo "${engine} binary already exists."
    return 0
  fi
  echo "Downloading ${engine} for ${ARCH}..."
  local base_url="https://github.com/Develata/sing-box-deve/releases/download/binaries"
  if [[ "$engine" == "sing-box" ]]; then
    curl -fsSL "${base_url}/sing-box-${ARCH}" -o "$bin_path" || {
      echo "Failed to download sing-box, trying official release..."
      local ver
      ver=$(curl -fsSL "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | grep -oP '"tag_name":\s*"v\K[^"]+' || echo "1.11.0")
      curl -fsSL "https://github.com/SagerNet/sing-box/releases/download/v${ver}/sing-box-${ver}-linux-${ARCH}.tar.gz" -o /tmp/sb.tar.gz
      tar -xzf /tmp/sb.tar.gz -C /tmp/
      mv /tmp/sing-box-*/sing-box "$bin_path"
      rm -rf /tmp/sb.tar.gz /tmp/sing-box-*
    }
  elif [[ "$engine" == "xray" ]]; then
    curl -fsSL "${base_url}/xray-${ARCH}" -o "$bin_path" || {
      echo "Failed to download xray, trying official release..."
      local ver
      ver=$(curl -fsSL "https://api.github.com/repos/XTLS/Xray-core/releases/latest" | grep -oP '"tag_name":\s*"v\K[^"]+' || echo "25.1.1")
      curl -fsSL "https://github.com/XTLS/Xray-core/releases/download/v${ver}/Xray-linux-${ARCH}.zip" -o /tmp/xray.zip
      unzip -o /tmp/xray.zip xray -d "${SBD_DIR}/bin/"
      rm -f /tmp/xray.zip
    }
  fi
  chmod +x "$bin_path"
  echo "${engine} installed: $("$bin_path" version 2>/dev/null | head -1 || echo 'unknown')"
}

install_cloudflared() {
  local argo_mode="${ARGO_MODE:-off}"
  [[ "$argo_mode" != "off" ]] || return 0
  local cf_bin="${SBD_DIR}/bin/cloudflared"
  if [[ -f "$cf_bin" ]]; then
    echo "cloudflared already exists."
    return 0
  fi
  echo "Downloading cloudflared for ${ARCH}..."
  curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}" -o "$cf_bin"
  chmod +x "$cf_bin"
  echo "cloudflared installed."
}

start_argo() {
  local argo_mode="${ARGO_MODE:-off}"
  [[ "$argo_mode" != "off" ]] || return 0
  local cf_bin="${SBD_DIR}/bin/cloudflared"
  local log_file="${SBD_DIR}/data/argo.log"

  if [[ "$argo_mode" == "fixed" ]]; then
    local token="${ARGO_TOKEN:-}"
    [[ -n "$token" ]] || { echo "ARGO_TOKEN required for fixed mode"; return 1; }
    nohup "$cf_bin" tunnel --no-autoupdate run --token "$token" > "$log_file" 2>&1 &
    echo "Argo fixed tunnel started."
  else
    local ws_port="${ARGO_BACKEND_PORT:-}"
    [[ -n "$ws_port" ]] || ws_port="${PORT:-3000}"
    nohup "$cf_bin" tunnel --no-autoupdate --url "http://localhost:${ws_port}" > "$log_file" 2>&1 &
    sleep 3
    local argo_domain
    argo_domain=$(grep -a "trycloudflare.com" "$log_file" 2>/dev/null | head -1 | grep -oP 'https://\K[^ ]+' || true)
    if [[ -n "$argo_domain" ]]; then
      echo "$argo_domain" > "${SBD_DIR}/data/argo_domain"
      echo "Argo temp tunnel: $argo_domain"
    else
      echo "Waiting for argo domain..."
      sleep 5
      argo_domain=$(grep -a "trycloudflare.com" "$log_file" 2>/dev/null | head -1 | grep -oP 'https://\K[^ ]+' || true)
      [[ -n "$argo_domain" ]] && echo "$argo_domain" > "${SBD_DIR}/data/argo_domain"
      echo "Argo temp tunnel: ${argo_domain:-pending}"
    fi
  fi
}

generate_config() {
  local engine="${ENGINE:-sing-box}"
  local protocols="${PROTOCOLS:-vless-reality,vmess-ws}"
  echo "Generating ${engine} config for protocols: ${protocols}"
  # Delegate to the main sing-box-deve script if available
  if [[ -f "${SBD_DIR}/script/sing-box-deve.sh" ]]; then
    bash "${SBD_DIR}/script/sing-box-deve.sh" apply --runtime 2>/dev/null || true
  fi
}

start_engine() {
  local engine="${ENGINE:-sing-box}"
  local bin_path="${SBD_DIR}/bin/${engine}"
  local config_file="${SBD_DIR}/config/${engine}.json"
  [[ -f "$config_file" ]] || { echo "No config file found at $config_file"; return 1; }
  echo "Starting ${engine}..."
  nohup "$bin_path" run -c "$config_file" > "${SBD_DIR}/data/${engine}.log" 2>&1 &
  echo "${engine} started (PID: $!)"
}

echo "--- Detecting network ---"
detect_ip
echo "--- Generating UUID ---"
generate_uuid
echo "--- Downloading engine ---"
download_engine
echo "--- Installing cloudflared ---"
install_cloudflared
echo "--- Starting Argo tunnel ---"
start_argo
echo "--- Generating config ---"
generate_config
echo "--- Starting engine ---"
start_engine || echo "Engine start deferred (config may be generated later)."
echo "=== Container bootstrap complete ==="
