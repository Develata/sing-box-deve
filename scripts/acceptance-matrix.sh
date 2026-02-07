#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/sing-box-deve.sh"

providers=(vps serv00 sap docker)
profiles=(lite full)

echo "# Acceptance Matrix"
echo
echo "| Provider | Profile | Argo | WARP | Outbound Proxy | Result | Notes |"
echo "|---|---|---|---|---|---|---|"

for provider in "${providers[@]}"; do
  for profile in "${profiles[@]}"; do
    argo="off"
    warp="off"
    outbound="direct"
    notes=""

    if [[ "$profile" == "full" ]]; then
      argo="temp"
      outbound="socks"
      notes="full preset"
    fi

    if [[ "$provider" == "vps" ]]; then
      if [[ "$profile" == "full" ]]; then
        warp="global"
        outbound="direct"
        notes="full preset (warp-priority)"
      fi
    fi

    result="manual"
    if [[ "${EUID}" -eq 0 ]]; then
      result="pending-real-run"
    fi

    echo "| ${provider} | ${profile} | ${argo} | ${warp} | ${outbound} | ${result} | ${notes} |"
  done
done

echo
echo "## Suggested Real Commands (run on target host)"
echo
echo "1) VPS lite baseline"
echo "   sudo ${SCRIPT} install --provider vps --profile lite --engine sing-box --protocols vless-reality --yes"
echo "2) VPS full + argo"
echo "   sudo ${SCRIPT} install --provider vps --profile full --engine xray --protocols vless-reality,vmess-ws,argo --argo temp --yes"
echo "3) VPS outbound socks"
echo "   sudo ${SCRIPT} install --provider vps --profile lite --engine sing-box --protocols vless-reality --outbound-proxy-mode socks --outbound-proxy-host 1.2.3.4 --outbound-proxy-port 1080 --yes"
echo "4) Serv00/SAP/Docker require credentials and should be executed with corresponding env templates from examples/."
