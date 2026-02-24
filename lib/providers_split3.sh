#!/usr/bin/env bash

provider_split3_show() {
  ensure_root
  [[ -f /etc/sing-box-deve/runtime.env ]] || die "$(msg "未找到运行时状态" "No runtime state found")"
  sbd_load_runtime_env /etc/sing-box-deve/runtime.env
  log_info "$(msg "split3 直连=${domain_split_direct:-}" "split3 direct=${domain_split_direct:-}")"
  log_info "$(msg "split3 代理=${domain_split_proxy:-}" "split3 proxy=${domain_split_proxy:-}")"
  log_info "$(msg "split3 屏蔽=${domain_split_block:-}" "split3 block=${domain_split_block:-}")"
}

provider_split3_set() {
  ensure_root
  local direct_csv="$1" proxy_csv="$2" block_csv="$3"
  provider_cfg_command domain-split "$direct_csv" "$proxy_csv" "$block_csv"
  provider_split3_show
}
