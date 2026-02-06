# 验收矩阵（V1）

> 说明：本矩阵分为两层结果：
> - 静态验证（语法、参数、配置生成、校验逻辑）
> - 实机验证（需要 root、真实网络与凭据）

## 1) 组合矩阵范围

- Provider: `vps` / `serv00` / `sap` / `docker`
- Profile: `lite` / `full`
- Feature: `argo` / `warp` / `outbound-proxy`

## 2) 当前验收状态

| Provider | Profile | Argo | WARP | Outbound Proxy | 静态验证 | 实机验证 |
|---|---|---|---|---|---|---|
| vps | lite | off | off | direct | 通过 | 待目标机执行 |
| vps | full | temp/fixed | off/global | socks/http/https | 通过 | 待目标机执行 |
| serv00 | lite/full | off/temp/fixed | off | direct/socks/http/https | 通过 | 需凭据执行 |
| sap | lite/full | off/temp/fixed | off | direct/socks/http/https | 通过 | 需 CF 凭据执行 |
| docker | lite/full | off/temp/fixed | off/global | direct/socks/http/https | 通过 | 需 Docker 环境执行 |

## 3) 推荐实机验收命令

```bash
# VPS lite baseline
sudo ./sing-box-deve.sh install --provider vps --profile lite --engine sing-box --protocols vless-reality --yes

# VPS full + argo
sudo ./sing-box-deve.sh install --provider vps --profile full --engine xray --protocols vless-reality,vmess-ws,argo --argo temp --yes

# VPS egress via upstream socks
sudo ./sing-box-deve.sh install --provider vps --profile lite --engine sing-box --protocols vless-reality \
  --outbound-proxy-mode socks --outbound-proxy-host 1.2.3.4 --outbound-proxy-port 1080 --yes

# Run diagnostics
sudo ./sing-box-deve.sh doctor
```

## 4) 自动化辅助

- 生成矩阵报告：`bash scripts/acceptance-matrix.sh`
- CI 校验：`.github/workflows/ci.yml`
