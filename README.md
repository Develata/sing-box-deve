# sing-box-deve

`sing-box-deve` 是一个以安全为优先、支持交互与自动化的 sing-box / xray 代理入口部署工具。

GitHub：`https://github.com/Develata/sing-box-deve`

## 特性概览

- **6 种公开入站协议**：`vless-reality`, `vless-ws`, `shadowsocks-2022`, `naive`, `hysteria2`, `tuic`；`vless-xhttp` 作为 xray compatibility 协议保留。
- **默认主线**：VPS + `sing-box` + `vless-reality`（`reality-only` preset，无需自有域名）。
- **域名 TLS 门禁**：`hysteria2` / `tuic` / `naive` 必须使用自有域名与有效证书；自动签发使用 nginx/OpenResty webroot，不再使用会抢占 80 端口的 standalone 模式。
- **域名静态站面**：域名协议会生成 archive-gateway 静态站；优先复用 OpenResty，其次 nginx，两者都不存在时可按 nginx.org 官方仓库安装 nginx。
- **可选兼容**：Serv00/Hostuno 受限环境、xray compatibility engine。
- **Argo 隧道**：临时/固定模式，用于受限入口或 CDN 辅助暴露。
- **WARP 出站**：仅作为 outbound mode，不暴露 WireGuard public inbound。
- **运维闭环**：panel/list/doctor/logs/restart/update/uninstall/settings。
- **安全边界**：增量防火墙托管、规则重放、managed rollback、checksum manifest。
- **订阅产物**：本地刷新/查看节点、聚合订阅、sing-box/clash/SFA/SFI 客户端配置。

已裁剪的旧功能：SAP Cloud Foundry provider、Workers 模板、Psiphon sidecar、SFW Windows 打包、GitLab/TG 订阅推送、jump 端口跳跃、set-share 手工分享端点、set-port-egress 按端口出站策略、`anytls`/`trojan` public inbound。

## 当前状态与验证结论

当前主线已完成第二轮模块级修复与回归验证。可以认为**基础功能面已经可用**，包括：

- CLI 参数解析、`install --dry-run`、`wizard`/`panel`/`doctor`/`list` 等基础命令；
- `reality-only` 默认安装路径，以及域名协议 preset 的 TLS 证书门禁；
- `set-port` / `mport` 端口管理、节点链接重生、防火墙旧记录清理；
- OpenResty/nginx web-front 契约与 web-generator 参数同步；
- Hysteria2 `salamander` obfs 作为高级 opt-in；
- 非 root user-mode 下的 state/config/snapshot 路径同步；
- Serv00 provider 与 VPS provider 的依赖/防火墙边界；
- self-update/rollback 的 checksum manifest 完整性校验。

最近一轮本地验证覆盖：shell syntax、Node syntax、CLI smoke、firewall records、web schema drift、version compare、module size、update authority、clash ruleset、shellcheck、checksum verify、`git diff --check`，并经过 Codex blocker-only review：`PASS — no blockers found`。

仍需谨慎看待的边界：

- 自动化测试不能完全替代真实 VPS root install、真实 nginx/OpenResty webroot ACME 签发、真实 OpenResty/nginx reload、真实客户端连通性测试；
- `scripts/consistency-check.sh` 是已安装主机上的 runtime 一致性检查，需要真实 `/etc/sing-box-deve/runtime.env`，不适合作为本地非 root checkout 测试；
- FreeBSD/Serv00、Hostuno、OpenRC/nohup 等受限环境属于 best-effort，需要在目标平台再做 smoke test；
- 域名协议要求有效证书与正确 DNS/SNI；脚本会 fail fast，但不会替你修复 DNS、运营商封锁或 80/443 被占用问题。

## 平台支持边界

- **Primary support**：Ubuntu / Debian VPS，推荐 root + systemd，架构支持 `amd64` / `arm64`。
- **Best-effort support**：Alpine Linux（OpenRC）、FreeBSD 系 Serv00/Hostuno、以及无 root/受限 shell 环境（自动回退到 nohup+crontab）。
- 未经实机验证的发行版会以“非主支持系统”继续尝试运行；生产环境建议先执行 `install --dry-run` 与目标主机 smoke test。

## 一键安装

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/Develata/sing-box-deve/main/sing-box-deve.sh) wizard
```

本地克隆后运行：

```bash
git clone https://github.com/Develata/sing-box-deve.git
cd sing-box-deve
chmod +x ./sing-box-deve.sh
./sing-box-deve.sh wizard
```

## 90% 用户常用命令

```bash
./sing-box-deve.sh wizard
./sing-box-deve.sh panel --full
./sing-box-deve.sh doctor
./sing-box-deve.sh list --nodes
./sing-box-deve.sh restart --core

# 完成一次安装后，也可以使用全局快捷入口：
sb panel --full
sb doctor
sb list --nodes
sb restart --core
```

`install` 成功后会写入 `/usr/local/bin/sb`。`sb` 是固定快捷入口：它优先读取已安装运行时的 `script_root`，通常指向 `/opt/sing-box-deve/script` 或当前安装绑定的 Git checkout；不会因为你刚好在另一个源码 checkout 目录里执行 `sb` 就切换目标。调试源码 checkout 时请直接运行 `./sing-box-deve.sh ...`。

## 自动化安装示例

```bash
# 默认推荐：无需域名，部署 sing-box + vless-reality
./sing-box-deve.sh install --preset reality-only --yes

# 使用已有可信证书：部署 reality + hysteria2/tuic/naive
./sing-box-deve.sh install --preset reality-plus-domain \
  --tls-sni example.com \
  --tls-mode acme \
  --acme-cert-path /path/fullchain.pem \
  --acme-key-path /path/privkey.pem \
  --yes

# 自动签发证书：要求域名 A/AAAA 已指向本机；脚本通过 nginx/OpenResty webroot 完成 HTTP-01
./sing-box-deve.sh install --preset full \
  --tls-sni example.com \
  --tls-mode acme-auto \
  --acme-email admin@example.com \
  --yes

# 高级：指定 OpenResty/nginx web front，并开启 Hysteria2 salamander obfs
./sing-box-deve.sh install --preset reality-plus-domain \
  --tls-sni example.com \
  --tls-mode acme \
  --acme-cert-path /path/fullchain.pem \
  --acme-key-path /path/privkey.pem \
  --web-front openresty \
  --hy2-obfs salamander \
  --yes
```

`--web-front auto` 的选择顺序是：已有 OpenResty → 已有 nginx → 询问是否按 nginx.org 官方仓库安装 nginx。脚本不会自动安装 OpenResty。

## 运行管理

```bash
./sing-box-deve.sh list --all
./sing-box-deve.sh panel --full
./sing-box-deve.sh status
./sing-box-deve.sh list --nodes
./sing-box-deve.sh list --runtime
./sing-box-deve.sh doctor
./sing-box-deve.sh logs --core
./sing-box-deve.sh logs --argo
./sing-box-deve.sh restart --all
./sing-box-deve.sh restart --core
./sing-box-deve.sh restart --argo
```

## 协议与端口

```bash
./sing-box-deve.sh protocol matrix
./sing-box-deve.sh protocol matrix --enabled
./sing-box-deve.sh set-port --list
./sing-box-deve.sh set-port --protocol vless-reality --port 443
./sing-box-deve.sh mport list
./sing-box-deve.sh mport add vless-reality 8443
./sing-box-deve.sh mport remove vless-reality 8443
```

## 出站与路由

```bash
./sing-box-deve.sh set-egress --mode direct
./sing-box-deve.sh set-egress --mode socks --host 1.2.3.4 --port 1080 --user demo --pass demo
./sing-box-deve.sh set-route cn-direct
./sing-box-deve.sh split3 show
./sing-box-deve.sh split3 set cn.example.com,qq.com google.com,youtube.com ads.example.com
```

## 配置变更中心

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
./sing-box-deve.sh cfg tls self-signed|acme|acme-auto [cert_path|domain] [key_path|email]
./sing-box-deve.sh cfg profile lite|full
./sing-box-deve.sh cfg protocol-add <proto_csv> [random|manual] [proto:port,...]
./sing-box-deve.sh cfg protocol-remove <proto_csv|index_csv>
./sing-box-deve.sh cfg rebuild
```

## WARP / Argo / 系统工具

```bash
./sing-box-deve.sh warp status
./sing-box-deve.sh warp register
./sing-box-deve.sh warp unlock
./sing-box-deve.sh warp socks5-start [port]
./sing-box-deve.sh warp socks5-status
./sing-box-deve.sh warp socks5-stop
./sing-box-deve.sh sys bbr-status
./sing-box-deve.sh sys bbr-enable
./sing-box-deve.sh sys acme-install
./sing-box-deve.sh sys acme-issue <domain> <email>
./sing-box-deve.sh sys acme-apply <cert_path> <key_path>
```

## 订阅与客户端产物

```bash
./sing-box-deve.sh sub refresh
./sing-box-deve.sh sub show
./sing-box-deve.sh sub rules-update
```

订阅刷新后生成：

- 聚合原始链接：`/opt/sing-box-deve/data/jhdy.txt`
- 聚合 base64：`/opt/sing-box-deve/data/jh_sub.txt`
- 客户端分组链接：`/opt/sing-box-deve/data/share-groups/*.txt`
- sing-box 客户端配置：`/opt/sing-box-deve/data/sing_box_client.json`
- clash-meta 客户端配置：`/opt/sing-box-deve/data/clash_meta_client.yaml`
- SFA/SFI 客户端配置：`/opt/sing-box-deve/data/sfa_client.json`, `sfi_client.json`

## 防火墙

```bash
./sing-box-deve.sh fw status
./sing-box-deve.sh fw replay
./sing-box-deve.sh fw rollback
```

防火墙策略：只做增量托管规则；不会执行 `ufw disable`、`iptables -F`、`iptables -X`、`setenforce 0`。rollback 指 sing-box-deve 托管规则回滚，不是系统防火墙全量快照。

## 设置持久化

root 默认路径：

- config：`/etc/sing-box-deve`
- state：`/var/lib/sing-box-deve`
- install：`/opt/sing-box-deve`

非 root 默认路径：`~/sing-box-deve/`。

```bash
./sing-box-deve.sh settings show
./sing-box-deve.sh settings set lang zh
./sing-box-deve.sh settings set lang=en auto_yes=true update_channel=stable
```

## 更新与卸载

```bash
./sing-box-deve.sh version
./sing-box-deve.sh update
./sing-box-deve.sh update --script
./sing-box-deve.sh update --core
./sing-box-deve.sh update --all
./sing-box-deve.sh uninstall --keep-settings
```

完成安装后可等价使用：

```bash
sb version
sb update
sb update --script
sb update --core
sb update --all
sb update --rollback
```

更新语义：

- `update` / `update --script`：只刷新脚本与模块文件，不更新 sing-box/xray core；
- `update --core`：只更新已安装 core，需要已有 runtime；
- `update --all`：先刷新脚本，再用刷新后的脚本继续更新 core；
- `update --rollback`：回滚上一轮脚本更新快照。

更新路径会校验 manifest 与 `checksums.txt`。如果 checksum manifest 缺失或校验失败，安装完整性验证会失败，不再静默跳过。`sb` launcher 也会在脚本更新后重新写入并校验，避免快捷入口指向旧脚本。

## 真实主机 smoke test 建议

在新 VPS 上建议按以下顺序验证：

```bash
# 1. 非破坏性预检
sudo ./sing-box-deve.sh install --preset reality-only --dry-run --yes

# 2. 最小主线安装
sudo ./sing-box-deve.sh install --preset reality-only --yes

# 3. 快捷入口与运行状态
sb --print-root
sb --print-version
sb status
sb doctor

# 4. 运行状态与节点产物
sudo ./sing-box-deve.sh status
sudo ./sing-box-deve.sh doctor
sudo ./sing-box-deve.sh list --nodes
sudo ./sing-box-deve.sh fw status

# 5. 更新路径
sb update --script --force --yes
sb update --core --yes
sb version

# 6. 端口变更回归
sudo ./sing-box-deve.sh set-port --protocol vless-reality --port 24443
sudo ./sing-box-deve.sh list --nodes
sudo ./sing-box-deve.sh fw status
```

域名协议另需验证：DNS 已指向本机、证书 SAN 覆盖 `--tls-sni`、80/443 未被非托管服务占用、OpenResty/nginx 配置测试与 reload 成功、客户端能按正常证书校验连接。

## 安全承诺

- 不清空系统防火墙。
- 不接管无法证明归属的预存防火墙规则。
- 重复安装同一 endpoint 不重复堆叠托管规则。
- `fw status` 在无可用后端时仍会展示托管记录。
- 更新脚本通过 manifest + checksum 验证。

## 许可证

MIT
