# 实机验收执行单

本轮自动化主路径：在 disposable Debian systemd VM 上运行，项目运行目录必须为空；临时使用已有部署的主机时，先取得替换授权并核验备份，测试结束后恢复原部署：

```bash
sudo SBD_DISPOSABLE_ACCEPTANCE=yes bash scripts/primary-vps-acceptance.sh /tmp/sbd-acceptance
```

也可手动触发 `Primary VPS Acceptance` workflow。它使用 Debian 目标机，执行真实生命周期及客户端流量检查；本地 mock 或 current-core 配置测试不能替代其 receipt。配置与运行边界见 [RELIABILITY.md](RELIABILITY.md)。Ubuntu 不在本轮实机验证范围。

以下是补充人工验收项。目标：覆盖 `VPS/Serv00 × Lite/Full × Argo/WARP/上游代理` 的关键组合。

## 0) 基线准备

```bash
sudo ./sing-box-deve.sh version
sudo ./sing-box-deve.sh doctor
sudo ./sing-box-deve.sh panel --full
```

PASS：`doctor` 无 fatal error，版本可显示。

## 1) VPS Lite 基线

```bash
sudo ./sing-box-deve.sh install --provider vps --profile lite --engine sing-box --protocols vless-reality --yes
sudo ./sing-box-deve.sh panel --full
sudo ./sing-box-deve.sh list --all
sudo ./sing-box-deve.sh apply --runtime
```

PASS：核心服务 running，节点文件生成，端口监听检查通过。

## 2) VPS Full + Argo

```bash
sudo ./sing-box-deve.sh install --provider vps --profile full --engine sing-box --protocols vless-reality,vless-ws --argo temp --yes
sudo ./sing-box-deve.sh panel --full
sudo ./sing-box-deve.sh doctor
```

PASS：Argo sidecar 可启动，节点包含 Argo 入口。

## 3) VPS 上游出站代理

```bash
sudo ./sing-box-deve.sh install --provider vps --profile lite --engine sing-box --protocols vless-reality   --outbound-proxy-mode socks --outbound-proxy-host <host> --outbound-proxy-port <port>   --outbound-proxy-user <user> --outbound-proxy-pass <pass> --yes
sudo ./sing-box-deve.sh panel --full
sudo ./sing-box-deve.sh doctor
```

PASS：panel 中 Egress 为 socks/http/https，配置字段生效。

## 4) WARP

```bash
sudo WARP_PRIVATE_KEY=<key> WARP_PEER_PUBLIC_KEY=<peer> ./sing-box-deve.sh install --provider vps --profile full --engine sing-box --protocols vless-reality --warp-mode global --yes
sudo ./sing-box-deve.sh restart --all
```

PASS：安装成功且 panel 显示 WARP global。

## 5) Serv00

```bash
export SERV00_HOST=<host>
export SERV00_USER=<user>
export SERV00_PASS=<pass>
sudo ./sing-box-deve.sh install --provider serv00 --profile lite --engine sing-box --protocols vless-reality
```

批量：

```bash
export SERV00_ACCOUNTS_JSON="$(cat examples/serv00-accounts.json)"
export SERV00_RETRY_COUNT=1
sudo ./sing-box-deve.sh install --provider serv00 --profile full --engine sing-box --protocols vless-reality
```

PASS：summary 正确，失败项有清晰提示。

## 6) 更新与防火墙

```bash
sudo ./sing-box-deve.sh update --core --yes
sudo ./sing-box-deve.sh fw status
sudo ./sing-box-deve.sh panel --full
```

PASS：core 更新成功，防火墙规则仍可追踪。

## 最终验收结论模板

```text
环境：<OS/内存/架构>
场景覆盖：VPS[PASS] Serv00[PASS/FAIL]
功能覆盖：Lite[PASS] Full[PASS] Argo[PASS] WARP[PASS] 上游代理[PASS]
安全检查：防火墙增量[PASS] 回滚[PASS] 更新校验[PASS]
结论：<可发布/需修复后发布>
```
