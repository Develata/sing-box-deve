#!/bin/bash
# sing-box-deve container bootstrap script
# Runs inside Docker / Clawcloud / SAP CF containers
# All configuration is received via environment variables
set -euo pipefail

export LANG=en_US.UTF-8
export HOME="${HOME:-/root}"
SBD_DIR="${HOME}/sing-box-deve"
APP_DIR="${APP_DIR:-/app}"

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

prepare_script_tree() {
  local src="${APP_DIR}" dst="${SBD_DIR}/script"
  [[ -f "${src}/sing-box-deve.sh" ]] || {
    echo "Unable to locate sing-box-deve.sh in ${src}"
    return 1
  }
  mkdir -p "$dst"
  cp -f "${src}/sing-box-deve.sh" "$dst/"
  [[ -f "${src}/version" ]] && cp -f "${src}/version" "$dst/"
  [[ -f "${src}/checksums.txt" ]] && cp -f "${src}/checksums.txt" "$dst/"
  for dir in lib providers rulesets; do
    [[ -d "${src}/${dir}" ]] || continue
    rm -rf "${dst:?}/${dir}"
    cp -R "${src}/${dir}" "$dst/"
  done
  chmod +x "${dst}/sing-box-deve.sh"
}

verify_sha256() {
  local file="$1" expected="$2" actual
  [[ -n "$expected" ]] || return 1
  actual="$(sha256sum "$file" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]]
}

download_verified_binary() {
  local url="$1" sha_url="$2" out="$3" sha_file="/tmp/sbd-download.sha256" expected
  curl -fsSL "$url" -o "$out" 2>/dev/null || return 1
  curl -fsSL "$sha_url" -o "$sha_file" 2>/dev/null || {
    rm -f "$out" "$sha_file"
    return 1
  }
  expected="$(awk '{print $1}' "$sha_file" | head -n1)"
  if ! verify_sha256 "$out" "$expected"; then
    rm -f "$out" "$sha_file"
    echo "Checksum mismatch for $(basename "$out")"
    return 1
  fi
  rm -f "$sha_file"
}

verify_engine_binary_runs() {
  local engine="$1" bin_path="$2" version_out
  if ! version_out="$("$bin_path" version 2>&1)"; then
    echo "${engine} binary is not executable in this container:"
    printf '%s\n' "$version_out"
    return 1
  fi
  echo "${engine} installed: $(printf '%s\n' "$version_out" | head -1)"
}

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
    download_verified_binary "${base_url}/sing-box-${ARCH}" "${base_url}/sing-box-${ARCH}.sha256" "$bin_path" || {
      echo "Failed to download sing-box, trying official release..."
      local release_json tag ver filename url digest expected sb_arch
      release_json="$(curl -fsSL "https://api.github.com/repos/SagerNet/sing-box/releases/latest")"
      tag="$(printf '%s' "$release_json" | jq -r '.tag_name // empty')"
      [[ -n "$tag" && "$tag" != "null" ]] || tag="v1.11.0"
      ver="${tag#v}"
      sb_arch="$ARCH"
      [[ -f /etc/alpine-release ]] && sb_arch="${ARCH}-musl"
      filename="sing-box-${ver}-linux-${sb_arch}.tar.gz"
      url="$(printf '%s' "$release_json" | jq -r --arg name "$filename" '.assets[] | select(.name==$name) | .browser_download_url' | head -n1)"
      digest="$(printf '%s' "$release_json" | jq -r --arg name "$filename" '.assets[] | select(.name==$name) | .digest // empty' | head -n1)"
      expected="${digest#sha256:}"
      [[ -n "$url" && -n "$expected" && "$expected" != "$digest" ]] || { echo "Missing sing-box release URL or sha256 digest for ${filename}"; exit 1; }
      curl -fsSL "$url" -o /tmp/sb.tar.gz
      verify_sha256 /tmp/sb.tar.gz "$expected" || { echo "Checksum mismatch for ${filename}"; exit 1; }
      tar -xzf /tmp/sb.tar.gz -C /tmp/
      mv /tmp/sing-box-*/sing-box "$bin_path"
      rm -rf /tmp/sb.tar.gz /tmp/sing-box-*
    }
  elif [[ "$engine" == "xray" ]]; then
    download_verified_binary "${base_url}/xray-${ARCH}" "${base_url}/xray-${ARCH}.sha256" "$bin_path" || {
      echo "Failed to download xray, trying official release..."
      local tag x_arch filename expected
      tag=$(curl -fsSL "https://api.github.com/repos/XTLS/Xray-core/releases/latest" | jq -r '.tag_name // empty')
      [[ -n "$tag" && "$tag" != "null" ]] || tag="v25.1.1"
      x_arch="64"
      [[ "$ARCH" == "arm64" ]] && x_arch="arm64-v8a"
      filename="Xray-linux-${x_arch}.zip"
      curl -fsSL "https://github.com/XTLS/Xray-core/releases/download/${tag}/${filename}" -o /tmp/xray.zip
      curl -fsSL "https://github.com/XTLS/Xray-core/releases/download/${tag}/${filename}.dgst" -o /tmp/xray.zip.dgst
      expected="$(awk '/SHA256/{print $NF; exit}' /tmp/xray.zip.dgst)"
      verify_sha256 /tmp/xray.zip "$expected" || { echo "Checksum mismatch for ${filename}"; exit 1; }
      unzip -o /tmp/xray.zip xray -d "${SBD_DIR}/bin/"
      rm -f /tmp/xray.zip /tmp/xray.zip.dgst
    }
  fi
  chmod +x "$bin_path"
  verify_engine_binary_runs "$engine" "$bin_path"
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
  download_verified_binary \
    "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}" \
    "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.sha256" \
    "$cf_bin"
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
  local protocols_csv="${PROTOCOLS:-vless-reality,vmess-ws}"
  local profile="${PROFILE:-full}"
  local script_root="${SBD_DIR}/script"
  echo "Generating ${engine} config for protocols: ${protocols_csv}"
  prepare_script_tree

  export PROJECT_ROOT="$script_root"
  # shellcheck disable=SC1091
  source "${PROJECT_ROOT}/lib/common.sh"
  # shellcheck disable=SC1091
  source "${PROJECT_ROOT}/lib/legacy_compat.sh"
  # shellcheck disable=SC1091
  source "${PROJECT_ROOT}/lib/protocols.sh"
  # shellcheck disable=SC1091
  source "${PROJECT_ROOT}/lib/security.sh"
  # shellcheck disable=SC1091
  source "${PROJECT_ROOT}/lib/providers.sh"
  # shellcheck disable=SC1091
  source "${PROJECT_ROOT}/lib/output.sh"

  SBD_STATE_DIR="${SBD_DIR}/state"
  SBD_CONFIG_DIR="${SBD_DIR}/config"
  SBD_RUNTIME_DIR="${SBD_DIR}/run"
  SBD_RULES_FILE="${SBD_STATE_DIR}/firewall-rules.db"
  SBD_CONTEXT_FILE="${SBD_STATE_DIR}/context.env"
  SBD_FW_SNAPSHOT_FILE="${SBD_STATE_DIR}/firewall-rules.snapshot"
  SBD_CFG_LOCK_FILE="${SBD_STATE_DIR}/cfg.lock"
  CONFIG_SNAPSHOT_FILE="${SBD_CONFIG_DIR}/config.yaml"
  SBD_SETTINGS_FILE="${SBD_CONFIG_DIR}/settings.conf"
  SBD_INSTALL_DIR="${SBD_DIR}"
  SBD_BIN_DIR="${SBD_DIR}/bin"
  SBD_DATA_DIR="${SBD_DIR}/data"
  SBD_CACHE_DIR="${SBD_DIR}/cache"
  SBD_NODES_FILE="${SBD_DATA_DIR}/nodes.txt"
  SBD_NODES_BASE_FILE="${SBD_DATA_DIR}/nodes-base.txt"
  SBD_SUB_FILE="${SBD_DATA_DIR}/nodes-sub.txt"

  mkdir -p "$SBD_STATE_DIR" "$SBD_CONFIG_DIR" "$SBD_RUNTIME_DIR" "$SBD_BIN_DIR" "$SBD_DATA_DIR" "$SBD_CACHE_DIR"
  export UUID SBD_UUID="${UUID:-}"
  export TLS_MODE="${TLS_MODE:-self-signed}"
  export ARGO_MODE="${ARGO_MODE:-off}"
  export WARP_MODE="${WARP_MODE:-off}"
  export PSIPHON_ENABLE="${PSIPHON_ENABLE:-off}"
  export PSIPHON_MODE="${PSIPHON_MODE:-off}"
  export PSIPHON_REGION="${PSIPHON_REGION:-auto}"
  export ROUTE_MODE="${ROUTE_MODE:-direct}"
  export OUTBOUND_PROXY_MODE="${OUTBOUND_PROXY_MODE:-direct}"
  export IP_PREFERENCE="${IP_PREFERENCE:-auto}"

  validate_profile_protocols "$profile" "$protocols_csv"
  assert_engine_protocol_compatibility "$engine" "$protocols_csv"
  validate_feature_modes
  case "$engine" in
    sing-box) build_sing_box_config "$protocols_csv" ;;
    xray) build_xray_config "$protocols_csv" ;;
    *) echo "Unsupported engine: $engine"; return 1 ;;
  esac
  validate_generated_config "$engine" "true"
  write_nodes_output "$engine" "$protocols_csv"
}

start_engine() {
  local engine="${ENGINE:-sing-box}"
  local bin_path="${SBD_DIR}/bin/${engine}"
  local config_file run_args=()
  case "$engine" in
    sing-box)
      config_file="${SBD_DIR}/config/config.json"
      run_args=(run -c "$config_file")
      ;;
    xray)
      config_file="${SBD_DIR}/config/xray-config.json"
      run_args=(run -config "$config_file")
      ;;
    *) echo "Unsupported engine: $engine"; return 1 ;;
  esac
  [[ -f "$config_file" ]] || { echo "No config file found at $config_file"; return 1; }
  echo "Starting ${engine}..."
  nohup "$bin_path" "${run_args[@]}" > "${SBD_DIR}/data/${engine}.log" 2>&1 &
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
start_engine
echo "=== Container bootstrap complete ==="
