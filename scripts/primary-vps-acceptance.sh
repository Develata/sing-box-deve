#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034,SC2031
set -euo pipefail
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
if [[ "${1:-}" == --help ]]; then
  echo 'Usage: sudo SBD_DISPOSABLE_ACCEPTANCE=yes bash scripts/primary-vps-acceptance.sh REPORT_DIR'
  echo 'Requires a fresh disposable Ubuntu/Debian VM with systemd and outbound Internet access.'
  exit 0
fi
[[ "${SBD_DISPOSABLE_ACCEPTANCE:-}" == yes && "$EUID" == 0 ]] || {
  echo '[ERROR] Explicit disposable-host authorization and root are required' >&2; exit 2;
}
[[ -d /run/systemd/system ]] || { echo '[ERROR] A running systemd VM is required' >&2; exit 2; }
command -v python3 >/dev/null || { echo "[ERROR] python3 is required for acceptance receipts" >&2; exit 2; }
source /etc/os-release
[[ -z "${SBD_EXPECT_DISTRO:-}" || "$ID" == "$SBD_EXPECT_DISTRO" ]] || exit 2
case "$ID" in ubuntu|debian) ;; *) echo '[ERROR] Primary acceptance requires Ubuntu/Debian' >&2; exit 2 ;; esac
for path in /opt/sing-box-deve /etc/sing-box-deve /var/lib/sing-box-deve /var/lib/sing-box-deve.host /usr/local/bin/sb; do
  [[ ! -e "$path" && ! -L "$path" ]] || { echo "[ERROR] Host is not fresh: $path" >&2; exit 2; }
done
report_dir="${1:?A report directory is required}"
mkdir -p "$report_dir"
report_dir="$(cd "$report_dir" && pwd -P)"
source_sha="$(git -C "$root_dir" rev-parse HEAD)"
[[ -z "$(git -C "$root_dir" status --porcelain --untracked-files=all)" ]] || {
  echo '[ERROR] Acceptance requires a clean source checkout' >&2; exit 2;
}
[[ ! -e "$report_dir/receipt.json" && ! -e "$report_dir/cases.txt" ]] || {
  echo '[ERROR] Acceptance report already exists' >&2; exit 2;
}
private_dir="$(mktemp -d)"
chmod 700 "$private_dir"
probe_pid=""; result=failure; case_name=preflight
cleanup() {
  local rc=$?
  if [[ -e "$root_dir/.git.acceptance-saved" && ! -e "$root_dir/.git" ]]; then
    mv "$root_dir/.git.acceptance-saved" "$root_dir/.git" || rc=1
  fi
  [[ -z "$probe_pid" ]] || kill "$probe_pid" 2>/dev/null || true
  python3 - "$report_dir/receipt.json" "$result" "$case_name" "$ID" "$VERSION_ID" "$root_dir" "$source_sha" "$rc" <<'PY' || rc=1
import datetime, json, pathlib, subprocess, sys
out, result, case, distro, version, root, original_sha, code = sys.argv[1:]
sha = subprocess.check_output(['git', '-C', root, 'rev-parse', 'HEAD'], text=True).strip()
clean = sha == original_sha and not subprocess.check_output(['git', '-C', root, 'status', '--porcelain', '--untracked-files=all'], text=True)
cases = pathlib.Path(out).with_name('cases.txt')
result = 'success' if result == 'success' and int(code) == 0 and clean else 'failure'
json.dump(dict(schema=1, result=result, last_case=case, distro=distro, version=version,
               source_sha=original_sha, source_clean=bool(clean), exit_code=int(code),
               cases=cases.read_text().splitlines() if cases.exists() else [],
               finished_at=datetime.datetime.now(datetime.timezone.utc).isoformat()), open(out, 'w'), indent=2)
if not clean:
    sys.exit(1)
PY
  echo "[INFO] Sanitized receipt: $report_dir/receipt.json"
  echo "[INFO] Private diagnostic logs remain on the disposable VM: $private_dir"
  exit "$rc"
}
trap cleanup EXIT
step() {
  case_name="$1"; shift
  echo "[CASE] $case_name"
  timeout -k 5s 900s "$@" > "$private_dir/$case_name.log" 2>&1 || return $?
  printf '%s passed\n' "$case_name" >> "$report_dir/cases.txt"
}
cli="$root_dir/sing-box-deve.sh"
step install-lite "$cli" install --provider vps --profile lite --engine sing-box --protocols vless-reality --yes
cli=/usr/local/bin/sb
# Source switching is script-only, including recovery without the Git directory.
core_pid_before="$(systemctl show sing-box-deve -p MainPID --value)"
sha256sum /opt/sing-box-deve/bin/sing-box /etc/sing-box-deve/config.json /opt/sing-box-deve/data/uuid > "$private_dir/source-preserved.sha256"
step script-bind "$cli" update --bind-git "$root_dir" --yes
[[ "$("$cli" --print-root)" == "$root_dir" ]]
step script-source-check "$cli" update --check-source
step script-source-repeat "$cli" update --bind-git "$root_dir" --yes
# Temporarily hiding .git tests the fixed recovery entry without relocating the
# running acceptance script. Restore it even if the rollback command fails.
mv "$root_dir/.git" "$root_dir/.git.acceptance-saved"
if step script-source-recovery "$cli" --rollback-source; then
  mv "$root_dir/.git.acceptance-saved" "$root_dir/.git"
else
  mv "$root_dir/.git.acceptance-saved" "$root_dir/.git"
  exit 1
fi
[[ "$("$cli" --print-root)" == /opt/sing-box-deve/releases/* ]]
sha256sum -c "$private_dir/source-preserved.sha256" >/dev/null
[[ "$core_pid_before" == "$(systemctl show sing-box-deve -p MainPID --value)" ]]
# Probe through the generated client outbound, without adding routes or a TUN.
PROJECT_ROOT="$root_dir"
source "$PROJECT_ROOT/lib/load.sh"
cp "$SBD_BIN_DIR/sing-box" "$private_dir/probe-core"
probe() {
  local tag="$1" expect_warp="${2:-false}" outbound attempt ok=false
  local attempts=5 deadline remaining request_timeout
  # Quick Tunnel announces its hostname before recursive DNS necessarily resolves it.
  [[ "$tag" != sbd-vless-argo ]] || attempts=180
  deadline=$((SECONDS + 180))
  case_name="probe-$tag-$expect_warp"
  [[ -z "$probe_pid" ]] || { kill "$probe_pid" 2>/dev/null || true; wait "$probe_pid" 2>/dev/null || true; probe_pid=""; }
  outbound="$(singbox_client_proxy_outbounds | jq -ce --arg tag "$tag" '.[] | select(.tag == $tag) | if $tag == "sbd-vless-reality" then .server="127.0.0.1" else . end')"
  jq -n --argjson outbound "$outbound" '{log:{level:"warn"},
    dns:{servers:[{type:"local",tag:"dns-local"}],disable_cache:true},
    inbounds:[{type:"socks",listen:"127.0.0.1",listen_port:39080}],
    outbounds:[$outbound],route:{final:$outbound.tag}}' > "$private_dir/probe.json"
  "$private_dir/probe-core" run -c "$private_dir/probe.json" > "$private_dir/probe.log" 2>&1 & probe_pid=$!
  for ((attempt=1; attempt<=attempts && SECONDS<deadline; attempt++)); do
    remaining=$((deadline - SECONDS))
    request_timeout=20
    (( remaining >= request_timeout )) || request_timeout="$remaining"
    if curl -fsS --connect-timeout 5 --max-time "$request_timeout" --socks5-hostname 127.0.0.1:39080 \
      https://www.cloudflare.com/cdn-cgi/trace -o "$private_dir/trace" 2>/dev/null; then ok=true; break; fi
    sleep 1
  done
  [[ "$ok" == true ]]
  [[ "$expect_warp" != true ]] || grep -Eq '^warp=(on|plus)$' "$private_dir/trace"
  printf '%s passed\n' "$case_name" >> "$report_dir/cases.txt"
}
probe sbd-vless-reality
cp "$SBD_DATA_DIR/uuid" "$private_dir/original-uuid"
step rotate-id "$cli" cfg rotate-id
if cmp -s "$SBD_DATA_DIR/uuid" "$private_dir/original-uuid"; then exit 1; fi
step snapshot-rollback "$cli" cfg rollback latest
cmp -s "$SBD_DATA_DIR/uuid" "$private_dir/original-uuid"
step change-port "$cli" set-port --protocol vless-reality --port 29443
probe sbd-vless-reality
step reinstall-full-argo "$cli" install --provider vps --profile full --engine sing-box --protocols vless-reality,vless-ws --argo temp --yes
probe sbd-vless-reality
probe sbd-vless-argo
step core-update "$cli" update --core --yes
probe sbd-vless-reality
step warp-register "$cli" warp register
step warp-socks-start "$cli" warp socks5-start 39081
step upstream-socks "$cli" set-egress --mode socks --host 127.0.0.1 --port 39081 --udp direct
step upstream-global-route "$cli" set-route global-proxy
probe sbd-vless-reality true
step route-reset "$cli" set-route direct
step upstream-reset "$cli" set-egress --mode direct
step warp-socks-stop "$cli" warp socks5-stop
step warp-global "$cli" warp mode global
probe sbd-vless-reality true
step warp-reset "$cli" warp mode off
step restart "$cli" restart --all
probe sbd-vless-reality
# Reinstall via Xray verifies engine switching with real systemd services.
step kernel-xray "$cli" kernel set xray latest
probe sbd-vless-reality
step kernel-singbox "$cli" kernel set sing-box latest
probe sbd-vless-reality
step uninstall "$cli" uninstall --keep-settings --purge-managed-host-changes
[[ ! -e /opt/sing-box-deve && ! -e /etc/sing-box-deve && ! -e /usr/local/bin/sb ]]
backup="$(sed -n 's/^\[INFO\] Backup preserved and verified: //p' "$private_dir/uninstall.log")"
[[ "$backup" == /opt/sing-box-deve.backup-* && "$backup" != *$'\n'* && -s "$backup/files/data/uuid" ]]
cmp -s "$private_dir/original-uuid" "$backup/files/data/uuid"
(cd "$backup"; sha256sum -c checksums.txt > /dev/null)
case_name=complete
result=success
printf '[OK] primary VPS acceptance completed\n'
