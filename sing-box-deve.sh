#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="sing-box-deve"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${PROJECT_ROOT}/lib/common.sh"
source "${PROJECT_ROOT}/lib/protocols.sh"
source "${PROJECT_ROOT}/lib/security.sh"
source "${PROJECT_ROOT}/lib/providers.sh"
source "${PROJECT_ROOT}/lib/output.sh"

usage() {
  cat <<'EOF'
Usage:
  sing-box-deve.sh wizard
  sing-box-deve.sh install [--provider vps|serv00|sap|docker] [--profile lite|full] [--engine sing-box|xray] [--protocols p1,p2] [--argo off|temp|fixed] [--argo-domain DOMAIN] [--argo-token TOKEN] [--warp-mode off|global] [--yes]
  sing-box-deve.sh apply -f config.env
  sing-box-deve.sh list
  sing-box-deve.sh restart
  sing-box-deve.sh update [--script|--core|--all] [--yes]
  sing-box-deve.sh version
  sing-box-deve.sh settings show
  sing-box-deve.sh settings set <key> <value>
  sing-box-deve.sh settings set key1=value1 key2=value2 ...
  sing-box-deve.sh uninstall
  sing-box-deve.sh doctor
  sing-box-deve.sh fw status
  sing-box-deve.sh fw rollback

Examples:
  ./sing-box-deve.sh install --provider vps --profile lite --engine sing-box --protocols vless-reality
  ./sing-box-deve.sh apply -f ./config.env
EOF
}

parse_install_args() {
  PROVIDER="vps"
  PROFILE="lite"
  ENGINE="sing-box"
  PROTOCOLS="vless-reality"
  DRY_RUN="false"
  AUTO_YES="${AUTO_YES:-false}"
  ARGO_MODE="${ARGO_MODE:-off}"
  ARGO_DOMAIN="${ARGO_DOMAIN:-}"
  ARGO_TOKEN="${ARGO_TOKEN:-}"
  WARP_MODE="${WARP_MODE:-off}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --provider)
        PROVIDER="$2"; shift 2 ;;
      --profile)
        PROFILE="$2"; shift 2 ;;
      --engine)
        ENGINE="$2"; shift 2 ;;
      --protocols)
        PROTOCOLS="$2"; shift 2 ;;
      --dry-run)
        DRY_RUN="true"; shift ;;
      --yes|-y)
        AUTO_YES="true"; shift ;;
      --argo)
        ARGO_MODE="$2"; shift 2 ;;
      --argo-domain)
        ARGO_DOMAIN="$2"; shift 2 ;;
      --argo-token)
        ARGO_TOKEN="$2"; shift 2 ;;
      --warp-mode)
        WARP_MODE="$2"; shift 2 ;;
      *)
        die "Unknown install argument: $1" ;;
    esac
  done
}

parse_update_args() {
  UPDATE_SCRIPT="false"
  UPDATE_CORE="false"
  AUTO_YES="${AUTO_YES:-false}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --script) UPDATE_SCRIPT="true"; shift ;;
      --core) UPDATE_CORE="true"; shift ;;
      --all) UPDATE_SCRIPT="true"; UPDATE_CORE="true"; shift ;;
      --yes|-y) AUTO_YES="true"; shift ;;
      *) die "Unknown update argument: $1" ;;
    esac
  done

  if [[ "$UPDATE_SCRIPT" == "false" && "$UPDATE_CORE" == "false" ]]; then
    UPDATE_SCRIPT="true"
    UPDATE_CORE="true"
  fi
}

show_version() {
  local local_ver remote_ver
  local_ver="$(current_script_version)"
  remote_ver="$(fetch_remote_script_version 2>/dev/null || true)"

  log_info "$(msg "当前脚本版本" "Current script version"): ${local_ver}"
  if [[ -n "$remote_ver" ]]; then
    log_info "$(msg "远程最新版本" "Remote latest version"): ${remote_ver}"
  else
    log_warn "$(msg "无法获取远程版本（可设置 SBD_UPDATE_BASE_URL）" "Unable to fetch remote version (set SBD_UPDATE_BASE_URL if needed)")"
  fi
}

update_command() {
  parse_update_args "$@"

  if [[ "$UPDATE_SCRIPT" == "true" ]]; then
    local local_ver remote_ver
    local_ver="$(current_script_version)"
    remote_ver="$(fetch_remote_script_version 2>/dev/null || true)"

    if [[ -n "$remote_ver" && "$remote_ver" == "$local_ver" ]]; then
      log_info "$(msg "脚本已是最新版本" "Script is already up to date") (${local_ver})"
    else
      if prompt_yes_no "$(msg "更新脚本本体与模块文件吗？" "Update script and module files?")" "Y"; then
        perform_script_self_update
        log_success "$(msg "脚本更新完成，请重新执行命令" "Script update completed, please rerun command")"
      else
        log_warn "$(msg "已跳过脚本更新" "Skipped script update")"
      fi
    fi
  fi

  if [[ "$UPDATE_CORE" == "true" ]]; then
    if prompt_yes_no "$(msg "更新已安装的核心（sing-box/xray）吗？" "Update installed core engine (sing-box/xray)?")" "Y"; then
      provider_update
    else
      log_warn "$(msg "已跳过核心更新" "Skipped core engine update")"
    fi
  fi
}

settings_command() {
  local sub="${1:-show}"
  case "$sub" in
    show)
      show_settings
      ;;
    set)
      ensure_root
      shift
      [[ $# -ge 1 ]] || die "Usage: settings set <key> <value> OR settings set key=value ..."
      if [[ $# -eq 2 ]] && [[ "$1" != *"="* ]]; then
        set_setting "$1" "$2"
      else
        local kv key value
        for kv in "$@"; do
          if [[ "$kv" != *"="* ]]; then
            die "Invalid setting format: $kv (expected key=value)"
          fi
          key="${kv%%=*}"
          value="${kv#*=}"
          [[ -n "$key" ]] || die "Invalid setting key in: $kv"
          set_setting "$key" "$value"
        done
      fi
      log_success "$(msg "设置已保存" "Setting saved")"
      show_settings
      ;;
    *)
      die "Usage: settings [show|set <key> <value>|set key=value ...]"
      ;;
  esac
}

wizard() {
  ensure_root
  detect_os
  init_runtime_layout

  log_info "$(msg "欢迎使用 ${PROJECT_NAME} 交互向导" "Welcome to ${PROJECT_NAME} interactive wizard")"
  echo

  echo "$(msg "部署场景决定脚本运行位置：" "Provider decides where deployment runs:")"
  echo "- vps: $(msg "本机服务器直接运行" "local server runtime")"
  echo "- serv00: $(msg "远程 Serv00 引导部署" "remote Serv00 bootstrap")"
  echo "- sap: $(msg "SAP Cloud Foundry 部署" "SAP Cloud Foundry deployment")"
  echo "- docker: $(msg "容器化部署" "containerized deployment")"
  if prompt_yes_no "$(msg "使用推荐场景 'vps' 吗？" "Use recommended provider 'vps'?")" "Y"; then
    PROVIDER="vps"
  else
    prompt_with_default "$(msg "选择场景 [vps/serv00/sap/docker]" "Choose provider [vps/serv00/sap/docker]")" "vps" PROVIDER
  fi

  echo
  echo "$(msg "资源档位决定内存开销：" "Profile controls resource usage:")"
  echo "- lite: $(msg "适合 512MB，最多 2 个协议" "optimized for 512MB, up to 2 protocols")"
  echo "- full: $(msg "开放全部协议选择" "all enabled choices")"
  if prompt_yes_no "$(msg "使用推荐档位 'lite' 吗？" "Use recommended profile 'lite'?")" "Y"; then
    PROFILE="lite"
  else
    prompt_with_default "$(msg "选择档位 [lite/full]" "Choose profile [lite/full]")" "lite" PROFILE
  fi

  echo
  echo "$(msg "内核选择决定运行核心：" "Engine controls runtime core:")"
  echo "- sing-box: $(msg "默认且支持协议更广" "default and broader protocol support")"
  echo "- xray: $(msg "可选核心" "optional core")"
  if prompt_yes_no "$(msg "使用推荐内核 'sing-box' 吗？" "Use recommended engine 'sing-box'?")" "Y"; then
    ENGINE="sing-box"
  else
    prompt_with_default "$(msg "选择内核 [sing-box/xray]" "Choose engine [sing-box/xray]")" "sing-box" ENGINE
  fi

  echo
  echo "$(msg "协议选择" "Protocol selection")"
  PROTOCOLS="vless-reality"
  if prompt_yes_no "$(msg "保留默认协议 'vless-reality' 吗？" "Keep default protocol 'vless-reality'?")" "Y"; then
    PROTOCOLS="vless-reality"
  else
    PROTOCOLS=""
    for p in "${ALL_PROTOCOLS[@]}"; do
      if [[ "$PROFILE" == "lite" ]]; then
        local count
        count="$(echo "$PROTOCOLS" | tr ',' '\n' | grep -c . || true)"
        if (( count >= 2 )); then
          break
        fi
      fi
      local hint risk resource note
      hint="$(protocol_hint "$p")"
      risk="$(echo "$hint" | awk -F';' '{print $1}' | cut -d= -f2)"
      resource="$(echo "$hint" | awk -F';' '{print $2}' | cut -d= -f2)"
      note="$(echo "$hint" | awk -F';' '{print $3}' | cut -d= -f2-)"
      log_info "$(msg "协议提示" "Protocol hint") ${p}: risk=${risk}, resource=${resource}, ${note}"
      if prompt_yes_no "$(msg "启用协议 '${p}' 吗？" "Enable protocol '${p}'?")" "N"; then
        if [[ -z "$PROTOCOLS" ]]; then
          PROTOCOLS="$p"
        else
          PROTOCOLS+=" ,$p"
        fi
      fi
    done
    PROTOCOLS="$(echo "$PROTOCOLS" | tr -d ' ')"
    [[ -n "$PROTOCOLS" ]] || PROTOCOLS="vless-reality"
  fi

  if [[ "$PROFILE" == "lite" ]] && prompt_yes_no "$(msg "Lite 模式：启用推荐第二协议 'hysteria2' 吗？" "Lite mode: enable recommended second protocol 'hysteria2'?")" "N"; then
    if [[ "$PROTOCOLS" == "vless-reality" ]]; then
      PROTOCOLS="vless-reality,hysteria2"
    fi
  fi

  echo
  echo "$(msg "Argo 可通过 Cloudflare 隧道暴露 WS 协议。" "Argo can expose WS protocols through Cloudflare tunnel.")"
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
  echo "$(msg "WARP 用于控制 sing-box 出站路径。" "WARP controls outbound path for sing-box.")"
  if prompt_yes_no "$(msg "启用 WARP 全局出站模式吗？" "Enable WARP global outbound mode?")" "N"; then
    WARP_MODE="global"
    log_info "$(msg "安装前请设置 WARP_PRIVATE_KEY 和 WARP_PEER_PUBLIC_KEY" "Remember to set WARP_PRIVATE_KEY and WARP_PEER_PUBLIC_KEY before install")"
  else
    WARP_MODE="off"
  fi

  validate_provider "$PROVIDER"
  validate_engine "$ENGINE"
  validate_profile_protocols "$PROFILE" "$PROTOCOLS"

  print_plan_summary "$PROVIDER" "$PROFILE" "$ENGINE" "$PROTOCOLS"
  if ! prompt_yes_no "$(msg "现在开始安装吗？" "Proceed with installation now?")" "Y"; then
    log_warn "Installation aborted by user"
    exit 0
  fi

  run_install "$PROVIDER" "$PROFILE" "$ENGINE" "$PROTOCOLS" "false"
}

run_install() {
  local provider="$1"
  local profile="$2"
  local engine="$3"
  local protocols_csv="$4"
  local dry_run="$5"

  ensure_root
  detect_os
  init_runtime_layout

  validate_provider "$provider"
  validate_engine "$engine"
  validate_profile_protocols "$profile" "$protocols_csv"

  export ARGO_MODE ARGO_DOMAIN ARGO_TOKEN WARP_MODE

  create_install_context "$provider" "$profile" "$engine" "$protocols_csv"
  auto_generate_config_snapshot "$CONFIG_SNAPSHOT_FILE"

  fw_detect_backend
  fw_snapshot_create

  if [[ "$dry_run" == "true" ]]; then
    log_info "Dry-run enabled; no system changes applied"
    print_plan_summary "$provider" "$profile" "$engine" "$protocols_csv"
    return 0
  fi

  if [[ "${AUTO_YES:-false}" != "true" ]]; then
    print_plan_summary "$provider" "$profile" "$engine" "$protocols_csv"
    if ! prompt_yes_no "$(msg "确认执行该安装计划吗？" "Apply this plan?")" "Y"; then
      log_warn "Installation aborted by user"
      exit 0
    fi
  fi

  if ! provider_install "$provider" "$profile" "$engine" "$protocols_csv"; then
    log_error "Install failed; rolling back firewall changes"
    fw_rollback
    exit 1
  fi

  log_success "Installation flow completed"
  print_post_install_info "$provider" "$profile" "$engine" "$protocols_csv"
}

apply_config() {
  local config_file="$1"
  ensure_root
  detect_os
  init_runtime_layout

  if [[ ! -f "$config_file" ]]; then
    die "Config file not found: $config_file"
  fi

  # shellcheck disable=SC1090
  source "$config_file"

  local provider="${provider:-vps}"
  local profile="${profile:-lite}"
  local engine="${engine:-sing-box}"
  local protocols="${protocols:-vless-reality}"
  export ARGO_MODE="${argo_mode:-${ARGO_MODE:-off}}"
  export ARGO_DOMAIN="${argo_domain:-${ARGO_DOMAIN:-}}"
  export ARGO_TOKEN="${argo_token:-${ARGO_TOKEN:-}}"
  export WARP_MODE="${warp_mode:-${WARP_MODE:-off}}"

  run_install "$provider" "$profile" "$engine" "$protocols" "false"
}

doctor() {
  ensure_root
  detect_os
  init_runtime_layout
  log_info "Running diagnostics"
  doctor_system
  fw_detect_backend
  fw_status
  provider_doctor
}

main() {
  local cmd="${1:-help}"
  case "$cmd" in
    wizard)
      shift
      wizard "$@"
      ;;
    install)
      shift
      parse_install_args "$@"
      run_install "$PROVIDER" "$PROFILE" "$ENGINE" "$PROTOCOLS" "$DRY_RUN"
      ;;
    apply)
      shift
      if [[ "${1:-}" != "-f" ]] || [[ -z "${2:-}" ]]; then
        die "Usage: apply -f config.env"
      fi
      apply_config "$2"
      ;;
    list)
      shift
      provider_list
      ;;
    restart)
      shift
      provider_restart
      ;;
    update)
      shift
      update_command "$@"
      ;;
    version)
      shift
      show_version
      ;;
    settings)
      shift
      settings_command "$@"
      ;;
    uninstall)
      shift
      provider_uninstall
      ;;
    doctor)
      shift
      doctor
      ;;
    fw)
      shift
      case "${1:-}" in
        status)
          fw_detect_backend
          fw_status
          ;;
        rollback)
          fw_detect_backend
          fw_rollback
          ;;
        *)
          die "Usage: fw [status|rollback]"
          ;;
      esac
      ;;
    help|-h|--help)
      usage
      ;;
    *)
      usage
      die "Unknown command: $cmd"
      ;;
  esac
}

init_i18n
main "$@"
