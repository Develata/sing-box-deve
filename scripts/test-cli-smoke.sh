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

uninstall_home="${TMP_DIR}/uninstall-home"
mkdir -p "$uninstall_home"
assert_success uninstall-no-firewall env HOME="$uninstall_home" SBD_FW_BACKEND=none "$SCRIPT" uninstall --keep-settings
grep -q "No firewall backend detected" "${TMP_DIR}/uninstall-no-firewall.out" || fail "uninstall no-firewall warning missing"

serv00_home="${TMP_DIR}/serv00-home"
mkdir -p "$serv00_home"
assert_success serv00-local-bundle env HOME="$serv00_home" "$SCRIPT" install --provider serv00 --yes
grep -q "generated local bundle only" "${TMP_DIR}/serv00-local-bundle.out" || fail "serv00 local bundle warning missing"
[[ -f "${serv00_home}/sing-box-deve/config/serv00.env" ]] || fail "serv00 local bundle missing serv00.env"

serv00_cred_home="${TMP_DIR}/serv00-cred-home"
mkdir -p "$serv00_cred_home"
assert_failure serv00-credentials-no-sshpass env HOME="$serv00_cred_home" SERV00_HOST=h SERV00_USER=u SERV00_PASS=p "$SCRIPT" install --provider serv00 --yes
grep -q "sshpass is required" "${TMP_DIR}/serv00-credentials-no-sshpass.err" || fail "serv00 sshpass error missing"

assert_failure integration-smoke-missing-value "${ROOT_DIR}/scripts/integration-smoke.sh" --script
grep -q "requires a value" "${TMP_DIR}/integration-smoke-missing-value.err" || fail "integration-smoke missing-value error is not explicit"

assert_failure install-option-next-token env HOME="$HOME" "$SCRIPT" install --dry-run --tls-sni --yes
grep -q "Option --tls-sni requires a value" "${TMP_DIR}/install-option-next-token.err" || fail "install next-option-as-value error is not explicit"

assert_failure update-option-next-token env HOME="$HOME" "$SCRIPT" update --source --yes
grep -q "Option --source requires a value" "${TMP_DIR}/update-option-next-token.err" || fail "update next-option-as-value error is not explicit"

local_remote_root="${TMP_DIR}/local-remote"
mkdir -p "$local_remote_root"
printf '%s\n' "$(tr -d '[:space:]' < "${ROOT_DIR}/version")" > "${local_remote_root}/version"
assert_success update-default-script-only env HOME="$HOME" SBD_UPDATE_BASE_URL="file://${local_remote_root}" "$SCRIPT" update --source primary --yes
! grep -q "Update installed core engine" "${TMP_DIR}/update-default-script-only.out" || fail "default update should not attempt core update"

assert_failure set-route-extra-arg env HOME="$HOME" "$SCRIPT" set-route direct extra
grep -q "Usage: set-route" "${TMP_DIR}/set-route-extra-arg.err" || fail "set-route extra-arg error is not explicit"

cfg_path_home="${TMP_DIR}/cfg-path-home"
mkdir -p "$cfg_path_home"
env PROJECT_ROOT="$ROOT_DIR" HOME="$cfg_path_home" bash <<'BASH'
set -euo pipefail
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/protocols.sh"
source "$PROJECT_ROOT/lib/security.sh"
source "$PROJECT_ROOT/lib/providers.sh"
detect_privilege_level
provider_cfg_snapshot_paths_sync
multi_ports_store_path_sync
case "$SBD_CFG_SNAPSHOT_DIR" in
  "$HOME"/sing-box-deve/state/cfg-snapshots) ;;
  *) echo "unexpected cfg snapshot dir: $SBD_CFG_SNAPSHOT_DIR" >&2; exit 1 ;;
esac
case "$SBD_MULTI_PORTS_FILE" in
  "$HOME"/sing-box-deve/state/multi-ports.db) ;;
  *) echo "unexpected multi-ports file: $SBD_MULTI_PORTS_FILE" >&2; exit 1 ;;
esac
mkdir -p "$SBD_CFG_SNAPSHOT_DIR/20260101T000000Z-aaaaaaaa" "$SBD_CFG_SNAPSHOT_DIR/20260102T000000Z-bbbbbbbb"
printf '%s\n' '20260102T000000Z-bbbbbbbb' > "$SBD_CFG_SNAPSHOT_LATEST_FILE"
provider_cfg_snapshots_list >/dev/null
provider_cfg_snapshots_prune_unlocked 1 >/dev/null
[[ -d "$SBD_CFG_SNAPSHOT_DIR/20260102T000000Z-bbbbbbbb" ]]
[[ ! -d "$SBD_CFG_SNAPSHOT_DIR/20260101T000000Z-aaaaaaaa" ]]
grep -qx '20260102T000000Z-bbbbbbbb' "$SBD_CFG_SNAPSHOT_LATEST_FILE"
BASH

set_port_home="${TMP_DIR}/set-port-home"
mkdir -p "$set_port_home"
env PROJECT_ROOT="$ROOT_DIR" HOME="$set_port_home" bash <<'BASH'
set -euo pipefail
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/protocols.sh"
source "$PROJECT_ROOT/lib/security.sh"
source "$PROJECT_ROOT/lib/providers.sh"
detect_privilege_level
init_runtime_layout
mkdir -p "$SBD_BIN_DIR" "$SBD_DATA_DIR" "$SBD_CONFIG_DIR"
cat > "$SBD_BIN_DIR/sing-box" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in check|version) exit 0 ;; *) exit 0 ;; esac
SH
chmod +x "$SBD_BIN_DIR/sing-box"
printf '%s\n' '11111111-1111-4111-8111-111111111111' > "$SBD_DATA_DIR/uuid"
printf '%s\n' 'PUBKEYPUBKEYPUBKEYPUBKEYPUBKEYPUBKEYPUBKEYP' > "$SBD_DATA_DIR/reality_public.key"
printf '%s\n' 'abcd1234' > "$SBD_DATA_DIR/reality_short_id"
cat > "$SBD_CONFIG_DIR/runtime.env" <<EOF
provider="vps"
profile="lite"
engine="sing-box"
protocols="vless-reality"
script_root="$PROJECT_ROOT"
installed_at="2026-06-17T00:00:00Z"
EOF
cat > "$SBD_CONFIG_DIR/config.json" <<'EOF'
{"inbounds":[{"type":"vless","tag":"vless-reality","listen":"::","listen_port":443,"users":[{"uuid":"11111111-1111-4111-8111-111111111111","flow":"xtls-rprx-vision"}],"tls":{"enabled":true,"server_name":"www.microsoft.com","reality":{"enabled":true,"handshake":{"server":"www.microsoft.com","server_port":443},"private_key":"PRIV","short_id":["abcd1234"]}}}],"outbounds":[{"type":"direct","tag":"direct"}],"route":{"rules":[]}}
EOF
provider_restart() { :; }
detect_public_ip() { printf '%s\n' '203.0.113.1'; }
fw_detect_backend() { FW_BACKEND="iptables"; }
fw_apply_rule() { local proto="$1" port="$2" service="${3:-core}"; fw_record_rule "$FW_BACKEND" "$proto" "$port" "$(fw_tag "$service" "$proto" "$port")"; }
AUTO_YES=true
mkdir -p "$SBD_STATE_DIR"
printf '%s|%s|%s|%s|%s\n' iptables tcp 443 'MYBOX:old1:core:tcp:443' now > "$SBD_RULES_FILE"
printf '%s|%s|%s|%s|%s\n' iptables tcp 443 'MYBOX:old2:core:tcp:443' now >> "$SBD_RULES_FILE"
provider_set_port vless-reality 24443
grep -q ':24443?' "$SBD_NODES_FILE"
! grep -q ':443?' "$SBD_NODES_FILE"
! grep -q 'core:tcp:443' "$SBD_RULES_FILE"
BASH

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

echo "[OK] CLI smoke checks passed"
