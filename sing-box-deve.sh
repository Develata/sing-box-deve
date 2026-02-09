#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC2034
PROJECT_NAME="sing-box-deve"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bootstrap_remote_tree() {
  local repo_slug="${SBD_REPO_SLUG:-Develata/sing-box-deve}"
  local repo_ref="${SBD_REPO_REF:-main}"
  local archive_url="${SBD_ARCHIVE_URL:-https://codeload.github.com/${repo_slug}/tar.gz/refs/heads/${repo_ref}}"
  local tmp_dir="" archive top_dir remote_root target_script

  tmp_dir="$(mktemp -d)"
  archive="${tmp_dir}/repo.tar.gz"

  cleanup_bootstrap() {
    if [[ -n "${tmp_dir:-}" && -d "${tmp_dir}" ]]; then
      rm -rf "$tmp_dir"
    fi
  }
  trap cleanup_bootstrap EXIT

  if ! curl -fsSL "$archive_url" -o "$archive"; then
    echo "[ERROR] Failed to download project archive: ${archive_url}" >&2
    exit 1
  fi

  tar -xzf "$archive" -C "$tmp_dir"
  top_dir="$(tar -tzf "$archive" | awk -F/ 'NR==1{print $1; exit}')"
  remote_root="${tmp_dir}/${top_dir}"

  if [[ ! -f "${remote_root}/lib/common.sh" || ! -f "${remote_root}/sing-box-deve.sh" ]]; then
    echo "[ERROR] Invalid project archive structure" >&2
    exit 1
  fi

  target_script="${remote_root}/sing-box-deve.sh"
  chmod +x "$target_script"
  exec "$target_script" "$@"
}

if [[ ! -f "${PROJECT_ROOT}/lib/common.sh" ]]; then
  bootstrap_remote_tree "$@"
fi

source "${PROJECT_ROOT}/lib/common.sh"
source "${PROJECT_ROOT}/lib/legacy_compat.sh"
source "${PROJECT_ROOT}/lib/protocols.sh"
source "${PROJECT_ROOT}/lib/security.sh"
source "${PROJECT_ROOT}/lib/providers.sh"
source "${PROJECT_ROOT}/lib/output.sh"
source "${PROJECT_ROOT}/lib/menu.sh"
source "${PROJECT_ROOT}/lib/cli_args.sh"
source "${PROJECT_ROOT}/lib/cli_commands.sh"
source "${PROJECT_ROOT}/lib/cli_wizard.sh"
source "${PROJECT_ROOT}/lib/cli_main_handlers.sh"
source "${PROJECT_ROOT}/lib/cli_main.sh"

init_i18n
main "$@"
