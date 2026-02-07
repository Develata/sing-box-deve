#!/usr/bin/env bash

doctor_system() {
  local deps=(curl awk sed grep cut tr ss)
  local missing=0
  local dep
  for dep in "${deps[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      log_warn "Missing dependency: $dep"
      missing=1
    fi
  done

  if [[ "$missing" -eq 0 ]]; then
    log_success "Core dependencies present"
  else
    log_warn "Some dependencies are missing"
  fi

  local mem_kb
  mem_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
  if [[ -n "$mem_kb" ]]; then
    local mem_mb
    mem_mb=$((mem_kb / 1024))
    log_info "Detected memory: ${mem_mb}MB"
    if (( mem_mb <= 600 )); then
      log_info "Small-memory host detected; Lite profile is recommended"
    fi
  fi

  if curl -fsS --max-time 5 https://1.1.1.1 >/dev/null 2>&1; then
    log_success "Outbound HTTPS reachability: ok"
  else
    log_warn "Outbound HTTPS reachability: failed"
  fi

  if command -v getent >/dev/null 2>&1; then
    if getent hosts github.com >/dev/null 2>&1; then
      log_success "DNS resolution check: ok"
    else
      log_warn "DNS resolution check: failed"
    fi
  fi
}
