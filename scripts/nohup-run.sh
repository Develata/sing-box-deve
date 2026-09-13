#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$PROJECT_ROOT/lib/load.sh"
detect_privilege_level
if [[ "${1:-}" == --argv ]]; then
  (( $# >= 5 )) || exit 2
  svc_name="$2"; SBD_RUNTIME_DIR="$3"; SBD_DATA_DIR="$4"
  shift 4
  argv=("$@")
else
  [[ $# == 4 ]] || exit 2
  svc_name="$1"; SBD_RUNTIME_DIR="$3"; SBD_DATA_DIR="$4"
  argv=()
  sbd_decode_command_argv "$2" argv || exit 2
fi
[[ "$SBD_RUNTIME_DIR" == /* && "$SBD_DATA_DIR" == /* ]] || exit 2
# Cron is already registered; avoid rewriting it while cron launches this job.
nohup_register_crontab() { return 0; }
nohup_remove_crontab() { return 0; }
sbd_with_mutation_lock nohup_start_service "$svc_name" "${argv[@]}"
