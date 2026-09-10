#!/usr/bin/env bash
# The entrypoint and integration tests share this exact module graph.
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
