#!/usr/bin/env bash

provider_cfg_with_lock() {
  sbd_with_mutation_lock "$@"
}
