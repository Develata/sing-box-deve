#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

web_unit="${TMP_DIR}/web-front-unit"
mkdir -p "${web_unit}/bin" "${web_unit}/home"
cat > "${web_unit}/bin/systemctl" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  list-unit-files)
    if [[ " ${*} " == *" existing.service "* ]]; then
      printf 'existing.service enabled\n'
    fi
    exit 0
    ;;
  *) exit 0 ;;
esac
SH
chmod +x "${web_unit}/bin/systemctl"

env PROJECT_ROOT="$ROOT_DIR" PATH="${web_unit}/bin:${PATH}" bash <<'BASH'
set -euo pipefail
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/protocols.sh"
source "$PROJECT_ROOT/lib/security.sh"
source "$PROJECT_ROOT/lib/providers.sh"
sbd_systemd_unit_exists existing
! sbd_systemd_unit_exists missing
BASH

cat > "${web_unit}/bin/openresty" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  -V) echo 'nginx version: openresty/1.27.1 --conf-path=/opt/openresty/nginx/conf/nginx.conf' >&2 ;;
  -t) exit 0 ;;
  *) exit 0 ;;
esac
SH
cat > "${web_unit}/bin/nginx" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  -V) echo 'nginx version: nginx/1.28.0 --conf-path=/etc/nginx/nginx.conf' >&2 ;;
  -t) exit 0 ;;
  *) exit 0 ;;
esac
SH
chmod +x "${web_unit}/bin/openresty" "${web_unit}/bin/nginx"
touch "${web_unit}/cert.pem" "${web_unit}/key.pem"

env PROJECT_ROOT="$ROOT_DIR" HOME="${web_unit}/home" PATH="${web_unit}/bin:${PATH}" \
  WEB_FRONT_MODE=auto TLS_SERVER_NAME=front.example.com \
  ACME_CERT_PATH="${web_unit}/cert.pem" ACME_KEY_PATH="${web_unit}/key.pem" bash <<'BASH'
set -euo pipefail
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/protocols.sh"
source "$PROJECT_ROOT/lib/security.sh"
source "$PROJECT_ROOT/lib/providers.sh"
detect_privilege_level
init_runtime_layout
sbd_write_archive_gateway_site >/dev/null
sbd_configure_web_front hysteria2 >/dev/null
grep -q '^WEB_FRONT_ENGINE=openresty$' "$SBD_DATA_DIR/web_front.env"
grep -q 'server_name front.example.com;' "$SBD_CONFIG_DIR/web-front/openresty/conf.d/sing-box-deve-archive.conf"
BASH

rm -f "${web_unit}/bin/openresty"
env PROJECT_ROOT="$ROOT_DIR" HOME="${web_unit}/home2" PATH="${web_unit}/bin:${PATH}" \
  WEB_FRONT_MODE=auto TLS_SERVER_NAME=front.example.com \
  ACME_CERT_PATH="${web_unit}/cert.pem" ACME_KEY_PATH="${web_unit}/key.pem" bash <<'BASH'
set -euo pipefail
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/protocols.sh"
source "$PROJECT_ROOT/lib/security.sh"
source "$PROJECT_ROOT/lib/providers.sh"
detect_privilege_level
init_runtime_layout
sbd_write_archive_gateway_site >/dev/null
sbd_configure_web_front hysteria2 >/dev/null
grep -q '^WEB_FRONT_ENGINE=nginx$' "$SBD_DATA_DIR/web_front.env"
grep -q 'root ' "$SBD_CONFIG_DIR/web-front/nginx/conf.d/sing-box-deve-archive.conf"
BASH

env PROJECT_ROOT="$ROOT_DIR" HOME="${web_unit}/home2b" PATH="${web_unit}/bin:${PATH}" \
  WEB_FRONT_MODE=nginx TLS_SERVER_NAME=front.example.com \
  ACME_CERT_PATH="${web_unit}/cert.pem" ACME_KEY_PATH="${web_unit}/key.pem" bash <<'BASH'
set -euo pipefail
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/protocols.sh"
source "$PROJECT_ROOT/lib/security.sh"
source "$PROJECT_ROOT/lib/providers.sh"
detect_privilege_level
init_runtime_layout
sbd_write_archive_gateway_site >/dev/null
sbd_configure_web_front hysteria2 >/dev/null
grep -q '^WEB_FRONT_ENGINE=nginx$' "$SBD_DATA_DIR/web_front.env"
BASH

if env PROJECT_ROOT="$ROOT_DIR" HOME="${web_unit}/home3" PATH="${web_unit}/bin:${PATH}" \
  WEB_FRONT_MODE=auto TLS_SERVER_NAME=front.example.com \
  ACME_CERT_PATH="${web_unit}/cert.pem" ACME_KEY_PATH="${web_unit}/key.pem" bash <<'BASH' >"${TMP_DIR}/web-front-443-conflict.out" 2>"${TMP_DIR}/web-front-443-conflict.err"
set -euo pipefail
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/protocols.sh"
source "$PROJECT_ROOT/lib/security.sh"
source "$PROJECT_ROOT/lib/providers.sh"
detect_privilege_level
init_runtime_layout
sbd_write_archive_gateway_site >/dev/null
sbd_configure_web_front vless-reality,hysteria2 >/dev/null
BASH
then
  fail "web front accepted vless-reality default TCP 443 conflict"
fi
grep -q "move selected TCP protocol" "${TMP_DIR}/web-front-443-conflict.err" || fail "web front 443 conflict error is not explicit"

env PROJECT_ROOT="$ROOT_DIR" HOME="${web_unit}/home3b" PATH="${web_unit}/bin:${PATH}" \
  ENGINE=sing-box WEB_FRONT_MODE=off SBD_PORT_VLESS_REALITY=8443 bash <<'BASH'
set -euo pipefail
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/protocols.sh"
source "$PROJECT_ROOT/lib/security.sh"
source "$PROJECT_ROOT/lib/providers.sh"
detect_privilege_level
init_runtime_layout
sbd_web_front_assert_tcp443_available vless-reality,hysteria2
BASH

if env PROJECT_ROOT="$ROOT_DIR" HOME="${web_unit}/home3c" PATH="${web_unit}/bin:${PATH}" \
  ENGINE=sing-box WEB_FRONT_MODE=off SBD_PORT_NAIVE=443 bash <<'BASH' >"${TMP_DIR}/web-front-naive-443.out" 2>"${TMP_DIR}/web-front-naive-443.err"
set -euo pipefail
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/protocols.sh"
source "$PROJECT_ROOT/lib/security.sh"
source "$PROJECT_ROOT/lib/providers.sh"
detect_privilege_level
init_runtime_layout
sbd_web_front_assert_tcp443_available naive,hysteria2
BASH
then
  fail "web front accepted manually mapped naive TCP 443 conflict"
fi
grep -q "move selected TCP protocol" "${TMP_DIR}/web-front-naive-443.err" || fail "manual naive 443 conflict error is not explicit"

if env PROJECT_ROOT="$ROOT_DIR" HOME="${web_unit}/home3d" PATH="${web_unit}/bin:${PATH}" \
  WEB_FRONT_MODE=nginx TLS_SERVER_NAME=front.example.com \
  ACME_CERT_PATH=relative.pem ACME_KEY_PATH="${web_unit}/key.pem" bash <<'BASH' >"${TMP_DIR}/web-front-relative-cert.out" 2>"${TMP_DIR}/web-front-relative-cert.err"
set -euo pipefail
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/protocols.sh"
source "$PROJECT_ROOT/lib/security.sh"
source "$PROJECT_ROOT/lib/providers.sh"
detect_privilege_level
init_runtime_layout
sbd_write_archive_gateway_site >/dev/null
sbd_configure_web_front hysteria2 >/dev/null
BASH
then
  fail "web front accepted relative certificate path"
fi
grep -q "path must be absolute" "${TMP_DIR}/web-front-relative-cert.err" || fail "relative certificate path error is not explicit"

if env PROJECT_ROOT="$ROOT_DIR" HOME="${web_unit}/home4" PATH="${web_unit}/bin:${PATH}" \
  WEB_FRONT_MODE=auto TLS_SERVER_NAME='good.example;include/tmp/pwn' \
  ACME_CERT_PATH="${web_unit}/cert.pem" ACME_KEY_PATH="${web_unit}/key.pem" bash <<'BASH' >"${TMP_DIR}/web-front-server-name.out" 2>"${TMP_DIR}/web-front-server-name.err"
set -euo pipefail
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/protocols.sh"
source "$PROJECT_ROOT/lib/security.sh"
source "$PROJECT_ROOT/lib/providers.sh"
detect_privilege_level
init_runtime_layout
sbd_write_archive_gateway_site >/dev/null
sbd_configure_web_front hysteria2 >/dev/null
BASH
then
  fail "web front accepted unsafe nginx server_name"
fi
grep -q "nginx server_name contains unsupported characters" "${TMP_DIR}/web-front-server-name.err" || fail "unsafe server_name error is not explicit"

env PROJECT_ROOT="$ROOT_DIR" HOME="${web_unit}/home5" HY2_OBFS_MODE=salamander bash <<'BASH'
set -euo pipefail
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/protocols.sh"
source "$PROJECT_ROOT/lib/security.sh"
source "$PROJECT_ROOT/lib/providers.sh"
detect_privilege_level
init_runtime_layout
pw1="$(sbd_hy2_obfs_password)"
pw2="$(sbd_hy2_obfs_password)"
[[ "$pw1" == "$pw2" && ${#pw1} -ge 8 ]] || { echo "invalid persisted hy2 obfs password" >&2; exit 1; }
fragment="$(singbox_fragment_hysteria2 11111111-1111-4111-8111-111111111111 8443 h.example /abs/cert.pem /abs/key.pem /abs/site salamander "$pw1")"
FRAGMENT_JSON="[$fragment]" python3 - "$pw1" <<'PY'
import json, os, sys
expected = sys.argv[1]
data = json.loads(os.environ["FRAGMENT_JSON"])
assert data[0]["obfs"]["type"] == "salamander"
assert data[0]["obfs"]["password"] == expected
assert data[0]["masquerade"] == "file:///abs/site"
PY
BASH

include_unit="${TMP_DIR}/openresty-include-unit"
mkdir -p "$include_unit"
cat > "${include_unit}/nginx.conf" <<'EOF'
events {}
http {
    server_tokens off;
}
stream {
}
EOF
env PROJECT_ROOT="$ROOT_DIR" SBD_OPENRESTY_CONF_ROOT="$include_unit" bash <<'BASH'
set -euo pipefail
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/protocols.sh"
source "$PROJECT_ROOT/lib/security.sh"
source "$PROJECT_ROOT/lib/providers.sh"
SBD_USER_MODE=false
sbd_ensure_openresty_confd_include "$SBD_OPENRESTY_CONF_ROOT"
python3 - "$SBD_OPENRESTY_CONF_ROOT/nginx.conf" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
http_start = text.index('http {')
stream_start = text.index('stream {')
include_pos = text.index('include conf.d/*.conf;')
assert http_start < include_pos < stream_start
PY
BASH

include_stream_unit="${TMP_DIR}/openresty-include-stream-unit"
mkdir -p "$include_stream_unit"
cat > "${include_stream_unit}/nginx.conf" <<'EOF'
events {}
http {
    server_tokens off;
}
stream {
    include conf.d/*.conf;
}
EOF
env PROJECT_ROOT="$ROOT_DIR" SBD_OPENRESTY_CONF_ROOT="$include_stream_unit" bash <<'BASH'
set -euo pipefail
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/protocols.sh"
source "$PROJECT_ROOT/lib/security.sh"
source "$PROJECT_ROOT/lib/providers.sh"
SBD_USER_MODE=false
sbd_ensure_openresty_confd_include "$SBD_OPENRESTY_CONF_ROOT"
python3 - "$SBD_OPENRESTY_CONF_ROOT/nginx.conf" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
http_start = text.index('http {')
stream_start = text.index('stream {')
include_positions = [i for i in range(len(text)) if text.startswith('include conf.d/*.conf;', i)]
assert any(http_start < pos < stream_start for pos in include_positions)
PY
BASH

echo "[OK] web front smoke checks passed"
