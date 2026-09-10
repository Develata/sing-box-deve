#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2034
set -euo pipefail
shopt -s extdebug
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
declare -A seen_definitions=()
source() {
  local source_result=0 function_name location
  builtin source "$@" || source_result=$?
  while read -r _ _ function_name; do
    location="$(declare -F "$function_name")"
    if [[ -n "${seen_definitions[$function_name]:-}" && "${seen_definitions[$function_name]}" != "$location" ]]; then
      printf '[ERROR] Function overwritten in source graph: %s\n  before: %s\n  after: %s\n' \
        "$function_name" "${seen_definitions[$function_name]}" "$location" >&2
      return 1
    fi
    seen_definitions["$function_name"]="$location"
  done < <(declare -F)
  return "$source_result"
}
source "$PROJECT_ROOT/lib/load.sh"
printf '[OK] full source graph has no overwritten function definitions\n'
