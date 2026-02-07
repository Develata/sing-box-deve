#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="sing-box-deve"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${PROJECT_ROOT}/lib/common.sh"
source "${PROJECT_ROOT}/lib/protocols.sh"
source "${PROJECT_ROOT}/lib/security.sh"
source "${PROJECT_ROOT}/lib/providers.sh"
source "${PROJECT_ROOT}/lib/output.sh"
source "${PROJECT_ROOT}/lib/menu.sh"
source "${PROJECT_ROOT}/lib/cli_args.sh"
source "${PROJECT_ROOT}/lib/cli_commands.sh"
source "${PROJECT_ROOT}/lib/cli_wizard.sh"
source "${PROJECT_ROOT}/lib/cli_main.sh"

init_i18n
main "$@"
