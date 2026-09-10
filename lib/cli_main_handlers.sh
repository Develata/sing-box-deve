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
  if [[ "${1:-}" == status ]]; then fw_status; return $?; fi
  sbd_with_mutation_lock cli_handle_fw_mutation "$@"
}

cli_handle_fw_mutation() {
  case "${1:-}" in
    status)
      fw_status
      ;;
    rollback)
      fw_detect_backend || return 1
      fw_rollback
      ;;
    replay)
      fw_detect_backend || return 1
      fw_replay
      ;;
    *)
      die "Usage: fw [status|rollback|replay]"
      ;;
  esac
}
