#!/usr/bin/env bash

parse_set_port_egress_args() {
  SET_PORT_EGRESS_ACTION="list"
  SET_PORT_EGRESS_MAP=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --list) SET_PORT_EGRESS_ACTION="list"; shift ;;
      --clear) SET_PORT_EGRESS_ACTION="clear"; shift ;;
      --map)
        require_option_value "$1" "$#"
        SET_PORT_EGRESS_ACTION="map"
        SET_PORT_EGRESS_MAP="$2"
        shift 2
        ;;
      *) die "Unknown set-port-egress argument: $1" ;;
    esac
  done
  if [[ "$SET_PORT_EGRESS_ACTION" == "map" && -z "$SET_PORT_EGRESS_MAP" ]]; then
    die "Usage: set-port-egress --list | --clear | --map <port:direct|proxy|warp|psiphon,...>"
  fi
}
