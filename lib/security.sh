#!/usr/bin/env bash

FW_BACKEND=""
SBD_FW_REPLAY_SERVICE_FILE="/etc/systemd/system/sing-box-deve-fw-replay.service"

source "${PROJECT_ROOT}/lib/security_firewall_core.sh"
source "${PROJECT_ROOT}/lib/security_firewall_ops.sh"
