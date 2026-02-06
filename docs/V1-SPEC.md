# sing-box-deve V1 Specification

## Confirmed Decisions

- Default engine: `sing-box`
- Optional engine: `xray`
- WireGuard in V1: standalone VPN mode + outbound mode
- Lite profile: max 2 protocols
- Lite default protocol: `vless-reality`
- Lite recommended second protocol: `hysteria2`
- Primary targets: Ubuntu, Debian
- No backward compatibility with old variable names
- Static Web command generator on GitHub Pages
- VPS must not run extra local web panel services by default
- First-start language selection is persisted in one-line settings file (`/etc/sing-box-deve/settings.conf`)

## Firewall Policy

- Strictly incremental firewall changes
- Explicit rollback support
- Absolutely no:
  - `ufw disable`
  - `iptables -F`
  - `iptables -X`
  - `setenforce 0`

## Firewall Backend Selection

1. `ufw` when active
2. `nftables` when available
3. `firewalld` when running
4. `iptables` as fallback

## Scope

- Scenarios: VPS, Serv00/Hostuno, SAP, Docker, Workers, GitHub Actions
- Protocol family: full set in V1, including Trojan and WireGuard

## Current V1 Implementation Progress

- VPS runtime implemented with service management and node output generation
- Argo tunnel sidecar implemented (`temp` and `fixed` modes)
- WARP outbound implemented for sing-box (`off`/`global`, key-driven)
- Artifact checksum verification implemented for `sing-box`, `xray`, and `cloudflared`
- Serv00/SAP/Docker providers support environment-driven executable deployment flows and generated templates
