# sing-box-deve V1 Specification

## Confirmed Decisions

- Default engine: `sing-box`
- Compatibility engine: `xray`
- Primary target: Ubuntu/Debian VPS
- Best-effort target: Serv00/Hostuno-style restricted shell
- WireGuard in V1: WARP outbound mode only; standalone WireGuard public inbound is not exposed
- Lite profile: max 2 protocols
- Lite default protocol: `vless-reality`
- Lite recommended second protocol: `hysteria2`
- Supported CPU architectures: `amd64`/`x86_64`, `arm64`/`aarch64`
- VPS must not run extra local web panel services by default

## Core Ontology

The project manages six objects: host, runtime, public inbounds, outbounds, generated artifacts, and safety state. Features outside this ontology are pruned from the mainline.

## Firewall Policy

- Strictly incremental firewall changes
- Managed-rule rollback support; rollback restores only rules tracked by `sing-box-deve`, not a full system firewall snapshot
- Idempotent endpoint ownership: repeated installs do not duplicate managed rules for the same backend/proto/port/service
- Drift self-healing: if a managed record exists but the backend rule is missing, the next apply/replay restores the backend rule
- `fw status` always prints managed records first; backend presence checks are best-effort and skipped when no usable backend is available
- `firewalld` has port/proto ownership granularity only; pre-existing ports are not adopted
- `nftables` backend is best-effort for complex host rulesets
- Absolutely no `ufw disable`, `iptables -F`, `iptables -X`, `setenforce 0`

## Firewall Backend Selection

1. `ufw` when active
2. `firewalld` when running
3. `iptables` when usable
4. `nftables` when usable

## Scope

- Scenarios: VPS, Serv00/Hostuno
- Public inbound protocols: `vless-reality`, `vless-ws`, `vless-xhttp` (xray compatibility), `shadowsocks-2022`, `naive`, `hysteria2`, `tuic`
- Feature modes: Argo and WARP outbound
- Pruned from mainline: SAP, Workers, Psiphon, SFW packaging, GitLab/TG subscription push, jump, set-share, set-port-egress, anytls, trojan

## Platform Support Contract

- Ubuntu/Debian VPS is the release-blocking validation path.
- Alpine Linux is best-effort via `apk` and OpenRC/nohup service handling.
- FreeBSD support is scoped primarily to Serv00/Hostuno-style restricted environments.
- Unknown `/etc/os-release` IDs may continue with a warning but are not considered supported until validated on a real target host.

## Current V1 Implementation Progress

- VPS runtime implemented with service management and node output generation
- Argo tunnel sidecar implemented (`temp` and `fixed` modes)
- WARP outbound implemented for sing-box/xray routing modes
- Artifact checksum verification implemented for `sing-box`, `xray`, and `cloudflared`
- Serv00 provider supports environment-driven executable deployment flow
- Outbound upstream proxy implemented (`direct/socks/http/https`)
- CI checks include syntax, shellcheck, examples JSON, checksum manifest consistency, CLI smoke, and firewall record tests
