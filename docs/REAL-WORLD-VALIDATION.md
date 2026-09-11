# 实机验收执行单

本轮自动化主路径：在 disposable Debian systemd VM 上运行，项目运行目录必须为空；临时使用已有部署的主机时，先取得替换授权并核验备份，测试结束后恢复原部署：

```bash
sudo SBD_DISPOSABLE_ACCEPTANCE=yes bash scripts/primary-vps-acceptance.sh /tmp/sbd-acceptance
```

上述命令通过已核验主机密钥的 SSH 连接执行，无需安装 Actions runner。源码应固定到最终发布提交，报告目录位于 checkout 之外且不能复用。也可手动触发可选的 `Primary VPS Acceptance` workflow；本地 mock 或 current-core 配置测试不能替代实机 receipt。配置与运行边界见 [RELIABILITY.md](RELIABILITY.md)。Ubuntu 不在本轮实机验证范围。

## SSH 验收与发布门禁

1. 完成源码修改、校验和更新、完整 pre-push 检查和提交，固定最终 SHA；源码变化后重新验收。
2. 通过 SSH 在授权目标机核验该 SHA 和干净 checkout，验证原部署备份，启动独立于 SSH 会话的限时验收及失败恢复监督进程，再运行上述脚本。
3. 监督进程恢复原部署，核验原文件/配置、防火墙和服务状态，写出恢复成功回执。恢复失败不得发布。
4. 从目标机取得 `receipt.json`，构造下面的脱敏发布回执；运行包用同一源码的 `runtime-archive.py pack` 构建，核对本地与目标机的包摘要。原始日志、备份路径、凭据和节点链接不得放入回执。
5. 验证回执，再通过 `gh workflow run release.yml --ref main --json` 提交输入对象 `{"acceptance_receipt":"<完整回执 JSON 字符串>"}`。工作流会重建运行包并核对摘要；main 必须仍指向验收 SHA。

发布回执 schema 1 字段：

| 字段 | 要求 |
|---|---|
| `schema` / `transport` | `1` / `"ssh"` |
| `source_sha` | 最终发布提交的完整 SHA |
| `runtime_sha256` | 待发布 `sing-box-deve-runtime.tar.gz` 的 SHA256 |
| `acceptance` | 脚本生成的完整 `receipt.json`；必须 Debian、success、complete、退出码 0、源码保持干净且有通过用例 |
| `restoration.result` / `restoration.source_sha` | `"success"` / 同一最终 SHA |
| `restoration.finished_at` | 含时区的 ISO 时间，不能早于验收结束 |
| `restoration.original_deployment_restored` | 原部署文件与运行状态已恢复，布尔 `true` |
| `restoration.managed_firewall_restored` | 受管理防火墙规则已恢复，布尔 `true` |
| `restoration.protected_services_restored` | 其他服务状态已核验，布尔 `true` |
| `restoration.protected_config_unchanged` | 受保护配置已核验未变，布尔 `true` |
| `restoration.backup_verified` | 原部署备份完整性已核验，布尔 `true` |

所有字段均必填，不接受额外字段、重复 JSON key 或字符串形式的布尔值。一次性空白主机也应由监督进程验证其原始空白状态得到恢复。

```bash
python3 scripts/runtime-archive.py pack . /tmp/sing-box-deve-runtime.tar.gz
python3 scripts/verify-release-receipt.py /tmp/ssh-acceptance.json . /tmp/sing-box-deve-runtime.tar.gz
```

回执由可信维护者从 SSH 验收和恢复证据生成；JSON 校验不构成独立签名。发布后检查 workflow 结果、tag 对应提交及下载资产摘要。不要在仓库内提交本次回执再沿用旧 SHA，这会改变最终提交。

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
