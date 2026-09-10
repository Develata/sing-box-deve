#!/usr/bin/env bash

perform_script_self_update() {
  sbd_with_mutation_lock sbd_transaction_run script-update sbd_release_download_update
}

perform_download_update() {
  perform_script_self_update "$@"
}

perform_git_update() {
  # Source checkouts remain developer-owned; updates install an immutable runtime.
  perform_script_self_update "$@"
}

sync_installed_script_root_from_project() {
  sbd_with_mutation_lock sbd_transaction_run script-update sbd_release_install_tree "$PROJECT_ROOT"
}

verify_sb_launcher_target() {
  local launcher="/usr/local/bin/sb" resolved
  [[ "${SBD_USER_MODE:-false}" != true ]] || launcher="${HOME}/.local/bin/sb"
  [[ -x "$launcher" ]] || return 1
  resolved="$("$launcher" --print-root)" || return 1
  [[ "$resolved" == "$(readlink -f "$SBD_INSTALL_DIR/current")" ]]
}
