#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${1:-sha256:7e5bc0e499a8d50cb1e32287944a90b9ec8fd7d500673e75daff3f52882f5798}"

docker run --rm -v "${ROOT_DIR}:/work" -w /work "${IMAGE}" bash -lc '
set -euo pipefail

mkdir -p /tmp/sbd-mock

cat > /tmp/sbd-mock/systemctl <<'"'"'MOCK'"'"'
#!/usr/bin/env bash
case "${1:-}" in
  is-active|is-enabled) exit 0 ;;
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
if [[ "$last" == *"1.1.1.1" ]]; then
  exit 0
fi
echo "mock curl: unsupported $*" >&2
exit 1
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
exit 0
MOCK

chmod +x /tmp/sbd-mock/*
export PATH="/tmp/sbd-mock:${PATH}"

mkdir -p /etc/sing-box-deve /opt/sing-box-deve/bin /opt/sing-box-deve/data /var/lib/sing-box-deve /run/sing-box-deve
cat > /etc/sing-box-deve/settings.conf <<EOF
lang=zh;auto_yes=true;update_channel=stable
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

cat > /etc/sing-box-deve/runtime.env <<EOF
provider=vps
profile=full
engine=sing-box
protocols=vless-reality
argo_mode=off
warp_mode=off
route_mode=direct
outbound_proxy_mode=direct
ip_preference=auto
tls_mode=self-signed
EOF

cat > /etc/sing-box-deve/config.json <<EOF
{"inbounds":[{"tag":"vless-reality","type":"vless","listen_port":443}]}
EOF

echo "vless://test@127.0.0.1:443?type=tcp#sbd-vless-reality" > /opt/sing-box-deve/data/nodes.txt

echo "[TEST] bash -n"
bash -n sing-box-deve.sh lib/*.sh scripts/*.sh providers/*.sh

echo "[TEST] install --dry-run"
./sing-box-deve.sh install --provider vps --profile lite --engine sing-box --protocols vless-reality --dry-run --yes

echo "[TEST] cfg apply ip-pref"
./sing-box-deve.sh cfg apply ip-pref v4

echo "[TEST] cfg protocol-add / remove"
./sing-box-deve.sh cfg protocol-add vmess-ws random
./sing-box-deve.sh cfg protocol-remove vmess-ws

echo "[TEST] cfg snapshots + rollback"
./sing-box-deve.sh cfg snapshots list
./sing-box-deve.sh cfg rollback latest

echo "[TEST] doctor"
./sing-box-deve.sh doctor

echo "[OK] docker regression smoke passed"
'
