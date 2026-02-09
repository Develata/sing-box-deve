#!/usr/bin/env bash

doctor_system() {
  local deps=(curl awk sed grep cut tr ss)
  local missing=0
  local dep
  for dep in "${deps[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      log_warn "$(msg "缺少依赖: $dep" "Missing dependency: $dep")"
      missing=1
    fi
  done

  if [[ "$missing" -eq 0 ]]; then
    log_success "$(msg "核心依赖检查通过" "Core dependencies present")"
  else
    log_warn "$(msg "存在缺失依赖，请先安装后再执行关键操作" "Some dependencies are missing")"
  fi

  local mem_kb
  mem_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
  if [[ -n "$mem_kb" ]]; then
    local mem_mb
    mem_mb=$((mem_kb / 1024))
    log_info "$(msg "检测到内存: ${mem_mb}MB" "Detected memory: ${mem_mb}MB")"
    if (( mem_mb <= 600 )); then
      log_info "$(msg "检测到小内存主机，建议使用 Lite 档位" "Small-memory host detected; Lite profile is recommended")"
    fi
  fi

  if curl -fsS --max-time 5 https://1.1.1.1 >/dev/null 2>&1; then
    log_success "$(msg "外网 HTTPS 连通性: 正常" "Outbound HTTPS reachability: ok")"
  else
    log_warn "$(msg "外网 HTTPS 连通性: 失败" "Outbound HTTPS reachability: failed")"
  fi

  if command -v getent >/dev/null 2>&1; then
    if getent hosts github.com >/dev/null 2>&1; then
      log_success "$(msg "DNS 解析检查: 正常" "DNS resolution check: ok")"
    else
      log_warn "$(msg "DNS 解析检查: 失败" "DNS resolution check: failed")"
    fi
  fi
}
