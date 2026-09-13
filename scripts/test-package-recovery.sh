#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$PROJECT_ROOT/lib/load.sh"
package_test="$(mktemp -d)"
trap 'rm -rf "$package_test"' EXIT
export package_test
SBD_HOST_STATE_DIR="$package_test/control"
mkdir -p "$package_test/bin" "$SBD_HOST_STATE_DIR"
export PATH="$package_test/bin:$PATH"
cat > "$package_test/bin/apt-get" <<'SH'
#!/usr/bin/env bash
set -eu
[[ "$DEBIAN_FRONTEND" == noninteractive ]]
printf 'apt\n' >> "$package_test/calls"
case "$(cat "$package_test/mode")" in
  fail) touch "$package_test/unhealthy"; exit 42 ;;
  timeout|failed-child)
    touch "$package_test/unhealthy"
    # The parent exits on TERM; the maintainer child ignores it.
    bash -c 'trap "" TERM; echo "$BASHPID" > "$package_test/child"; exec sleep 60' &
    if [[ "$(cat "$package_test/mode")" == failed-child ]]; then
      for ((attempt=0; attempt<50; attempt++)); do [[ ! -f "$package_test/child" ]] || exit 42; sleep 0.02; done
      exit 98
    fi
    trap 'exit 1' TERM
    wait ;;
  success) exit 0 ;;
esac
SH
cat > "$package_test/bin/dpkg" <<'SH'
#!/usr/bin/env bash
set -eu
printf 'dpkg %s\n' "$*" >> "$package_test/calls"
case "$*" in
  --audit) [[ ! -e "$package_test/audit-error" ]] || exit 2; [[ ! -e "$package_test/unhealthy" ]] || echo 'half-configured fixture' ;;
  '--configure -a')
    [[ "$DEBIAN_FRONTEND" == noninteractive ]]
    [[ ! -e "$package_test/reconcile-fails" ]] || exit 43
    rm -f "$package_test/unhealthy" ;;
  *) exit 99 ;;
esac
SH
chmod +x "$package_test/bin/apt-get" "$package_test/bin/dpkg"
# Only the lock probe is substituted: never probe or mutate CI's real database.
sbd_package_database_unlocked() { [[ ! -e "$package_test/locked" ]]; }
fail() { echo "[FAIL] $*" >&2; exit 1; }
marker="$SBD_HOST_STATE_DIR/package_recovery_required"
printf 'fail\n' > "$package_test/mode"
if sbd_apt_get install -y fixture; then fail 'original package failure was hidden'; else [[ $? == 42 ]]; fi
[[ ! -e "$package_test/unhealthy" && ! -e "$marker" ]] || fail 'successful reconciliation did not clear unhealthy state'
[[ "$(grep -c '^dpkg --configure -a$' "$package_test/calls")" == 1 ]] || fail 'reconciliation was not exactly once'

touch "$package_test/reconcile-fails"
if sbd_apt_get install -y fixture; then fail 'reconciliation failure was hidden'; fi
[[ -f "$marker" && "$(stat -c %a "$marker")" == 600 ]] || fail 'recovery marker missing or public'
count="$(grep -c '^apt$' "$package_test/calls")"
if sbd_apt_get install -y another; then fail 'unhealthy package state accepted'; fi
[[ "$(grep -c '^apt$' "$package_test/calls")" == "$count" ]] || fail 'new mutation stacked on failed reconciliation'
rm "$package_test/reconcile-fails"
printf 'success\n' > "$package_test/mode"
sbd_apt_get install -y fixture
[[ ! -e "$marker" && ! -e "$package_test/unhealthy" ]]

# One invocation gets at most one reconciliation, including preflight recovery.
touch "$package_test/unhealthy"
printf 'fail\n' > "$package_test/mode"
before="$(grep -c '^dpkg --configure -a$' "$package_test/calls")"
if sbd_apt_get install -y fixture; then fail 'failed op following preflight repair was hidden'; fi
[[ "$(grep -c '^dpkg --configure -a$' "$package_test/calls")" == "$((before + 1))" && -e "$marker" ]]
printf 'success\n' > "$package_test/mode"
sbd_apt_get install -y fixture

touch "$package_test/audit-error"
count="$(grep -c '^apt$' "$package_test/calls")"
if sbd_apt_get install -y fixture; then fail 'audit error allowed mutation'; fi
[[ -e "$marker" && "$(grep -c '^apt$' "$package_test/calls")" == "$count" ]]
rm "$package_test/audit-error"
touch "$package_test/locked"
if sbd_apt_get install -y fixture; then fail 'busy database allowed mutation'; fi
[[ -e "$marker" ]]
rm "$package_test/locked"

printf 'timeout\n' > "$package_test/mode"
started=$SECONDS
if SBD_PACKAGE_TIMEOUT=1 SBD_PACKAGE_TERM_GRACE=3 SBD_TIMEOUT_KILL_AFTER=1 sbd_apt_get install -y fixture; then
  fail 'timeout returned success'
else [[ $? == 124 ]]; fi
elapsed=$((SECONDS - started))
(( elapsed >= 4 && elapsed <= 9 )) || fail "independent grace/deadline not respected: $elapsed"
child="$(cat "$package_test/child")"
if [[ -r "/proc/$child/stat" ]]; then
  state="$(awk '{print $3}' "/proc/$child/stat")"
  [[ "$state" == Z || "$state" == X ]] || fail 'TERM-exiting parent orphaned a live maintainer'
fi
[[ ! -e "$package_test/unhealthy" && ! -e "$marker" ]]
[[ -s "$SBD_HOST_STATE_DIR/package-recovery.log" ]]
rm "$package_test/child"
printf 'failed-child\n' > "$package_test/mode"
started=$SECONDS
if SBD_PACKAGE_TIMEOUT=5 SBD_PACKAGE_TERM_GRACE=2 sbd_apt_get install -y fixture; then
  fail 'failed parent with surviving maintainer returned success'
else [[ $? == 42 ]]; fi
(( SECONDS - started >= 2 && SECONDS - started <= 8 )) || fail 'failed parent skipped bounded group cleanup'
child="$(cat "$package_test/child")"
if [[ -r "/proc/$child/stat" ]]; then
  state="$(awk '{print $3}' "/proc/$child/stat")"
  [[ "$state" == Z || "$state" == X ]] || fail 'failed parent orphaned a live maintainer'
fi
[[ ! -e "$package_test/unhealthy" && ! -e "$marker" ]]
printf '[OK] package grace, descendants, one-round reconciliation, marker and fail-closed preflight\n'
