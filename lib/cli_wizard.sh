#!/usr/bin/env bash
# shellcheck disable=SC2034

wizard() {
  ensure_root
  detect_os
  init_runtime_layout
  PORT_MODE="${PORT_MODE:-random}"
  MANUAL_PORT_MAP="${MANUAL_PORT_MAP:-}"
  INSTALL_MAIN_PORT="${INSTALL_MAIN_PORT:-}"
  RANDOM_MAIN_PORT="${RANDOM_MAIN_PORT:-false}"

  log_info "$(msg "欢迎使用 ${PROJECT_NAME} 交互向导" "Welcome to ${PROJECT_NAME} interactive wizard")"
  echo

  printf '%s\n' "$(msg "部署场景决定脚本运行位置：" "Provider decides where deployment runs:")"
  echo "- vps: $(msg "本机服务器直接运行" "local server runtime")"
  echo "- serv00: $(msg "远程 Serv00 引导部署" "remote Serv00 bootstrap")"
  if prompt_yes_no "$(msg "使用推荐场景 'vps' 吗？" "Use recommended provider 'vps'?")" "Y"; then
    PROVIDER="vps"
  else
    prompt_with_default "$(msg "选择场景 [vps/serv00]" "Choose provider [vps/serv00]")" "vps" PROVIDER
  fi

  echo
  printf '%s\n' "$(msg "资源档位决定内存开销：" "Profile controls resource usage:")"
  echo "- lite: $(msg "适合 512MB，最多 2 个协议" "optimized for 512MB, up to 2 protocols")"
  echo "- full: $(msg "开放全部协议选择" "all enabled choices")"
  if prompt_yes_no "$(msg "使用推荐档位 'lite' 吗？" "Use recommended profile 'lite'?")" "Y"; then
    PROFILE="lite"
  else
    prompt_with_default "$(msg "选择档位 [lite/full]" "Choose profile [lite/full]")" "lite" PROFILE
  fi

  echo
  printf '%s\n' "$(msg "内核选择决定运行核心：" "Engine controls runtime core:")"
  echo "- sing-box: $(msg "默认且支持协议更广" "default and broader protocol support")"
  echo "- xray: $(msg "可选核心" "optional core")"
  if prompt_yes_no "$(msg "使用推荐内核 'sing-box' 吗？" "Use recommended engine 'sing-box'?")" "Y"; then
    ENGINE="sing-box"
  else
    prompt_with_default "$(msg "选择内核 [sing-box/xray]" "Choose engine [sing-box/xray]")" "sing-box" ENGINE
  fi

  echo
  printf '%s\n' "$(msg "部署预设" "Deployment preset")"
  echo "1) reality-only: $(msg "仅 vless-reality；不需要域名" "vless-reality only; no domain required")"
  echo "2) reality-plus-domain: $(msg "vless-reality + hysteria2/tuic/naive；必须自有域名和有效证书" "vless-reality + hysteria2/tuic/naive; requires domain and valid certificate")"
  echo "3) full: $(msg "全部 sing-box 协议各部署一份；必须自有域名和有效证书" "all sing-box protocols; requires domain and valid certificate")"
  local preset_choice
  prompt_with_default "$(msg "选择预设 [1/2/3]" "Choose preset [1/2/3]")" "1" preset_choice
  case "$preset_choice" in
    1|reality-only)
      INSTALL_PRESET="reality-only"
      ENGINE="sing-box"
      PROFILE="lite"
      PROTOCOLS="vless-reality"
      ;;
    2|reality-plus-domain|reality-plus)
      INSTALL_PRESET="reality-plus-domain"
      ENGINE="sing-box"
      PROFILE="full"
      PROTOCOLS="vless-reality,hysteria2,tuic,naive"
      ;;
    3|full)
      INSTALL_PRESET="full"
      ENGINE="sing-box"
      PROFILE="full"
      PROTOCOLS="vless-reality,vless-ws,shadowsocks-2022,naive,hysteria2,tuic"
      ;;
    *) die "$(msg "预设必须是 1/2/3" "Preset must be 1/2/3")" ;;
  esac

  if protocols_require_domain_cert "$PROTOCOLS"; then
    echo
    printf '%s\n' "$(msg "所选协议包含 hysteria2/tuic/naive，必须提供自有域名和有效证书。" "Selected protocols include hysteria2/tuic/naive and require a domain with a valid certificate.")"
    prompt_with_default "$(msg "输入 TLS 域名/SNI" "Input TLS domain/SNI")" "example.com" TLS_SERVER_NAME
    ACME_DOMAIN="${ACME_DOMAIN:-$TLS_SERVER_NAME}"
    if prompt_yes_no "$(msg "是否提供已有证书路径？" "Provide existing certificate paths?")" "N"; then
      TLS_MODE="acme"
      prompt_with_default "$(msg "输入 fullchain 证书路径" "Input fullchain certificate path")" "" ACME_CERT_PATH
      prompt_with_default "$(msg "输入私钥路径" "Input private key path")" "" ACME_KEY_PATH
    else
      TLS_MODE="acme-auto"
      prompt_with_default "$(msg "输入 ACME 注册邮箱（nginx/OpenResty webroot）" "Input ACME account email (nginx/OpenResty webroot)")" "" ACME_EMAIL
    fi
  fi

  local wizard_protocols=()
  protocols_to_array "$PROTOCOLS" wizard_protocols
  if [[ "${#wizard_protocols[@]}" -gt 0 ]]; then
    echo
    if prompt_yes_no "$(msg "首次安装端口策略使用随机端口吗？（推荐）" "Use random ports for first install? (recommended)")" "Y"; then
      PORT_MODE="random"
      MANUAL_PORT_MAP=""
      INSTALL_MAIN_PORT=""
      RANDOM_MAIN_PORT="true"
    else
      PORT_MODE="manual"
      MANUAL_PORT_MAP=""
      RANDOM_MAIN_PORT="false"
      local used_ports="" p mapping proto default_port chosen
      for p in "${wizard_protocols[@]}"; do
        protocol_needs_local_listener "$p" || continue
        mapping="$(protocol_port_map "$p")"
        proto="${mapping%%:*}"
        default_port="$(get_protocol_port "$p")"
        while true; do
          prompt_with_default "$(msg "输入协议 ${p} 的端口 (1-65535)" "Input port for protocol ${p} (1-65535)")" "$default_port" chosen
          if [[ ! "$chosen" =~ ^[0-9]+$ ]] || (( chosen < 1 || chosen > 65535 )); then
            log_warn "$(msg "端口必须是 1-65535 的数字" "Port must be numeric within 1-65535")"
            continue
          fi
          if sbd_port_used_in_list "$chosen" "$used_ports"; then
            log_warn "$(msg "端口与本次已选端口冲突，请重新输入" "Port conflicts with selected ports, please input again")"
            continue
          fi
          if sbd_port_is_in_use "$proto" "$chosen"; then
            log_warn "$(msg "端口已被系统占用，请重新输入" "Port already in use, please input again")"
            continue
          fi
          break
        done
        used_ports="${used_ports:+${used_ports},}${chosen}"
        MANUAL_PORT_MAP="${MANUAL_PORT_MAP:+${MANUAL_PORT_MAP},}${p}:${chosen}"
      done
      INSTALL_MAIN_PORT=""
    fi
  fi

  echo
  printf '%s\n' "$(msg "Argo 可通过 Cloudflare 隧道暴露 WS 协议。" "Argo can expose WS protocols through Cloudflare tunnel.")"
  if prompt_yes_no "$(msg "启用 Argo 隧道功能吗？" "Enable Argo tunnel feature?")" "N"; then
    if prompt_yes_no "$(msg "使用临时 Argo 隧道（无需 token）吗？" "Use temporary Argo tunnel (no token needed)?")" "Y"; then
      ARGO_MODE="temp"
    else
      ARGO_MODE="fixed"
      prompt_with_default "$(msg "输入 Argo 固定隧道 token" "Input Argo fixed token")" "" ARGO_TOKEN
      prompt_with_default "$(msg "输入 Argo 固定域名（可选）" "Input Argo fixed domain (optional)")" "" ARGO_DOMAIN
    fi
  else
    ARGO_MODE="off"
  fi

  echo
  printf '%s\n' "$(msg "WARP 用于控制 sing-box 出站路径。" "WARP controls outbound path for sing-box.")"
  if prompt_yes_no "$(msg "启用 WARP 全局出站模式吗？" "Enable WARP global outbound mode?")" "N"; then
    WARP_MODE="global"
    log_info "$(msg "安装前请设置 WARP_PRIVATE_KEY 和 WARP_PEER_PUBLIC_KEY" "Remember to set WARP_PRIVATE_KEY and WARP_PEER_PUBLIC_KEY before install")"
  else
    WARP_MODE="off"
  fi

  echo
  printf '%s\n' "$(msg "出站代理用于让所有入站流量通过上游 socks/http/https 代理转发。" "Outbound proxy lets inbound traffic egress through upstream socks/http/https.")"
  if prompt_yes_no "$(msg "保持默认直连出站（direct）吗？" "Keep default direct outbound mode?")" "Y"; then
    OUTBOUND_PROXY_MODE="direct"
  else
    prompt_with_default "$(msg "选择出站代理模式 [direct/socks/http/https]" "Choose outbound proxy mode [direct/socks/http/https]")" "direct" OUTBOUND_PROXY_MODE
    if [[ "$OUTBOUND_PROXY_MODE" != "direct" ]]; then
      prompt_with_default "$(msg "输入上游代理主机" "Input upstream proxy host")" "" OUTBOUND_PROXY_HOST
      prompt_with_default "$(msg "输入上游代理端口" "Input upstream proxy port")" "1080" OUTBOUND_PROXY_PORT
      prompt_with_default "$(msg "输入上游代理用户名（可选）" "Input upstream proxy username (optional)")" "" OUTBOUND_PROXY_USER
      prompt_with_default "$(msg "输入上游代理密码（可选）" "Input upstream proxy password (optional)")" "" OUTBOUND_PROXY_PASS
    fi
  fi

  echo
  printf '%s\n' "$(msg "VPN 分流模式用于控制哪些流量走直连或代理。" "VPN split routing controls which traffic goes direct or proxy.")"
  if [[ "$OUTBOUND_PROXY_MODE" == "direct" && "${WARP_MODE:-off}" == "off" ]]; then
    ROUTE_MODE="direct"
    log_info "$(msg "当前无上游代理/WARP，分流模式固定为 direct" "No proxy/warp configured, route mode fixed to direct")"
  elif prompt_yes_no "$(msg "使用推荐分流 'cn-direct'（中国流量直连，其他走代理）吗？" "Use recommended route mode 'cn-direct' (CN direct, others proxy)?")" "Y"; then
    ROUTE_MODE="cn-direct"
  else
    prompt_with_default "$(msg "选择分流模式 [direct/global-proxy/cn-direct/cn-proxy]" "Choose route mode [direct/global-proxy/cn-direct/cn-proxy]")" "direct" ROUTE_MODE
  fi

  validate_provider "$PROVIDER"
  validate_engine "$ENGINE"
  validate_profile_protocols "$PROFILE" "$PROTOCOLS"

  print_plan_summary "$PROVIDER" "$PROFILE" "$ENGINE" "$PROTOCOLS"
  if ! prompt_yes_no "$(msg "现在开始安装吗？" "Proceed with installation now?")" "Y"; then
    log_warn "$(msg "用户取消安装流程" "Installation aborted by user")"
    exit 0
  fi

  run_install "$PROVIDER" "$PROFILE" "$ENGINE" "$PROTOCOLS" "false"
}
