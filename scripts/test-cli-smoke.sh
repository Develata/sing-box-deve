#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/sing-box-deve.sh"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

assert_success() {
  local name="$1"
  shift
  if ! "$@" >"${TMP_DIR}/${name}.out" 2>"${TMP_DIR}/${name}.err"; then
    echo "[FAIL] expected success: ${name}" >&2
    cat "${TMP_DIR}/${name}.out" >&2 || true
    cat "${TMP_DIR}/${name}.err" >&2 || true
    exit 1
  fi
}

assert_failure() {
  local name="$1"
  shift
  if "$@" >"${TMP_DIR}/${name}.out" 2>"${TMP_DIR}/${name}.err"; then
    echo "[FAIL] expected failure: ${name}" >&2
    cat "${TMP_DIR}/${name}.out" >&2 || true
    cat "${TMP_DIR}/${name}.err" >&2 || true
    exit 1
  fi
}

export HOME="${TMP_DIR}/home"
mkdir -p "$HOME"

remote_root="${TMP_DIR}/remote"
mkdir -p "$remote_root"
printf '%s\n' 'v9.9.9' > "${remote_root}/version"

assert_success help "$SCRIPT" help

assert_success version env SBD_UPDATE_BASE_URL="file://${remote_root}" "$SCRIPT" version
grep -q "Current script version" "${TMP_DIR}/version.out" || fail "version output missing local version"
grep -q "Remote latest version" "${TMP_DIR}/version.out" || fail "version output missing remote version"

assert_success dry-run env HOME="$HOME" "$SCRIPT" install --dry-run \
  --provider vps \
  --profile lite \
  --engine sing-box \
  --protocols vless-reality \
  --uuid 11111111-1111-4111-8111-111111111111 \
  --yes
[[ ! -e "${HOME}/sing-box-deve" ]] || fail "dry-run created persistent state under HOME"

assert_failure unknown-command "$SCRIPT" __definitely_unknown_command__

assert_failure integration-smoke-missing-value "${ROOT_DIR}/scripts/integration-smoke.sh" --script
grep -q "requires a value" "${TMP_DIR}/integration-smoke-missing-value.err" || fail "integration-smoke missing-value error is not explicit"

assert_failure install-option-next-token env HOME="$HOME" "$SCRIPT" install --dry-run --tls-sni --yes
grep -q "Option --tls-sni requires a value" "${TMP_DIR}/install-option-next-token.err" || fail "install next-option-as-value error is not explicit"

assert_failure update-option-next-token env HOME="$HOME" "$SCRIPT" update --source --yes
grep -q "Option --source requires a value" "${TMP_DIR}/update-option-next-token.err" || fail "update next-option-as-value error is not explicit"

assert_failure set-route-extra-arg env HOME="$HOME" "$SCRIPT" set-route direct extra
grep -q "Usage: set-route" "${TMP_DIR}/set-route-extra-arg.err" || fail "set-route extra-arg error is not explicit"

release_unit="${TMP_DIR}/release-unit"
mkdir -p "$release_unit"
printf 'xray-archive' > "${release_unit}/Xray-linux-64.zip"
sha256="$(sha256sum "${release_unit}/Xray-linux-64.zip" | awk '{print $1}')"
printf 'MD5= ignored\nSHA2-256= %s\n' "$sha256" > "${release_unit}/Xray-linux-64.zip.dgst"
env PROJECT_ROOT="$ROOT_DIR" RELEASE_UNIT="$release_unit" bash <<'BASH'
set -euo pipefail
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/providers_release.sh"
verify_sha256_from_xray_dgst "$RELEASE_UNIT/Xray-linux-64.zip" "$RELEASE_UNIT/Xray-linux-64.zip.dgst"
BASH

assert_failure dry-run-domain-self-signed env HOME="$HOME" "$SCRIPT" install --dry-run \
  --preset reality-plus-domain \
  --tls-sni example.com \
  --yes
grep -q "not self-signed" "${TMP_DIR}/dry-run-domain-self-signed.err" || fail "domain self-signed dry-run error is not explicit"

assert_success dry-run-domain env HOME="$HOME" "$SCRIPT" install --dry-run \
  --preset reality-plus-domain \
  --tls-sni example.com \
  --tls-mode acme-auto \
  --acme-email admin@example.com \
  --web-front openresty \
  --hy2-obfs salamander \
  --hy2-obfs-password strongpass \
  --yes

assert_failure dry-run-hy2-gecko env HOME="$HOME" "$SCRIPT" install --dry-run \
  --preset reality-plus-domain \
  --tls-sni example.com \
  --tls-mode acme-auto \
  --acme-email admin@example.com \
  --hy2-obfs gecko \
  --yes
grep -q "HY2_OBFS_MODE=gecko" "${TMP_DIR}/dry-run-hy2-gecko.err" || fail "gecko error is not explicit"

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

echo "[OK] CLI smoke checks passed"
