#!/usr/bin/env bash
set -euo pipefail

runtime_file="/etc/sing-box-deve/runtime.env"
nodes_file="/opt/sing-box-deve/data/nodes.txt"
config_dir="/etc/sing-box-deve"

log() { printf '[CHECK] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*"; failures=$((failures + 1)); }

trim_ws() {
  local v="$1"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  printf '%s' "$v"
}

strip_inline_comment() {
  local value="$1" out="" ch prev=""
  local in_single="false" in_double="false" i
  for ((i = 0; i < ${#value}; i++)); do
    ch="${value:i:1}"
    if [[ "$ch" == "'" && "$in_double" == "false" ]]; then
      [[ "$in_single" == "true" ]] && in_single="false" || in_single="true"
      out+="$ch"
      prev="$ch"
      continue
    fi
    if [[ "$ch" == "\"" && "$in_single" == "false" ]]; then
      [[ "$in_double" == "true" ]] && in_double="false" || in_double="true"
      out+="$ch"
      prev="$ch"
      continue
    fi
    if [[ "$ch" == "#" && "$in_single" == "false" && "$in_double" == "false" ]]; then
      if [[ -n "$prev" && "$prev" =~ [[:space:]] ]]; then
        break
      fi
    fi
    out+="$ch"
    prev="$ch"
  done
  printf '%s' "$out"
}

unquote_env_value() {
  local value="$1"
  if [[ "$value" == \"*\" && "$value" == *\" && "${#value}" -ge 2 ]]; then
    value="${value:1:${#value}-2}"
  elif [[ "$value" == \'*\' && "$value" == *\' && "${#value}" -ge 2 ]]; then
    value="${value:1:${#value}-2}"
  fi
  printf '%s' "$value"
}

safe_load_env() {
  local file="$1" raw line key value
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    line="${raw%$'\r'}"
    [[ -n "${line//[[:space:]]/}" ]] || continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    line="${line#"${line%%[![:space:]]*}"}"
    [[ "$line" == *=* ]] || {
      echo "[ERROR] invalid env line in ${file}: ${line}" >&2
      exit 1
    }
    key="${line%%=*}"
    value="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || {
      echo "[ERROR] invalid env key in ${file}: ${key}" >&2
      exit 1
    }
    value="$(strip_inline_comment "$value")"
    value="$(trim_ws "$value")"
    value="$(unquote_env_value "$value")"
    printf -v "$key" '%s' "$value"
  done < "$file"
}

[[ -f "$runtime_file" ]] || { echo "[ERROR] runtime not found: ${runtime_file}"; exit 1; }
[[ -f "$nodes_file" ]] || { echo "[ERROR] nodes not found: ${nodes_file}"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "[ERROR] jq is required"; exit 1; }

safe_load_env "$runtime_file"
engine="${engine:-sing-box}"
config_file="${config_dir}/config.json"
[[ "$engine" == "xray" ]] && config_file="${config_dir}/xray-config.json"
[[ -f "$config_file" ]] || { echo "[ERROR] config not found: ${config_file}"; exit 1; }

failures=0

config_port_by_tag() {
  local tag="$1"
  if [[ "$engine" == "sing-box" ]]; then
    jq -r --arg t "$tag" '.inbounds[] | select(.tag==$t) | (.listen_port // .port // empty)' "$config_file" | head -n1
  else
    jq -r --arg t "$tag" '.inbounds[] | select(.tag==$t) | (.port // empty)' "$config_file" | head -n1
  fi
}

node_line() {
  local marker="$1"
  grep -F "$marker" "$nodes_file" | head -n1 || true
}

extract_uri_port() {
  local line="$1"
  if [[ "$line" =~ @(\[[^]]+\]|[^:/?#]+):([0-9]+)\? ]]; then
    echo "${BASH_REMATCH[2]}"
  fi
}

extract_query_param() {
  local line="$1" key="$2" q
  q="${line#*\?}"; q="${q%%#*}"
  printf '%s\n' "$q" | tr '&' '\n' | awk -F= -v k="$key" '$1==k{print $2; exit}'
}

log "engine=${engine} config=${config_file}"

check_port_match() {
  local tag="$1" marker="$2" line cfg_port node_port
  line="$(node_line "$marker")"
  [[ -n "$line" ]] || return 0
  cfg_port="$(config_port_by_tag "$tag")"
  node_port="$(extract_uri_port "$line")"
  if [[ -n "$cfg_port" && -n "$node_port" && "$cfg_port" != "$node_port" ]]; then
    fail "port mismatch for ${tag}: config=${cfg_port} node=${node_port}"
  else
    log "port ok for ${tag}: ${cfg_port:-n/a}"
  fi
}

check_port_match "vless-reality" "#sbd-vless-reality"
check_port_match "vless-ws" "#sbd-vless-ws"
check_port_match "vless-xhttp" "#sbd-vless-xhttp"
check_port_match "trojan" "#sbd-trojan"

vm_line="$(node_line "sbd-vmess-ws")"
if [[ -n "$vm_line" ]]; then
  vm_payload="${vm_line#vmess://}"
  vm_json="$(printf '%s' "$vm_payload" | base64 -d 2>/dev/null || true)"
  if [[ -n "$vm_json" ]]; then
    cfg_port="$(config_port_by_tag "vmess-ws")"
    node_port="$(printf '%s' "$vm_json" | jq -r '.port // empty')"
    cfg_path="$(if [[ "$engine" == "sing-box" ]]; then jq -r '.inbounds[]|select(.tag=="vmess-ws")|(.transport.path // empty)' "$config_file" | head -n1; else jq -r '.inbounds[]|select(.tag=="vmess-ws")|(.streamSettings.wsSettings.path // empty)' "$config_file" | head -n1; fi)"
    node_path="$(printf '%s' "$vm_json" | jq -r '.path // empty')"
    [[ "$cfg_port" == "$node_port" ]] || fail "port mismatch for vmess-ws: config=${cfg_port} node=${node_port}"
    [[ "$cfg_path" == "$node_path" ]] || fail "path mismatch for vmess-ws: config=${cfg_path} node=${node_path}"
    log "vmess-ws ok"
  fi
fi

vl_line="$(node_line "#sbd-vless-ws")"
if [[ -n "$vl_line" ]]; then
  cfg_path="$(if [[ "$engine" == "sing-box" ]]; then jq -r '.inbounds[]|select(.tag=="vless-ws")|(.transport.path // empty)' "$config_file" | head -n1; else jq -r '.inbounds[]|select(.tag=="vless-ws")|(.streamSettings.wsSettings.path // empty)' "$config_file" | head -n1; fi)"
  node_path="$(extract_query_param "$vl_line" "path")"
  expected="$(jq -nr --arg v "$cfg_path" '$v|@uri')"
  [[ "$expected" == "$node_path" ]] || fail "path mismatch for vless-ws: config=${cfg_path} node=${node_path}"
  log "vless-ws path ok"
fi

if (( failures > 0 )); then
  echo "[RESULT] FAIL (${failures} mismatch)"
  exit 1
fi

echo "[RESULT] PASS"
