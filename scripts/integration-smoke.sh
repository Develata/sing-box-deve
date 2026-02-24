#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
main_script="${root_dir}/sing-box-deve.sh"
engine="sing-box"
with_argo_temp="false"

usage() {
  cat <<'EOF'
Usage:
  sudo bash scripts/integration-smoke.sh [--script PATH] [--engine sing-box|xray] [--with-argo-temp]

Description:
  Run real integration smoke checks on host:
  install -> apply --runtime -> set-egress -> set-route -> jump -> cfg argo.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --script) main_script="$2"; shift 2 ;;
    --engine) engine="$2"; shift 2 ;;
    --with-argo-temp) with_argo_temp="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

[[ "${EUID}" -eq 0 ]] || { echo "[ERROR] must run as root"; exit 1; }
command -v systemctl >/dev/null 2>&1 || { echo "[ERROR] systemctl not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "[ERROR] jq not found"; exit 1; }
[[ -x "$main_script" ]] || { echo "[ERROR] main script not executable: $main_script"; exit 1; }

case "$engine" in
  sing-box|xray) ;;
  *) echo "[ERROR] invalid engine: $engine"; exit 1 ;;
esac

run_step() {
  local name="$1"
  shift
  echo
  echo "[STEP] ${name}"
  "$@"
}

resolve_protocol_port() {
  local tag="$1" cfg query port=""
  if [[ "$engine" == "sing-box" ]]; then
    cfg="/etc/sing-box-deve/config.json"
    query=".inbounds[] | select(.tag==\$t) | (.listen_port // .port // empty)"
  else
    cfg="/etc/sing-box-deve/xray-config.json"
    query=".inbounds[] | select(.tag==\$t) | (.port // empty)"
  fi
  [[ -f "$cfg" ]] || return 1
  port="$(jq -r --arg t "$tag" "$query" "$cfg" | head -n1)"
  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$port"
}

protocols="vless-reality,vmess-ws,vless-ws"
if [[ "$engine" == "xray" ]]; then
  protocols="vless-reality,vmess-ws,vless-ws,vless-xhttp"
fi

run_step "install baseline (${engine})" \
  "$main_script" install --provider vps --profile lite --engine "$engine" --protocols "$protocols" --yes

run_step "apply runtime" "$main_script" apply --runtime

run_step "set egress socks(127.0.0.1:1080)" \
  "$main_script" set-egress --mode socks --host 127.0.0.1 --port 1080

run_step "set route global-proxy" "$main_script" set-route global-proxy
run_step "set route direct" "$main_script" set-route direct

if command -v iptables >/dev/null 2>&1; then
  main_port="$(resolve_protocol_port "vless-reality" || true)"
  if [[ -n "$main_port" ]]; then
    run_step "jump set vless-reality ${main_port} <- 8443,2053" \
      "$main_script" jump set vless-reality "$main_port" 8443,2053
    run_step "jump clear" "$main_script" jump clear
  else
    echo
    echo "[WARN] unable to resolve vless-reality port from runtime config, skip jump tests"
  fi
else
  echo
  echo "[WARN] iptables not found, skip jump tests"
fi

if [[ "$with_argo_temp" == "true" ]]; then
  run_step "cfg argo temp" "$main_script" cfg argo temp
fi
run_step "cfg argo off" "$main_script" cfg argo off

run_step "panel compact" "$main_script" panel --compact
if [[ -x "${root_dir}/scripts/consistency-check.sh" ]]; then
  run_step "consistency check" "${root_dir}/scripts/consistency-check.sh"
fi

echo
echo "[OK] integration smoke finished"
