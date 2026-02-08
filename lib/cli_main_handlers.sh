#!/usr/bin/env bash

cli_handle_protocol_command() {
  case "${1:-matrix}" in
    matrix)
      shift || true
      if [[ "${1:-}" == "--enabled" ]]; then
        provider_protocol_matrix_show enabled
      else
        provider_protocol_matrix_show all
      fi
      ;;
    *)
      die "Usage: protocol matrix [--enabled]"
      ;;
  esac
}

cli_handle_fw_command() {
  case "${1:-}" in
    status)
      fw_detect_backend
      fw_status
      ;;
    rollback)
      fw_detect_backend
      fw_rollback
      ;;
    replay)
      fw_detect_backend
      fw_replay
      ;;
    *)
      die "Usage: fw [status|rollback|replay]"
      ;;
  esac
}
