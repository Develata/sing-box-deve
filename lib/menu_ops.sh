#!/usr/bin/env bash

menu_ops() {
  while true; do
    menu_status_header
    menu_title "$(msg "[内核、WARP与系统工具]" "[Kernel, WARP & System]")"
    echo "1) $(msg "查看内核版本状态（kernel show）" "Show kernel versions (kernel show)")"
    echo "2) $(msg "切换到最新 sing-box（kernel set sing-box latest）" "Set sing-box latest (kernel set sing-box latest)")"
    echo "3) $(msg "切换到最新 xray（kernel set xray latest）" "Set xray latest (kernel set xray latest)")"
    echo "4) $(msg "指定内核版本标签（kernel set <engine> <tag>）" "Set custom kernel tag (kernel set <engine> <tag>)")"
    echo "5) $(msg "查看 WARP 状态（warp status）" "Show WARP status (warp status)")"
    echo "6) $(msg "注册 WARP 账户（warp register）" "Register WARP account (warp register)")"
    echo "7) $(msg "查看 BBR 状态（sys bbr-status）" "Show BBR status (sys bbr-status)")"
    echo "8) $(msg "启用 BBR（sys bbr-enable）" "Enable BBR (sys bbr-enable)")"
    echo "9) $(msg "安装 acme.sh（sys acme-install）" "Install acme.sh (sys acme-install)")"
    echo "10) $(msg "申请证书（sys acme-issue）" "Issue certificate (sys acme-issue)")"
    echo "11) $(msg "应用证书到运行时（sys acme-apply）" "Apply cert to runtime (sys acme-apply)")"
    echo "0) $(msg "返回上级" "Back")"
    read -r -p "$(msg "请选择" "Select"): " c
    case "${c:-0}" in
      1) provider_kernel_show; menu_pause ;;
      2) provider_kernel_set sing-box latest; menu_pause ;;
      3) provider_kernel_set xray latest; menu_pause ;;
      4)
        read -r -p "$(msg "内核[sing-box/xray]" "engine[sing-box/xray]"): " e
        read -r -p "$(msg "版本标签(例: v1.12.20)" "tag(ex: v1.12.20)"): " t
        provider_kernel_set "$e" "$t"
        menu_pause
        ;;
      5) provider_warp_status; menu_pause ;;
      6) provider_warp_register; menu_pause ;;
      7) provider_sys_command bbr-status; menu_pause ;;
      8) provider_sys_command bbr-enable; menu_pause ;;
      9) provider_sys_command acme-install; menu_pause ;;
      10)
        read -r -p "$(msg "域名" "domain"): " d
        read -r -p "$(msg "邮箱" "email"): " e
        read -r -p "$(msg "DNS Provider(泛域名可选，如 dns_cf)" "DNS provider(optional for wildcard, e.g. dns_cf)"): " dp
        provider_sys_command acme-issue "$d" "$e" "$dp"
        menu_pause
        ;;
      11)
        read -r -p "$(msg "证书路径" "cert path"): " cpath
        read -r -p "$(msg "私钥路径" "key path"): " kpath
        provider_sys_command acme-apply "$cpath" "$kpath"
        menu_pause
        ;;
      0) return 0 ;;
      *) menu_invalid; menu_pause ;;
    esac
  done
}
