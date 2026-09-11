#!/usr/bin/env bash
# shellcheck disable=SC2034

parse_update_args() {
  UPDATE_SCRIPT="false"
  UPDATE_CORE="false"
  UPDATE_ROLLBACK="false"
  UPDATE_FORCE="false"
  UPDATE_BIND_GIT=""
  UPDATE_CHECK_SOURCE="false"
  UPDATE_RELEASE="false"
  UPDATE_SOURCE="${UPDATE_SOURCE:-auto}"
  AUTO_YES="${AUTO_YES:-false}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --script) UPDATE_SCRIPT="true"; shift ;;
      --core) UPDATE_CORE="true"; shift ;;
      --all) UPDATE_SCRIPT="true"; UPDATE_CORE="true"; shift ;;
      --rollback) UPDATE_ROLLBACK="true"; shift ;;
      --force) UPDATE_FORCE="true"; shift ;;
      --bind-git)
        require_option_value "$1" "$#" "${2-}"
        UPDATE_BIND_GIT="$2"; shift 2 ;;
      --check-source) UPDATE_CHECK_SOURCE="true"; shift ;;
      --release) UPDATE_RELEASE="true"; shift ;;
      --source)
        require_option_value "$1" "$#" "${2-}"
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

  if [[ -n "$UPDATE_BIND_GIT" || "$UPDATE_CHECK_SOURCE" == true ]]; then
    [[ "$UPDATE_SCRIPT" == false && "$UPDATE_CORE" == false && "$UPDATE_ROLLBACK" == false && "$UPDATE_RELEASE" == false ]] ||
      die "--bind-git/--check-source cannot be combined with other update operations"
    [[ -z "$UPDATE_BIND_GIT" || "$UPDATE_CHECK_SOURCE" == false ]] || die "Choose either --bind-git or --check-source"
    return 0
  fi
  [[ "$UPDATE_RELEASE" == false || "$UPDATE_ROLLBACK" == false ]] || die "--release cannot be combined with --rollback"
  [[ "$UPDATE_RELEASE" == false ]] || UPDATE_SCRIPT=true

  # Rollback is exclusive - don't combine with other update operations
  if [[ "$UPDATE_ROLLBACK" == "true" ]]; then
    UPDATE_SCRIPT="false"
    UPDATE_CORE="false"
    UPDATE_FORCE="false"
    return 0
  fi

  if [[ "$UPDATE_SCRIPT" == "false" && "$UPDATE_CORE" == "false" ]]; then
    UPDATE_SCRIPT="true"
  fi
}
