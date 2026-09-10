#!/usr/bin/env bash

provider_split3_show() {
  ensure_root
  [[ -f "${SBD_CONFIG_DIR}/runtime.env" ]] || die "$(msg "未找到运行时状态" "No runtime state found")"
  sbd_load_runtime_env "${SBD_CONFIG_DIR}/runtime.env" || return 1
  log_info "$(msg "split3 直连=${domain_split_direct:-}" "split3 direct=${domain_split_direct:-}")"
  log_info "$(msg "split3 代理=${domain_split_proxy:-}" "split3 proxy=${domain_split_proxy:-}")"
  log_info "$(msg "split3 屏蔽=${domain_split_block:-}" "split3 block=${domain_split_block:-}")"
}

provider_split3_set() {
  sbd_with_mutation_lock provider_split3_set_unlocked "$@"
}

provider_split3_set_unlocked() {
  ensure_root
  local direct_csv="$1" proxy_csv="$2" block_csv="$3"
  provider_cfg_command domain-split "$direct_csv" "$proxy_csv" "$block_csv"
  provider_split3_show
}
