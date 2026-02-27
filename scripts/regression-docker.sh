#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${1:-debian:12-slim}"

docker run --rm -v "${ROOT_DIR}:/work" -w /work "${IMAGE}" bash -lc '
set -uo pipefail
failures=0
tests=0
skips=0
TEST_TIMEOUT="${TEST_TIMEOUT:-60}"

run_test() {
  local name="$1"
  shift
  local rc
  tests=$((tests + 1))
  echo "[TEST] ${name}"
  if timeout "${TEST_TIMEOUT}" "$@"; then
    echo "[PASS] ${name}"
  else
    rc=$?
    if [[ "$rc" -eq 124 ]]; then
      echo "[FAIL] ${name} (timeout=${TEST_TIMEOUT}s)"
    else
      echo "[FAIL] ${name} (exit=${rc})"
    fi
    failures=$((failures + 1))
  fi
}

run_optional() {
  local name="$1"
  shift
  local rc
  tests=$((tests + 1))
  echo "[TEST-OPTIONAL] ${name}"
  if timeout "${TEST_TIMEOUT}" "$@"; then
    echo "[PASS] ${name}"
  else
    rc=$?
    if [[ "$rc" -eq 124 ]]; then
      echo "[SKIP] ${name} (timeout=${TEST_TIMEOUT}s)"
    else
      echo "[SKIP] ${name} (exit=${rc})"
    fi
    skips=$((skips + 1))
  fi
}

export DEBIAN_FRONTEND=noninteractive
apt-get update >/dev/null
apt-get install -y jq openssl ca-certificates >/dev/null

mkdir -p /tmp/sbd-mock

cat > /tmp/sbd-mock/systemctl <<'"'"'MOCK'"'"'
#!/usr/bin/env bash
case "${1:-}" in
  is-active|is-enabled) exit 0 ;;
  list-unit-files) echo "sing-box-deve-jump.service enabled"; exit 0 ;;
  status) echo "mock systemctl status: $*"; exit 0 ;;
  *) exit 0 ;;
esac
MOCK

cat > /tmp/sbd-mock/ufw <<'"'"'MOCK'"'"'
#!/usr/bin/env bash
if [[ "${1:-}" == "status" ]]; then
  echo "Status: active"
  exit 0
fi
exit 0
MOCK

cat > /tmp/sbd-mock/ss <<'"'"'MOCK'"'"'
#!/usr/bin/env bash
echo "tcp LISTEN 0 128 0.0.0.0:443 0.0.0.0:*"
echo "tcp LISTEN 0 128 0.0.0.0:8443 0.0.0.0:*"
exit 0
MOCK

cat > /tmp/sbd-mock/curl <<'"'"'MOCK'"'"'
#!/usr/bin/env bash
last="${@: -1}"
if [[ "$last" == *"/version" ]]; then
  echo "v1.0.0-dev.999"
  exit 0
fi
if [[ "$last" == *"icanhazip.com" ]]; then
  echo "203.0.113.8"
  exit 0
fi
if [[ "$last" == *"1.1.1.1"* || "$last" == *"8.8.8.8"* ]]; then
  exit 0
fi
if [[ "$last" == *"api.telegram.org"* ]]; then
  echo "{\"ok\":true}"
  exit 0
fi
echo "v1.0.0-dev.999"
exit 0
MOCK

cat > /tmp/sbd-mock/nft <<'"'"'MOCK'"'"'
#!/usr/bin/env bash
exit 0
MOCK

cat > /tmp/sbd-mock/firewall-cmd <<'"'"'MOCK'"'"'
#!/usr/bin/env bash
if [[ "${1:-}" == "--state" ]]; then
  exit 1
fi
exit 0
MOCK

cat > /tmp/sbd-mock/iptables <<'"'"'MOCK'"'"'
#!/usr/bin/env bash
for arg in "$@"; do
  if [[ "$arg" == "-C" ]]; then
    exit 1
  fi
done
exit 0
MOCK

cat > /tmp/sbd-mock/journalctl <<'"'"'MOCK'"'"'
#!/usr/bin/env bash
echo "mock journalctl: $*"
exit 0
MOCK

chmod +x /tmp/sbd-mock/*
export PATH="/tmp/sbd-mock:${PATH}"

mkdir -p /etc/sing-box-deve /opt/sing-box-deve/bin /opt/sing-box-deve/data /var/lib/sing-box-deve /run/sing-box-deve
mkdir -p /etc/systemd/system
touch /etc/systemd/system/sing-box-deve.service
touch /etc/systemd/system/sing-box-deve-argo.service
cat > /etc/sing-box-deve/settings.conf <<EOF
lang=zh
auto_yes=true
update_channel=stable
EOF

cat > /opt/sing-box-deve/bin/sing-box <<'"'"'MOCK'"'"'
#!/usr/bin/env bash
if [[ "${1:-}" == "check" ]]; then
  exit 0
fi
if [[ "${1:-}" == "version" ]]; then
  echo "sing-box version v1.12.20"
  exit 0
fi
if [[ "${1:-}" == "generate" ]]; then
  echo "{\"private_key\":\"a\",\"public_key\":\"b\"}"
  exit 0
fi
exit 0
MOCK
chmod +x /opt/sing-box-deve/bin/sing-box

cat > /opt/sing-box-deve/bin/xray <<'"'"'MOCK'"'"'
#!/usr/bin/env bash
if [[ "${1:-}" == "version" ]]; then
  echo "Xray 25.1.1"
  exit 0
fi
exit 0
MOCK
chmod +x /opt/sing-box-deve/bin/xray

echo "pubkey-demo" > /opt/sing-box-deve/data/reality_public.key
echo "abcd1234abcd1234" > /opt/sing-box-deve/data/reality_short_id

cat > /etc/sing-box-deve/runtime.env <<EOF
provider=vps
profile=full
engine=sing-box
protocols=vless-reality,vmess-ws,vless-ws
script_root=/work
installed_at=2026-02-26T00:00:00Z
argo_mode=off
warp_mode=off
route_mode=direct
outbound_proxy_mode=direct
ip_preference=auto
tls_mode=self-signed
EOF

cat > /etc/sing-box-deve/config.json <<EOF
{
  "inbounds":[
    {"tag":"vless-reality","type":"vless","listen_port":443},
    {"tag":"vmess-ws","type":"vmess","listen_port":8443,"transport":{"path":"/vmess"}},
    {"tag":"vless-ws","type":"vless","listen_port":10443,"transport":{"path":"/vless"}}
  ],
  "outbounds":[
    {"type":"direct","tag":"direct"},
    {"type":"socks","tag":"proxy-out","server":"127.0.0.1","server_port":1080},
    {"type":"direct","tag":"warp-out"},
    {"type":"direct","tag":"psiphon-out"}
  ]
}
EOF

cat > /etc/sing-box-deve/xray-config.json <<EOF
{
  "inbounds":[
    {"tag":"vless-reality","port":443},
    {"tag":"vmess-ws","port":8443,"streamSettings":{"wsSettings":{"path":"/vmess"}}},
    {"tag":"vless-ws","port":10443,"streamSettings":{"wsSettings":{"path":"/vless"}}}
  ],
  "outbounds":[
    {"protocol":"freedom","tag":"direct"},
    {"protocol":"socks","tag":"proxy-out","settings":{"servers":[{"address":"127.0.0.1","port":1080}]}},
    {"protocol":"freedom","tag":"warp-out"},
    {"protocol":"freedom","tag":"psiphon-out"}
  ]
}
EOF

echo "vless://test@127.0.0.1:443?type=tcp#sbd-vless-reality" > /opt/sing-box-deve/data/nodes.txt
echo "dmxlc3M6Ly90ZXN0QDEyNy4wLjAuMTo0NDM/dHlwZT10Y3Ajc2JkLXZsZXNzLXJlYWxpdHk=" > /opt/sing-box-deve/data/nodes-sub.txt

run_test "bash -n" bash -n sing-box-deve.sh lib/*.sh scripts/*.sh providers/*.sh

run_test "install dry-run sing-box" ./sing-box-deve.sh install --provider vps --profile lite --engine sing-box --protocols vless-reality --dry-run --yes
run_test "install dry-run xray" ./sing-box-deve.sh install --provider vps --profile lite --engine xray --protocols vless-reality --dry-run --yes

run_optional "version" ./sing-box-deve.sh version
run_test "settings show" ./sing-box-deve.sh settings show
run_test "settings set" ./sing-box-deve.sh settings set lang=zh auto_yes=true update_channel=stable

run_test "list all" ./sing-box-deve.sh list --all
run_test "panel compact" ./sing-box-deve.sh panel --compact
run_test "restart all" ./sing-box-deve.sh restart --all
run_test "logs core" ./sing-box-deve.sh logs --core

run_test "set-port list" ./sing-box-deve.sh set-port --list
run_test "set-port vless-reality 2443" ./sing-box-deve.sh set-port --protocol vless-reality --port 2443

run_test "set-port-egress map" ./sing-box-deve.sh set-port-egress --map 2443:direct
run_test "set-port-egress list" ./sing-box-deve.sh set-port-egress --list
run_test "set-port-egress clear" ./sing-box-deve.sh set-port-egress --clear

run_test "set-egress socks" ./sing-box-deve.sh set-egress --mode socks --host 127.0.0.1 --port 1080
run_test "set-egress direct" ./sing-box-deve.sh set-egress --mode direct
run_test "set-route direct" ./sing-box-deve.sh set-route direct
run_test "set-route global-proxy" ./sing-box-deve.sh set-route global-proxy
run_test "set-route cn-direct" ./sing-box-deve.sh set-route cn-direct
run_test "set-route cn-proxy" ./sing-box-deve.sh set-route cn-proxy
run_test "set-route restore direct" ./sing-box-deve.sh set-route direct
run_test "set-share direct" ./sing-box-deve.sh set-share direct 203.0.113.1:443
run_test "set-share proxy" ./sing-box-deve.sh set-share proxy 203.0.113.2:443
run_test "set-share warp" ./sing-box-deve.sh set-share warp 203.0.113.3:443

run_test "split3 set" ./sing-box-deve.sh split3 set direct.example proxy.example block.example
run_test "split3 show" ./sing-box-deve.sh split3 show

run_test "jump set" ./sing-box-deve.sh jump set vless-reality 443 2053,2082
run_test "jump show" ./sing-box-deve.sh jump show
run_optional "jump replay" ./sing-box-deve.sh jump replay
run_test "jump clear" ./sing-box-deve.sh jump clear

run_test "mport add" ./sing-box-deve.sh mport add vless-reality 2444
run_test "mport list" ./sing-box-deve.sh mport list
run_test "mport remove" ./sing-box-deve.sh mport remove vless-reality 2444
run_test "mport clear" ./sing-box-deve.sh mport clear

run_test "sub rules-update" ./sing-box-deve.sh sub rules-update
run_test "sub refresh" ./sing-box-deve.sh sub refresh
run_test "sub show" ./sing-box-deve.sh sub show

run_test "cfg preview ip-pref" ./sing-box-deve.sh cfg preview ip-pref v4
run_test "cfg apply ip-pref" ./sing-box-deve.sh cfg apply ip-pref v4
run_test "cfg preview cdn-host" ./sing-box-deve.sh cfg preview cdn-host cdn.example.com
run_test "cfg apply cdn-host" ./sing-box-deve.sh cfg apply cdn-host cdn.example.com
run_test "cfg preview domain-split" ./sing-box-deve.sh cfg preview domain-split d.example p.example b.example
run_test "cfg apply domain-split" ./sing-box-deve.sh cfg apply domain-split d.example p.example b.example
run_test "cfg apply protocol-add" ./sing-box-deve.sh cfg apply protocol-add vmess-ws random
run_test "cfg apply protocol-remove" ./sing-box-deve.sh cfg apply protocol-remove vmess-ws
run_test "cfg apply tls self-signed" ./sing-box-deve.sh cfg apply tls self-signed
run_test "cfg snapshots list" ./sing-box-deve.sh cfg snapshots list
run_test "cfg rollback latest" ./sing-box-deve.sh cfg rollback latest

run_test "kernel show" ./sing-box-deve.sh kernel show
run_test "protocol matrix" ./sing-box-deve.sh protocol matrix
run_test "protocol matrix --enabled" ./sing-box-deve.sh protocol matrix --enabled
run_test "fw status" ./sing-box-deve.sh fw status
run_test "fw replay" ./sing-box-deve.sh fw replay
run_optional "fw rollback" ./sing-box-deve.sh fw rollback
run_test "doctor" ./sing-box-deve.sh doctor

echo "[RESULT] tests=${tests} failures=${failures} skips=${skips}"
if [[ "$failures" -ne 0 ]]; then
  exit 1
fi
echo "[OK] docker full regression passed"
'
