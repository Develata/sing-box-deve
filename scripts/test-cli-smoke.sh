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

# shellcheck disable=SC2034
PROJECT_ROOT="$ROOT_DIR"
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/protocols.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/protocol_links_common.sh"
protocol_csv_has "vless-reality,hysteria2,tuic,naive,vless-ws" "vless-ws" || fail "protocol_csv_has missed vless-ws"
if protocol_csv_has "vless-reality,hysteria2" "vless-ws"; then
  fail "protocol_csv_has returned false positive"
fi

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
uninstall_global_bin="${TMP_DIR}/uninstall-global-bin"
uninstall_systemd_bin="${TMP_DIR}/uninstall-systemd-bin"
mkdir -p "$uninstall_home"
mkdir -p "$uninstall_global_bin" "$uninstall_systemd_bin"
printf '%s\n' '# fake root-owned global launcher fixture' > "${uninstall_global_bin}/sb"
cat > "${uninstall_systemd_bin}/systemctl" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  daemon-reload) echo 'simulated user-mode daemon-reload failure' >&2; exit 1 ;;
  disable|stop|is-active) exit 1 ;;
  *) exit 0 ;;
esac
SH
chmod +x "${uninstall_systemd_bin}/systemctl"
assert_success uninstall-no-firewall env HOME="$uninstall_home" SBD_FW_BACKEND=none SBD_GLOBAL_BIN_DIR="$uninstall_global_bin" "$SCRIPT" uninstall --keep-settings
grep -q "No firewall backend detected" "${TMP_DIR}/uninstall-no-firewall.out" || fail "uninstall no-firewall warning missing"
[[ -f "${uninstall_global_bin}/sb" ]] || fail "user-mode uninstall removed global sb fixture"
env PROJECT_ROOT="$ROOT_DIR" PATH="${uninstall_systemd_bin}:${PATH}" bash <<'BASH' >"${TMP_DIR}/daemon-reload-failure.out" 2>"${TMP_DIR}/daemon-reload-failure.err"
set -euo pipefail
source "$PROJECT_ROOT/lib/common.sh"
SBD_INIT_SYSTEM=systemd
sbd_systemd_daemon_reload false "test daemon-reload"
BASH
grep -q "simulated user-mode daemon-reload failure" "${TMP_DIR}/daemon-reload-failure.out" || fail "daemon-reload failure was not logged"

serv00_home="${TMP_DIR}/serv00-home"
mkdir -p "$serv00_home"
assert_success serv00-local-bundle env HOME="$serv00_home" "$SCRIPT" install --provider serv00 --yes
grep -q "generated local bundle only" "${TMP_DIR}/serv00-local-bundle.out" || fail "serv00 local bundle warning missing"
[[ -f "${serv00_home}/sing-box-deve/config/serv00.env" ]] || fail "serv00 local bundle missing serv00.env"

serv00_cred_home="${TMP_DIR}/serv00-cred-home"
serv00_no_sshpass_bin="${TMP_DIR}/serv00-no-sshpass-bin"
mkdir -p "$serv00_cred_home" "$serv00_no_sshpass_bin"
for d in /usr/bin /bin; do
  [[ -d "$d" ]] || continue
  for exe in "$d"/*; do
    [[ -x "$exe" && ! -d "$exe" ]] || continue
    name="${exe##*/}"
    [[ "$name" == "sshpass" ]] && continue
    [[ -e "${serv00_no_sshpass_bin}/${name}" ]] || ln -s "$exe" "${serv00_no_sshpass_bin}/${name}"
  done
done
assert_failure serv00-credentials-no-sshpass env PATH="$serv00_no_sshpass_bin" HOME="$serv00_cred_home" SERV00_HOST=h SERV00_USER=u SERV00_PASS=p "$SCRIPT" install --provider serv00 --yes
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

# Regression: prepare_domain_cert_for_protocols must not leak or read unbound
# cert/key locals when an existing domain certificate is discovered under set -u.
env PROJECT_ROOT="$ROOT_DIR" bash <<'BASH'
set -euo pipefail
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/protocols.sh"
source "$PROJECT_ROOT/lib/providers_system_tools.sh"
source "$PROJECT_ROOT/lib/providers_domain_tls.sh"
cert_tmp="$(mktemp -d)"
touch "$cert_tmp/fullchain.cer" "$cert_tmp/key.key"
sbd_candidate_cert_pairs_for_domain() { printf '%s|%s\n' "$cert_tmp/fullchain.cer" "$cert_tmp/key.key"; }
sbd_check_domain_cert_pair() { return 0; }
TLS_SERVER_NAME=example.com
TLS_MODE=self-signed
prepare_domain_cert_for_protocols hysteria2
[[ "$TLS_MODE" == "acme" ]]
[[ "$ACME_CERT_PATH" == "$cert_tmp/fullchain.cer" ]]
[[ "$ACME_KEY_PATH" == "$cert_tmp/key.key" ]]
BASH

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
{"inbounds":[{"type":"vless","tag":"vless-reality","listen":"::","listen_port":443,"users":[{"uuid":"11111111-1111-4111-8111-111111111111","flow":"xtls-rprx-vision"}],"tls":{"enabled":true,"server_name":"www.bing.com","reality":{"enabled":true,"handshake":{"server":"www.bing.com","server_port":443},"private_key":"PRIV","short_id":["abcd1234"]}}}],"outbounds":[{"type":"direct","tag":"direct"}],"route":{"rules":[]}}
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
provider_cfg_rebuild_runtime() {
  persist_runtime_state "${provider:-vps}" "${profile:-lite}" "${engine:-sing-box}" "${protocols:-vless-reality}"
}
provider_cfg_set_profile full
grep -q '^profile="full"$' "$SBD_CONFIG_DIR/runtime.env"
cat > "$SBD_CONFIG_DIR/runtime.env" <<EOF
provider="vps"
profile="lite"
engine="sing-box"
protocols="vless-reality"
script_root="$PROJECT_ROOT"
installed_at="2026-06-17T00:00:00Z"
EOF
provider_cfg_apply_with_snapshot_unlocked profile full
grep -q '^profile="full"$' "$SBD_CONFIG_DIR/runtime.env"
provider_cfg_protocol_add hysteria2 random
grep -q '^profile="full"$' "$SBD_CONFIG_DIR/runtime.env"
grep -q '^protocols="vless-reality,hysteria2"$' "$SBD_CONFIG_DIR/runtime.env"
sbd_export_protocol_ports_from_engine sing-box vless-reality
[[ "${SBD_PORT_VLESS_REALITY:-}" == "24443" ]]
cat > "$SBD_CONFIG_DIR/xray-config.json" <<'EOF'
{"inbounds":[{"tag":"vless-reality","port":443}]}
EOF
cat > "$SBD_BIN_DIR/xray" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  x25519)
    printf '%s\n' 'Private key: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' 'Public key: BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'
    ;;
  run)
    exit 0
    ;;
  *) exit 0 ;;
esac
SH
chmod +x "$SBD_BIN_DIR/xray"
build_xray_config vless-reality
grep -Eq '"port"[[:space:]]*:[[:space:]]*24443' "$SBD_CONFIG_DIR/xray-config.json"
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

bash "${ROOT_DIR}/scripts/test-web-front-smoke.sh"

echo "[OK] CLI smoke checks passed"
