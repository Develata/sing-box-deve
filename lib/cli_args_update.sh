#!/usr/bin/env bash

parse_update_args() {
  UPDATE_SCRIPT="false"
  UPDATE_CORE="false"
  UPDATE_ROLLBACK="false"
  UPDATE_SOURCE="${UPDATE_SOURCE:-auto}"
  AUTO_YES="${AUTO_YES:-false}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --script) UPDATE_SCRIPT="true"; shift ;;
      --core) UPDATE_CORE="true"; shift ;;
      --all) UPDATE_SCRIPT="true"; UPDATE_CORE="true"; shift ;;
      --rollback) UPDATE_ROLLBACK="true"; shift ;;
      --source)
        require_option_value "$1" "$#"
        UPDATE_SOURCE="$2"
        shift 2
        ;;
      --yes|-y) AUTO_YES="true"; shift ;;
      *) die "Unknown update argument: $1" ;;
    esac
  done

  case "$UPDATE_SOURCE" in
    auto|primary|backup) ;;
    *) die "--source must be auto|primary|backup" ;;
  esac

  # Rollback is exclusive - don't combine with other update operations
  if [[ "$UPDATE_ROLLBACK" == "true" ]]; then
    UPDATE_SCRIPT="false"
    UPDATE_CORE="false"
    return 0
  fi

  if [[ "$UPDATE_SCRIPT" == "false" && "$UPDATE_CORE" == "false" ]]; then
    UPDATE_SCRIPT="true"
    UPDATE_CORE="true"
  fi
}
