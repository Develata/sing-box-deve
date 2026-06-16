# 验收矩阵（V1）

> 本矩阵分为静态验证与实机验证。Ubuntu/Debian VPS 是 release-blocking 路径；Serv00/Hostuno 为 best-effort。

## 1) 组合矩阵范围

- Provider: `vps` / `serv00`
- Profile: `lite` / `full`
- Feature: `argo` / `warp` / `outbound-proxy`

## 2) 当前验收状态

| Provider | Profile | Argo | WARP | Outbound Proxy | 静态验证 | 实机验证 |
|---|---|---|---|---|---|---|
| vps | lite | off | off | direct | 通过 | 待目标机执行 |
| vps | full | temp/fixed | off/global | socks/http/https | 通过 | 待目标机执行 |
| serv00 | lite/full | off/temp/fixed | off | direct/socks/http/https | 通过 | 需凭据执行 |

## 3) 推荐实机验收命令

```bash
sudo ./sing-box-deve.sh install --provider vps --profile lite --engine sing-box --protocols vless-reality --yes
sudo ./sing-box-deve.sh install --provider vps --profile full --engine sing-box --protocols vless-reality,hysteria2 --argo temp --yes
sudo ./sing-box-deve.sh install --provider vps --profile lite --engine sing-box --protocols vless-reality   --outbound-proxy-mode socks --outbound-proxy-host 1.2.3.4 --outbound-proxy-port 1080 --yes
sudo ./sing-box-deve.sh doctor
sudo ./sing-box-deve.sh panel --full
```

## 4) 自动化辅助

- 生成矩阵报告：`bash scripts/acceptance-matrix.sh`
- CI 校验：`.github/workflows/ci.yml`
