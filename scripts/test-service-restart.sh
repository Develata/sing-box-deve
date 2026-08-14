#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${root_dir}/lib/common_base.sh"
source "${root_dir}/lib/common_nohup.sh"
source "${root_dir}/lib/common_init.sh"

tmp_dir="$(mktemp -d)"
SBD_DATA_DIR="${tmp_dir}/data"
SBD_RUNTIME_DIR="${tmp_dir}/run"
trap 'SBD_INIT_SYSTEM=nohup; nohup_stop_service test-svc >/dev/null 2>&1 || true; rm -rf "$tmp_dir"' EXIT INT TERM HUP

rc-service() { return 42; }
SBD_INIT_SYSTEM="openrc"
if sbd_service_restart test-svc '/bin/sleep 20'; then
  die "OpenRC restart failure was swallowed"
fi

systemctl() { return 43; }
SBD_INIT_SYSTEM="systemd"
if sbd_service_restart test-svc '/bin/sleep 20'; then
  die "systemd restart failure was swallowed"
fi

nohup_register_crontab() { return 0; }
nohup_remove_crontab() { return 0; }
SBD_INIT_SYSTEM="nohup"
if sbd_service_restart test-svc '/bin/false'; then
  die "nohup immediate exit was reported as success"
fi

nohup_register_crontab() { return 44; }
if sbd_service_restart test-svc '/bin/sleep 20'; then
  die "nohup crontab registration failure was swallowed"
fi
[[ ! -f "${SBD_RUNTIME_DIR}/test-svc.pid" ]] || die "failed nohup registration left a PID file"
nohup_register_crontab() { return 0; }

sbd_service_restart test-svc '/bin/sleep 20'
first_pid="$(<"${SBD_RUNTIME_DIR}/test-svc.pid")"
kill -0 "$first_pid"
sbd_service_restart test-svc '/bin/sleep 20'
second_pid="$(<"${SBD_RUNTIME_DIR}/test-svc.pid")"
kill -0 "$second_pid"
[[ "$first_pid" != "$second_pid" ]] || die "nohup restart did not replace PID"

printf '[OK] service restart propagation checks passed\n'
