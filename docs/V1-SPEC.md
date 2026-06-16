# sing-box-deve V1 Specification

## Confirmed Decisions

- Default engine: `sing-box`
- Optional engine: `xray`
- WireGuard in V1: WARP outbound mode only; standalone WireGuard public inbound is not exposed
- Lite profile: max 2 protocols
- Lite default protocol: `vless-reality`
- Lite recommended second protocol: `hysteria2`
- Primary targets: Ubuntu, Debian
- Best-effort targets: Alpine Linux, FreeBSD-based Serv00/Hostuno, restricted non-root shells
- Supported CPU architectures: `amd64`/`x86_64`, `arm64`/`aarch64`
- No backward compatibility with old variable names
- Static Web command generator on GitHub Pages
- VPS must not run extra local web panel services by default
- First-start language selection is persisted in one-line settings file (`/etc/sing-box-deve/settings.conf`)

## Firewall Policy

- Strictly incremental firewall changes
- Managed-rule rollback support; rollback restores only rules tracked by `sing-box-deve`, not a full system firewall snapshot
- Idempotent endpoint ownership: repeated installs do not duplicate managed rules for the same backend/proto/port/service, even when `install_id` changes
- Drift self-healing: if a managed record exists but the backend rule is missing, the next apply/replay restores the backend rule
- `fw status` always prints managed records first; backend presence checks are best-effort and skipped when no usable backend is available
- `firewalld` has port/proto ownership granularity only; pre-existing ports are not adopted
- `nftables` backend is best-effort for complex host rulesets; rule presence does not prove end-to-end reachability when other base chains drop traffic
- Absolutely no:
  - `ufw disable`
  - `iptables -F`
  - `iptables -X`
  - `setenforce 0`

## Firewall Backend Selection

1. `ufw` when active
2. `firewalld` when running
3. `iptables` when usable
4. `nftables` when usable

## Scope

- Scenarios: VPS, Serv00/Hostuno, SAP, Workers, GitHub Actions
- Protocol family: vless-reality, vless-ws, vless-xhttp, shadowsocks-2022, naive, hysteria2, tuic, anytls, trojan; WARP/Argo/Psiphon are feature modes, not public inbound protocols

## Platform Support Contract

- Ubuntu/Debian VPS is the primary support path and should be used for release-blocking validation.
- Alpine Linux is supported on a best-effort basis via `apk` dependency installation and OpenRC/nohup service handling.
- FreeBSD support is scoped primarily to Serv00/Hostuno-style non-root or restricted environments.
- Unknown `/etc/os-release` IDs are allowed to continue with a warning, but are not considered supported until validated on a real target host.

## Current V1 Implementation Progress

- VPS runtime implemented with service management and node output generation
- Argo tunnel sidecar implemented (`temp` and `fixed` modes)
- WARP outbound implemented for sing-box (`off`/`global`, key-driven)
- Artifact checksum verification implemented for `sing-box`, `xray`, and `cloudflared`
- Serv00/SAP providers support environment-driven executable deployment flows and generated templates
- Outbound upstream proxy implemented (`direct/socks/http/https`) for egress forwarding
- CI checks added (syntax, shellcheck, examples JSON, checksum manifest consistency)
