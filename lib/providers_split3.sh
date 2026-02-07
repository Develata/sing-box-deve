#!/usr/bin/env bash

provider_split3_show() {
  ensure_root
  [[ -f /etc/sing-box-deve/runtime.env ]] || die "No runtime state found"
  # shellcheck disable=SC1091
  source /etc/sing-box-deve/runtime.env
  log_info "split3 direct=${domain_split_direct:-}"
  log_info "split3 proxy=${domain_split_proxy:-}"
  log_info "split3 block=${domain_split_block:-}"
}

provider_split3_set() {
  ensure_root
  local direct_csv="$1" proxy_csv="$2" block_csv="$3"
  provider_cfg_command domain-split "$direct_csv" "$proxy_csv" "$block_csv"
  provider_split3_show
}
