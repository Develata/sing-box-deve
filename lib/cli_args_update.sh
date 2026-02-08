#!/usr/bin/env bash

parse_update_args() {
  UPDATE_SCRIPT="false"
  UPDATE_CORE="false"
  UPDATE_SOURCE="${UPDATE_SOURCE:-auto}"
  AUTO_YES="${AUTO_YES:-false}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --script) UPDATE_SCRIPT="true"; shift ;;
      --core) UPDATE_CORE="true"; shift ;;
      --all) UPDATE_SCRIPT="true"; UPDATE_CORE="true"; shift ;;
      --source) UPDATE_SOURCE="$2"; shift 2 ;;
      --yes|-y) AUTO_YES="true"; shift ;;
      *) die "Unknown update argument: $1" ;;
    esac
  done

  case "$UPDATE_SOURCE" in
    auto|primary|backup) ;;
    *) die "--source must be auto|primary|backup" ;;
  esac

  if [[ "$UPDATE_SCRIPT" == "false" && "$UPDATE_CORE" == "false" ]]; then
    UPDATE_SCRIPT="true"
    UPDATE_CORE="true"
  fi
}
