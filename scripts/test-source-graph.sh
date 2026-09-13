#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2034
set -euo pipefail
shopt -s extdebug
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
declare -A seen_definitions=()
graph_collision=0
source() {
  local source_result=0 function_name location
  local -a graph_functions=()
  builtin source "$@" || source_result=$?
  # extdebug gives definition locations only when names are passed to declare.
  # Query all names together instead of forking once per function per import.
  mapfile -t graph_functions < <(compgen -A function)
  while read -r function_name location; do
    if [[ -n "${seen_definitions[$function_name]:-}" && "${seen_definitions[$function_name]}" != "$location" ]]; then
      printf '[ERROR] Function overwritten in source graph: %s\n  before: %s\n  after: %s\n' \
        "$function_name" "${seen_definitions[$function_name]}" "$location" >&2
      graph_collision=1
    fi
    seen_definitions["$function_name"]="$location"
  done < <(declare -F "${graph_functions[@]}")
  (( graph_collision == 0 )) || return 1
  return "$source_result"
}
source "${1:-$PROJECT_ROOT/lib/load.sh}"
printf '[OK] full source graph has no overwritten function definitions\n'
