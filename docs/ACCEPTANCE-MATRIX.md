# 验收矩阵（V1）

> 本矩阵分为静态验证与实机验证。本轮发布以 Debian VPS 实机验收为门禁；Ubuntu 不在本轮实机验证范围，Serv00/Hostuno 为 best-effort。

## 1) 组合矩阵范围

- Provider: `vps` / `serv00`
- Profile: `lite` / `full`
- Feature: `argo` / `warp` / `outbound-proxy`

## 2) 当前验收状态

| Provider | Profile | Argo | WARP | Outbound Proxy | 静态验证 | 实机验证 |
|---|---|---|---|---|---|---|
| vps | lite | off | off | direct | 通过 | Debian 13 通过 |
| vps | full | temp/fixed | off/global | socks/http/https | 通过 | Debian 13：temp、global、SOCKS 通过；fixed、HTTP/HTTPS 待专项实机验证 |
| serv00 | lite/full | off/temp/fixed | off | direct/socks/http/https | 通过 | 需凭据执行 |

2026-09-11，提交 `f26a317e01b12455c4db82784b9c15042e270e20` 在 Debian 13 systemd VPS 上完成 29 项主路径检查：Lite 安装、Reality 转发、标识轮换与回滚、改端口、Full + 临时 Argo 重装和转发、内核更新、WARP SOCKS5 与全局出口、重启、Xray/sing-box 切换及保留设置卸载。退出码为 0，原部署、受管理防火墙规则及其他服务恢复核验通过。这是预发布 SSH 实机回执；最终发布提交的回执随 Release 资产提供。

## 3) 推荐实机验收命令

```bash
sudo ./sing-box-deve.sh install --provider vps --profile lite --engine sing-box --protocols vless-reality --yes
sudo ./sing-box-deve.sh install --provider vps --profile full --engine sing-box --protocols vless-reality,vless-ws --argo temp --yes
sudo ./sing-box-deve.sh install --provider vps --profile lite --engine sing-box --protocols vless-reality   --outbound-proxy-mode socks --outbound-proxy-host 1.2.3.4 --outbound-proxy-port 1080 --yes
sudo ./sing-box-deve.sh doctor
sudo ./sing-box-deve.sh panel --full
```

## 4) 自动化辅助

- 生成矩阵报告：`bash scripts/acceptance-matrix.sh`
- CI 和 Full Regression：统一执行 `scripts/sing-box-deve-pre-push.sh`
- 实机流量/生命周期：通过 SSH 执行 `scripts/primary-vps-acceptance.sh`；自托管 runner workflow 为可选方式。
- Release gate：核对最终 source SHA、干净源码、Debian SSH 实机成功回执、原部署恢复结果和运行包 SHA256；静态检查或真实内核回环测试不能替代生命周期验收。Ubuntu 不计入本轮通过结论。
