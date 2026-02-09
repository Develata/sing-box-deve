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

- 推荐直接用 `wizard` 安装：
  - `sing-box` 默认 `vless-reality,hysteria2`
  - `xray` 默认 `vless-reality,vmess-ws`
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
./sing-box-deve.sh split3 set cn.example.com,qq.com google.com,youtube.com ads.example.com
./sing-box-deve.sh jump set vless-reality 443 8443,2053,2083
./sing-box-deve.sh regen-nodes
```

订阅与客户端产物：

```bash
./sing-box-deve.sh sub refresh
./sing-box-deve.sh sub show
./sing-box-deve.sh sub rules-update
./sing-box-deve.sh sub gitlab-set <token> <group/project> [branch] [path]
./sing-box-deve.sh sub gitlab-push
./sing-box-deve.sh sub tg-set <bot_token> <chat_id>
./sing-box-deve.sh sub tg-push
```

面板已内置“订阅与分享”菜单，可直接完成刷新、GitLab 推送、TG 推送等操作。

订阅刷新后会额外生成：

- 四合一聚合原始链接：`/opt/sing-box-deve/data/jhdy.txt`
- 四合一聚合 base64：`/opt/sing-box-deve/data/jh_sub.txt`
- 客户端分组链接：`/opt/sing-box-deve/data/share-groups/*.txt`（v2rayn/v2rayng/nekobox/shadowrocket/singbox）
- clash-meta 建议使用：`/opt/sing-box-deve/data/clash_meta_client.yaml`
- clash 自定义规则文件：`/etc/sing-box-deve/clash_custom_rules.list`
- clash 本地规则集目录：`/opt/sing-box-deve/data/clash-ruleset/`
- 仓库内置规则源：`rulesets/clash/geosite-cn.yaml`、`rulesets/clash/geoip-cn.yaml`

配置变更中心与系统工具（面板同样可操作）：

```bash
./sing-box-deve.sh cfg preview <action> ...
./sing-box-deve.sh cfg apply <action> ...
./sing-box-deve.sh cfg rollback [snapshot_id|latest]
./sing-box-deve.sh cfg snapshots list
./sing-box-deve.sh cfg snapshots prune [keep_count]
./sing-box-deve.sh cfg rotate-id
./sing-box-deve.sh cfg argo off|temp|fixed [token] [domain]
./sing-box-deve.sh cfg ip-pref auto|v4|v6
./sing-box-deve.sh cfg cdn-host <domain>
./sing-box-deve.sh cfg domain-split <direct_csv> <proxy_csv> <block_csv>
./sing-box-deve.sh cfg tls self-signed|acme|acme-auto [cert_path|domain] [key_path|email] [dns_provider]
./sing-box-deve.sh cfg rebuild
./sing-box-deve.sh cfg protocol-add <proto_csv> [random|manual] [proto:port,...]
./sing-box-deve.sh cfg protocol-remove <proto_csv>
./sing-box-deve.sh kernel show
./sing-box-deve.sh kernel set sing-box v1.12.20
./sing-box-deve.sh warp status
./sing-box-deve.sh sys bbr-enable
./sing-box-deve.sh protocol matrix
./sing-box-deve.sh protocol matrix --enabled
```

服务器验证建议：优先使用 `sb` 面板完成安装、分流、端口和节点刷新操作；命令模式仅用于自动化。

版本与更新：

```bash
./sing-box-deve.sh uninstall --keep-settings
./sing-box-deve.sh version
./sing-box-deve.sh update
./sing-box-deve.sh update --script
./sing-box-deve.sh update --core
./sing-box-deve.sh update --script --source primary
./sing-box-deve.sh update --script --source backup
```

`update --source` 说明：

- `auto`：先主源，失败自动回退到备源
- `primary`：只使用主源
- `backup`：只使用备源

## 详细使用指南（按实际运维流程）

下面这套流程按“首次安装 -> 日常维护 -> 故障处理”编排，直接照做即可。

### 1) 首次安装（推荐走向导）

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/Develata/sing-box-deve/main/sing-box-deve.sh) wizard
```

安装完成后：

```bash
sb
```

进入面板后，建议先看：

1. `2 状态与节点查看`
2. `3 端口管理`
3. `11 订阅与分享`
4. `12 配置变更中心`

### 2) 主菜单 1-13 的实际用途

1. `安装/重装`：首次安装或按新参数整体重建。
2. `状态与节点查看`：看运行状态、节点、协议能力矩阵。
3. `端口管理`：查看或修改协议端口，自动加放行规则（不删历史规则）。
4. `出站策略管理`：配置 `direct/socks/http/https`、路由模式、分享出口、按端口出站策略。
5. `服务管理`：重启核心/Argo、重建节点、看日志。
6. `更新管理`：更新脚本和核心，支持主源/备源切换。
7. `防火墙管理`：看托管规则、回滚快照、重放规则。
8. `设置管理`：语言和自动确认。
9. `日志查看`：核心日志/Argo 日志。
10. `卸载管理`：保留设置卸载或完全卸载。
11. `订阅与分享`：刷新订阅、显示分组、生成二维码、推送 GitLab/TG。
12. `配置变更中心`：`preview/apply/rollback/snapshots` 闭环运维。
13. `内核与WARP`：内核切换、WARP、BBR、证书工具链。

### 3) 端口与协议管理

先看当前端口：

```bash
sb set-port --list
```

修改协议端口：

```bash
sb set-port --protocol vless-reality --port 52440
```

说明：

- 会自动校验端口范围与协议合法性。
- 会自动放行新端口对应防火墙规则。
- 不会粗暴删除历史防火墙规则。

### 4) 出站策略管理（普通出站）

切换到直连：

```bash
sb set-egress --mode direct
```

切到上游 socks：

```bash
sb set-egress --mode socks --host 1.2.3.4 --port 1080 --user demo --pass demo
```

路由模式：

```bash
sb set-route direct
sb set-route global-proxy
sb set-route cn-direct
sb set-route cn-proxy
```

### 5) 按端口走不同出站策略（新功能）

查看当前映射：

```bash
sb set-port-egress --list
```

设置映射（格式：`端口:direct|proxy|warp`）：

```bash
sb set-port-egress --map 443:direct,8443:proxy,9443:warp
```

清空映射：

```bash
sb set-port-egress --clear
```

规则说明：

- 仅允许映射到当前已存在的入站端口。
- `proxy` 需要当前配置里存在 `proxy-out`。
- `warp` 需要当前配置里存在 `warp-out`。
- 端口映射规则优先于常规路由/域名分流规则。

### 6) 配置中心闭环（推荐日常变更都走这里）

先预览再应用：

```bash
sb cfg preview protocol-add vmess-ws random
sb cfg apply protocol-add vmess-ws random
```

快照查看与回滚：

```bash
sb cfg snapshots list
sb cfg rollback latest
sb cfg snapshots prune 10
```

### 7) 订阅与分享产物怎么用

刷新产物：

```bash
sb sub refresh
sb sub show
```

关键文件：

- 聚合 base64：`/opt/sing-box-deve/data/jh_sub.txt`
- 原始聚合：`/opt/sing-box-deve/data/jhdy.txt`
- 客户端分组：`/opt/sing-box-deve/data/share-groups/*.txt`
- `clash-meta` 配置：`/opt/sing-box-deve/data/clash_meta_client.yaml`

重要说明：

- `clash-meta` 默认是 **YAML 文件**，不是通用节点 URL。
- `share-groups/clash-meta.txt` 里保存的是 yaml 路径提示。
- 如果执行 `sb sub gitlab-push`，会得到远程 raw 的 yaml 链接用于导入。
- clash YAML 会内置一套规则（局域网直连、基础广告拦截、CN 规则直连）。
- 规则文件随仓库一起提交；`sb sub refresh` 只会把仓库内置规则复制到本地运行目录，不依赖远端下载。
- 当你更新仓库内规则文件后，执行 `sb sub rules-update` 可强制重新同步到运行目录。
- 你也可在 `/etc/sing-box-deve/clash_custom_rules.list` 每行追加一条规则，然后执行 `sb sub refresh` 重新生成。

### 8) 更新机制与正确操作

先看版本：

```bash
sb version
```

更新脚本：

```bash
sb update --script --source primary
```

更新失败排查顺序：

1. 先试主源：`sb update --script --source primary`
2. 再试备源：`sb update --script --source backup`
3. 若报 `Checksum mismatch`，优先检查仓库 `checksums.txt` 是否已随最新改动更新并推送
4. 若刚推送仓库，建议稍等再更新（CDN 缓存短暂不一致时会失败）

### 9) 卸载与重装

保留设置卸载：

```bash
sb uninstall --keep-settings
```

完全卸载：

```bash
sb uninstall
```

若你要“干净重装”，建议顺序：

1. `sb uninstall`
2. 重新执行 `wizard`
3. `sb panel --full` 检查状态

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
- `scripts/integration-smoke.sh`（root + systemd 实机冒烟回归）
- `scripts/consistency-check.sh`（配置与节点端口/路径一致性检查）
- `scripts/regression-docker.sh`（Docker 模拟回归：首次安装干跑、协议增删、回滚、doctor）
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

Provider 快捷入口（已实现，不再是占位）：

```bash
./providers/vps.sh install --profile lite --engine sing-box --protocols vless-reality --yes
./providers/serv00.sh install --profile full --engine xray --protocols vless-reality,vmess-ws,argo --yes
./providers/sap.sh install --profile lite --engine sing-box --protocols vless-reality --yes
./providers/docker.sh install --profile lite --engine sing-box --protocols vless-reality --yes
```

高级协议参数（对齐 argosbx 风格）：

- Reality/TLS：`REALITY_SERVER_NAME`、`REALITY_FINGERPRINT`、`REALITY_HANDSHAKE_PORT`、`TLS_SERVER_NAME`
- WS/XHTTP：`VMESS_WS_PATH`、`VLESS_WS_PATH`、`VLESS_XHTTP_PATH`、`VLESS_XHTTP_MODE`
- Xray ENC：`XRAY_VLESS_ENC=true`、`XRAY_XHTTP_REALITY=true`
- 细粒度 CDN/ProxyIP：`CDN_HOST_VMESS`、`CDN_HOST_VLESS_WS`、`CDN_HOST_VLESS_XHTTP`、`PROXYIP_VMESS`、`PROXYIP_VLESS_WS`、`PROXYIP_VLESS_XHTTP`

示例（xray + vless enc + xhttp/ws 细粒度）：

```bash
XRAY_VLESS_ENC=true \
REALITY_SERVER_NAME=apple.com \
VMESS_WS_PATH=/my-vm \
VLESS_WS_PATH=/my-vl \
VLESS_XHTTP_PATH=/my-xh \
CDN_HOST_VMESS=cdn-a.example.com \
CDN_HOST_VLESS_WS=cdn-b.example.com \
PROXYIP_VLESS_XHTTP=203.0.113.10 \
./sing-box-deve.sh install --provider vps --profile full --engine xray --protocols vless-reality,vmess-ws,vless-ws,vless-xhttp --yes
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

## 运维闭环手册

推荐日常巡检顺序：

1. `sb panel --full`
2. `sb doctor`
3. `sb cfg snapshots list`
4. `sb fw status`

常见问题与处理：

1. 端口冲突/端口未监听
   - 执行：`sb doctor`
   - 若提示端口冲突：`sb set-port --protocol <协议> --port <新端口>`
   - 若首次新增协议：`sb cfg protocol-add <协议> random` 或手动映射端口

2. 证书签发失败或即将到期
   - 安装 acme：`sb sys acme-install`
   - 自动签发：`sb cfg tls acme-auto <domain> <email> [dns_provider]`
   - 复用已签证书：脚本会自动检测并优先复用同域名/泛域名证书
   - `sb panel --full` 与 `sb doctor` 会给出到期预警（30/15/7 天）

3. 订阅为空或产物缺失
   - 刷新产物：`sb sub refresh`
   - 检查输出：`sb sub show`
   - 必要时重建节点：`sb regen-nodes`

4. 配置变更后异常
   - 先看快照：`sb cfg snapshots list`
   - 回滚最近快照：`sb cfg rollback latest`
   - 清理旧快照：`sb cfg snapshots prune 10`

5. 更新失败
   - 使用主源：`sb update --script --source primary`
   - 使用备源：`sb update --script --source backup`
   - 自动回退：`sb update --script --source auto`

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
