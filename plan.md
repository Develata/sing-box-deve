# sing-box-deve 计划文档（瘦身后主线）

## 1) 项目本体

`sing-box-deve` 管理六类对象：host、runtime、public inbounds、outbounds、artifacts、safety state。主线只保留直接服务这些对象的能力。

## 2) 保留能力

- 安装/重装：`wizard`, `install`, `apply -f`, `apply --runtime`
- 状态：`panel`, `list`, `doctor`, `logs`, `restart`
- 协议：`vless-reality`, `vless-ws`, `vless-xhttp`(xray compatibility), `shadowsocks-2022`, `naive`, `hysteria2`, `tuic`
- 端口：`set-port`, `mport`
- 出站：`set-egress`, `set-route`, `split3`
- 特性：Argo, WARP outbound
- 订阅：`sub refresh/show/rules-update`
- 安全：firewall managed rules, cfg snapshots/rollback, update checksums

## 3) 已裁剪能力

- SAP Cloud Foundry provider
- Workers templates
- Psiphon sidecar
- SFW Windows client packaging
- GitLab/TG subscription push
- jump port redirect
- set-share endpoint rewriting
- set-port-egress per-port outbound policy
- `anytls` / `trojan` public inbound

## 4) 验收标准

1. `help` 不出现已裁剪命令。
2. `protocol matrix` 不出现已裁剪协议。
3. `install --dry-run --provider vps --profile lite --engine sing-box --protocols vless-reality` 不写持久状态。
4. `bash -n`, shellcheck, CLI smoke, consistency, firewall-record tests, checksum verification 全部通过。
5. root 实机验证覆盖 VPS lite baseline、VPS full + Argo、WARP、上游代理、Serv00 best-effort。
