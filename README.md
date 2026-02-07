# sing-box-deve

`sing-box-deve` 是一个以安全为优先、支持交互与自动化的代理/VPN 一键部署工具箱。

GitHub：`https://github.com/Develata/sing-box-deve`

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Ubuntu%20%7C%20Debian-blue)](docs/V1-SPEC.md)

## 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Develata/sing-box-deve/main/sing-box-deve.sh) wizard
```

说明：远程一键模式会自动拉取完整项目再执行，不再依赖 `/dev/fd` 临时路径下存在 `lib/` 目录。

或者本地克隆后运行：

```bash
git clone https://github.com/Develata/sing-box-deve.git
cd sing-box-deve
chmod +x ./sing-box-deve.sh
./sing-box-deve.sh wizard
```

## 三分钟上手（推荐）

```bash
# 1) 远程一键安装（推荐）
sudo bash <(curl -fsSL https://raw.githubusercontent.com/Develata/sing-box-deve/main/sing-box-deve.sh) wizard

# 2) 用 sb 打开面板
sb

# 3) 查看节点与诊断
sb list --nodes
sudo sb doctor
```

## 先看这里（90% 用户）

- 推荐直接用 `wizard` 安装，默认选 `vps + lite + sing-box + vless-reality`
- 安装后常用就是 4 个命令：`panel`、`doctor`、`list --nodes`、`restart --core`
- 需要交互控制台时直接输入 `sb`
- 如果只想稳定使用，可先跳过 Serv00/SAP/Docker/Workers 等进阶章节

最常用命令：

```bash
./sing-box-deve.sh wizard
./sing-box-deve.sh panel --full
./sing-box-deve.sh doctor
./sing-box-deve.sh list --nodes
```

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

默认情况下无需启用任何 keepalive workflow（`main.yml` / `mainh.yml`）。

基础流程：

```bash
./sing-box-deve.sh wizard
./sing-box-deve.sh install --provider vps --profile lite --engine sing-box --protocols vless-reality
./sing-box-deve.sh apply -f ./config.env
./sing-box-deve.sh apply --runtime
```

查看与诊断：

```bash
./sing-box-deve.sh list --all
./sing-box-deve.sh list --settings
./sing-box-deve.sh panel --full
./sing-box-deve.sh status
./sing-box-deve.sh list --nodes
./sing-box-deve.sh list --runtime
./sing-box-deve.sh doctor
./sing-box-deve.sh logs --core
```

运行管理：

```bash
./sing-box-deve.sh restart --all
./sing-box-deve.sh restart --core
./sing-box-deve.sh restart --argo
./sing-box-deve.sh logs --argo
./sing-box-deve.sh set-port --list
./sing-box-deve.sh set-port --protocol vless-reality --port 443
./sing-box-deve.sh set-egress --mode socks --host 1.2.3.4 --port 1080 --user demo --pass demo
./sing-box-deve.sh set-route cn-direct
./sing-box-deve.sh set-share direct 1.2.3.4:443,1.2.3.4:8443
./sing-box-deve.sh set-share proxy 9.9.9.9:443,9.9.9.9:2053
./sing-box-deve.sh regen-nodes
```

服务器验证建议：优先使用 `sb` 面板完成安装、分流、端口和节点刷新操作；命令模式仅用于自动化。

版本与更新：

```bash
./sing-box-deve.sh uninstall --keep-settings
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

## 进阶与实现细节（可后看）

- 已实现 VPS 运行时安装：`sing-box` / `xray` 内核、配置生成、systemd 管理、节点输出
- 已实现 Argo sidecar（临时/固定隧道）
- 已实现 WARP 出站（global 模式）
- 已实现脚本版本显示与更新（脚本自身 + 核心）
- 已实现校验清单驱动的脚本安全更新（`checksums.txt`）
- 已完成脚本模块化重构：`lib/common.sh`、`lib/providers.sh`、`lib/menu.sh`、`sing-box-deve.sh` 均为聚合入口
- 项目约束：所有 `.sh` 单文件不超过 250 行，并在 CI 中强制校验

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

VPN 分流模式（新增）：

- `direct`：全部直连
- `global-proxy`：全部走上游代理/WARP
- `cn-direct`：中国流量直连，其他走上游代理/WARP
- `cn-proxy`：中国流量走上游代理/WARP，其他直连

设置示例：

```bash
./sing-box-deve.sh set-route cn-direct
```

兼容上游变量模式（对齐 `sing-box-yg/argosbx` 常用写法）：

```bash
vmpt=8443 argo=vmpt bash <(curl -fsSL https://raw.githubusercontent.com/Develata/sing-box-deve/main/sing-box-deve.sh)
```

## Provider 说明

- `serv00`：支持单账号和批量 JSON 远程引导
- `sap`：支持单账号和批量 JSON 部署（CF CLI）
- `docker`：生成并可执行 `docker-compose` 部署

VPS 安装后快捷命令：

- 直接输入 `sb` 可启动交互菜单控制台
- `sb <子命令>` 可直接透传到 `sing-box-deve.sh`

示例：

```bash
sb
sb list --nodes
sb restart --core
sb set-port --list
```

详细文档：

- `docs/README.md`（文档总索引）
- `docs/Serv00.md`
- `docs/SAP.md`
- `docs/Docker.md`
- `docs/CONVENTIONS.md`（命名与目录规范）
- `docs/ACCEPTANCE-MATRIX.md`（验收矩阵）
- `docs/PANEL-TEMPLATE.md`（面板输出中英文模板）
- `docs/REAL-WORLD-VALIDATION.md`（实机验收执行单）

自动化与保活模板：

- 说明：以下均为**可选模板**，默认部署不依赖它们
- `.github/workflows/main.yml`（手动保活）
- `.github/workflows/mainh.yml`（手动保活模板 2）
- `.github/workflows/ci.yml`（语法、shellcheck、示例校验、checksums 校验）
- `workers/_worker.js`（反代模板）
- `workers/workers_keep.js`（Workers 定时保活模板）

发布前建议：

- 执行 `bash scripts/update-checksums.sh` 更新 `checksums.txt`
- 再执行 `./sing-box-deve.sh update --script` 的安全更新链路验证

## 常见问题

- `mainh.yml` 会自动运行吗？
  - 不会。当前仅支持手动触发（`workflow_dispatch`），默认不依赖。
- 为什么 `doctor` 提示请用 root？
  - 安装、服务、端口、防火墙诊断都需要 root 权限。
- `set-port` 为什么先要 `--list`？
  - 先看白名单和当前端口，避免修改到不支持协议。

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
