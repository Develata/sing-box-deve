# sing-box-deve

`sing-box-deve` 是一个以安全为优先、支持交互与自动化的代理/VPN 一键部署工具箱。

GitHub：`https://github.com/Develata/sing-box-deve`

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Ubuntu%20%7C%20Debian-blue)](docs/V1-SPEC.md)

## 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Develata/sing-box-deve/main/sing-box-deve.sh) wizard
```

或者本地克隆后运行：

```bash
git clone https://github.com/Develata/sing-box-deve.git
cd sing-box-deve
chmod +x ./sing-box-deve.sh
./sing-box-deve.sh wizard
```

## 核心特性

- 多场景支持：VPS、Serv00/Hostuno、SAP、Docker、Workers、GitHub Actions
- 双模式：交互向导 + 配置文件/环境变量自动化
- 安全默认：仅增量防火墙规则，支持回滚
- 小内存友好：默认 Lite 档位，面向 512MB 服务器
- 首启可选中文/English，后续持久化保存

## 当前实现状态

- 已实现 VPS 运行时安装：`sing-box` / `xray` 内核、配置生成、systemd 管理、节点输出
- 已实现 Argo sidecar（临时/固定隧道）
- 已实现 WARP 出站（global 模式）
- 已实现脚本版本显示与更新（脚本自身 + 核心）
- 已实现校验清单驱动的脚本安全更新（`checksums.txt`）

VPS 已支持协议：

- `sing-box`：`vless-reality`、`vmess-ws`、`vless-ws`、`shadowsocks-2022`、`hysteria2`、`tuic`、`trojan`、`wireguard`、`argo`、`anytls`、`any-reality`、`warp`
- `xray`：`vless-reality`、`vmess-ws`、`vless-ws`、`vless-xhttp`、`trojan`、`argo`

补充能力：

- 支持“上游出站代理”模式（`direct/socks/http/https`），用于让 `vless+reality` 等入站流量通过上游代理转发出去（不是额外暴露本地 socks/http 入口）

示例（通过上游 socks 转发出站）：

```bash
./sing-box-deve.sh install --provider vps --profile lite --engine sing-box --protocols vless-reality \
  --outbound-proxy-mode socks --outbound-proxy-host 1.2.3.4 --outbound-proxy-port 1080 \
  --outbound-proxy-user demo --outbound-proxy-pass demo
```

说明：该模式不会额外开放本地 socks/http 入站端口，仅改变服务器出站路径。

## 交互原则

- 每个关键步骤先说明用途与影响，再让用户 `Y/n` 决定
- 支持一直回车使用默认推荐值
- 支持 `--yes` 非交互自动确认

## 设置持久化

设置使用单行配置保存于：`/etc/sing-box-deve/settings.conf`

当前键：

- `lang`（`zh` / `en`）
- `auto_yes`（`true` / `false`）
- `update_channel`（默认 `stable`）

管理命令：

```bash
./sing-box-deve.sh settings show
./sing-box-deve.sh settings set lang zh
./sing-box-deve.sh settings set lang=en auto_yes=true update_channel=stable
```

## 常用命令

```bash
./sing-box-deve.sh wizard
./sing-box-deve.sh install --provider vps --profile lite --engine sing-box --protocols vless-reality
./sing-box-deve.sh apply -f ./config.env
./sing-box-deve.sh list
./sing-box-deve.sh doctor
./sing-box-deve.sh version
./sing-box-deve.sh update
./sing-box-deve.sh update --script
./sing-box-deve.sh update --core
```

## 示例文件

可直接参考并复制修改：

- `examples/vps-lite.env`
- `examples/vps-full-argo.env`
- `examples/docker.env`
- `examples/settings.conf`
- `examples/serv00-accounts.json`
- `examples/sap-accounts.json`

验收矩阵脚本：

- `scripts/acceptance-matrix.sh`
- 运行：`bash scripts/acceptance-matrix.sh`

## Provider 说明

- `serv00`：支持单账号和批量 JSON 远程引导
- `sap`：支持单账号和批量 JSON 部署（CF CLI）
- `docker`：生成并可执行 `docker-compose` 部署

详细文档：

- `docs/README.md`（文档总索引）
- `docs/Serv00.md`
- `docs/SAP.md`
- `docs/Docker.md`
- `docs/CONVENTIONS.md`（命名与目录规范）
- `docs/ACCEPTANCE-MATRIX.md`（验收矩阵）

自动化与保活模板：

- `.github/workflows/main.yml`（手动保活）
- `.github/workflows/mainh.yml`（定时仅保活）
- `.github/workflows/ci.yml`（语法、shellcheck、示例校验、checksums 校验）
- `workers/_worker.js`（反代模板）
- `workers/workers_keep.js`（Workers 定时保活模板）

## 安全承诺

- 不执行 `ufw disable`
- 不执行 `iptables -F` / `iptables -X`
- 不执行 `setenforce 0`
- 仅管理本工具新增规则，并支持回滚

## 路线图

- 持续增强 Serv00/SAP/Docker 的回滚与校验细节
- 增加更多协议专项诊断与压测辅助
- 完善 CI 与示例覆盖

## 版本记录

- 变更记录见 `CHANGELOG.md`

## 致谢

- 本项目在设计与部署经验上参考了：`yonggekkk/sing-box-yg`、`yonggekkk/argosbx`
- 感谢上游社区：`SagerNet/sing-box`、`XTLS/Xray-core`、`cloudflare/cloudflared`

## 贡献

欢迎提交 Issue / PR，详见 `CONTRIBUTING.md`。

## 许可证

本项目采用 MIT 协议开源，见 `LICENSE`。
