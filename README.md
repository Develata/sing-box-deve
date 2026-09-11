# sing-box-deve

`sing-box-deve` 是一个以安全为优先、支持交互与自动化的 sing-box / xray 代理入口部署工具。

GitHub：`https://github.com/Develata/sing-box-deve`

## 特性概览

- **5 种公开入站协议**：`vless-reality`, `vless-ws`, `shadowsocks-2022`, `naive`, `hysteria2`；`vless-xhttp` 作为 xray compatibility 协议保留。
- **默认主线**：VPS + `sing-box` + `vless-reality`（`reality-only` preset，无需自有域名）。
- **域名 TLS 门禁**：`hysteria2` / `naive` 必须使用自有域名与有效证书；自动签发使用 nginx/OpenResty webroot，不再使用会抢占 80 端口的 standalone 模式。
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
- 发行 archive 完整性校验、不可变 runtime 版本切换与恢复。

当前回归除 shell/Node syntax、shellcheck、CLI/firewall/web schema/checksum 外，还会下载并校验当前 stable sing-box 与 Xray，对 server 配置矩阵和 sing-box client 执行真实 core validation；Clash 产物会断言真实 `proxies` 与 proxy-group 引用。

仍需谨慎看待的边界：

- 自动化测试不能完全替代真实 VPS root install、真实 nginx/OpenResty webroot ACME 签发、真实 OpenResty/nginx reload、真实客户端连通性测试；
- `scripts/consistency-check.sh` 是已安装主机上的 runtime 一致性检查，需要真实 `/etc/sing-box-deve/runtime.env`，不适合作为本地非 root checkout 测试；
- FreeBSD/Serv00、Hostuno、OpenRC/nohup 等受限环境属于 best-effort，需要在目标平台再做 smoke test；
- 域名协议要求有效证书与正确 DNS/SNI；脚本会 fail fast，但不会替你修复 DNS、运营商封锁或 80/443 被占用问题。

## 平台支持边界

- **Primary support**：Ubuntu / Debian VPS，推荐 root + systemd，架构支持 `amd64` / `arm64`。
- **Best-effort support**：Alpine Linux（OpenRC）、FreeBSD 系 Serv00/Hostuno、以及无 root/受限 shell 环境（自动回退到 nohup+crontab）。
- 未经实机验证的发行版会以“非主支持系统”继续尝试运行；生产环境建议先执行 `install --dry-run` 与目标主机 smoke test。

## 安装

主运行环境需要 Bash 4.3+、Python 3.8+、curl、jq 和 GNU coreutils/util-linux。优先从完整 checkout 安装；以下 raw bootstrap 需要项目已发布带摘要的 runtime Release 资产。


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

`install` 成功后会写入 `/usr/local/bin/sb`（用户模式为 `~/.local/bin/sb`）。`sb` 是固定快捷入口：它优先读取已安装运行时的 `script_root`，新安装指向 `/opt/sing-box-deve/current`（用户模式为 `~/sing-box-deve/current`）；不会因为你刚好在另一个源码 checkout 目录里执行 `sb` 就切换目标。调试源码 checkout 时请直接运行 `./sing-box-deve.sh ...`。

## 自动化安装示例

```bash
# 默认推荐：无需域名，部署 sing-box + vless-reality
./sing-box-deve.sh install --preset reality-only --yes

# 使用已有可信证书：部署 reality + hysteria2/naive
./sing-box-deve.sh install --preset reality-plus-domain \
  --tls-sni example.com \
  --tls-mode acme \
  --acme-cert-path /path/fullchain.pem \
  --acme-key-path /path/privkey.pem \
  --yes

# 自动签发证书：域名 A/AAAA 指向本机，并预装 acme.sh 或配置可信 installer URL/SHA256
# 通过 nginx/OpenResty webroot 完成 HTTP-01
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

菜单 `5) 出站策略管理` 中，`1) 流量路由` 决定默认流量直连还是走代理，`2) 上游节点` 负责导入链接、手动填写代理和删除节点。**导入节点不会自动改变路由**；配置后请到流量路由选择 `global-proxy` / 国内分流，或使用 `sb set-route ...`。临时切回 `direct` 路由会保留节点，`set-egress --mode direct` 则会清空上游配置。

```bash
./sing-box-deve.sh set-route direct
./sing-box-deve.sh set-egress --mode direct
./sing-box-deve.sh set-egress --mode socks --host 1.2.3.4 --port 1080 --user demo --pass demo --udp direct
./sing-box-deve.sh set-route cn-direct
./sing-box-deve.sh split3 show
./sing-box-deve.sh split3 set cn.example.com,qq.com google.com,youtube.com ads.example.com
```

上游代理的 UDP 策略通过 `OUTBOUND_PROXY_UDP_MODE=proxy|direct|block`（默认 `proxy`）独立控制：

- `proxy`：UDP 与 TCP 都按现有路由进入 `proxy-out`；SOCKS5 上游必须支持 UDP ASSOCIATE。
- `direct`：需要走上游代理的 TCP 仍进入 `proxy-out`，UDP 在更高优先级路由中改为 `direct`。
- `block`：需要走上游代理的 TCP 仍进入 `proxy-out`；sing-box 通过高优先级 `action: reject` 拒绝 UDP，Xray 继续路由到 `blackhole`。

HTTP/HTTPS 上游不能承载 UDP，因此配置为 `http`/`https` 时必须显式选择 `--udp direct` 或 `--udp block`；`--udp proxy` 会在生成配置前报错。`set-egress` 未指定 `--udp` 时仍默认 `proxy`，保持 SOCKS 的既有行为。

路由模式的基础语义为：`direct` 未命中显式 domain-split 的流量直连；`global-proxy` 全局使用主出站；`cn-direct` 国内直连、其他使用主出站；`cn-proxy` 国内使用主出站、其他直连。UDP override 位于 CN 与 domain-split 规则之前。

WARP 与所有上游出口目前不做隐式链式组合；只要 `WARP_MODE!=off` 且启用了上游代理，配置阶段就会 fail fast，避免生成未被任何 route 引用的 WARP endpoint。

出口也支持导入本项目生成的节点分享链接，包括 VLESS+Reality、VLESS-WS、HY2、SS2022、Naive 和 VLESS-XHTTP。具体内核限制、UDP 策略和链接格式见 [出口节点说明](docs/EGRESS.md)。

```bash
# 已安装主机：从仅自己可读的文件导入出口，然后选择使用出口的路由
sb set-egress --link-file /root/egress.link --udp proxy
sb set-route global-proxy
# 也可在 sb menu → 5) 出站策略管理 → 2) 上游节点中粘贴链接（输入不回显）
```

例如，将 SOCKS 上游仅用于 TCP：

```bash
sb set-egress \
  --mode socks \
  --host 1.2.3.4 \
  --port 1080 \
  --user demo \
  --pass demo \
  --udp direct

sb set-route global-proxy
```

对应 sing-box 路由核心为：

```json
{
  "outbounds": [
    {"type": "direct", "tag": "direct"},
    {"type": "socks", "tag": "proxy-out", "server": "1.2.3.4", "server_port": 1080, "username": "demo", "password": "demo"}
  ],
  "route": {
    "rules": [
      {"network": "udp", "outbound": "direct"}
    ],
    "final": "proxy-out"
  }
}
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

节点参数先写入 `nodes-model.json`，再分别渲染分享 URI、sing-box outbound 与 Clash `proxies`。sing-box selector/urltest 和 Clash proxy-groups 都引用真实节点；Xray 专有且目标客户端无法表达的协议会被明确排除，不再伪装成只有 `DIRECT` 的客户端配置。

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

- `update` / `update --script`：默认 Release 模式安装完整脚本包；显式 Git 绑定模式只校验已拉取的源码，不执行 Git 操作。两者都不更新或重启核心；
- `update --core`：只更新已安装 core，需要已有 runtime；新 core 与根据 runtime 重建的候选配置先在临时目录完成真实 config check，之后才原子替换 binary/config 并重启；健康检查失败会同时回滚 binary 与 config；
- `update --all`：先更新 Release 或检查绑定的 Git 源码，再用选中的脚本更新 core；
- `update --rollback`：Release 模式切回完整上一代；Git 模式解除绑定，恢复绑定前保存的完整版本；
- `update --release`：明确安装 Release 并解除 Git 绑定；`update --check-source`：校验当前来源。

### TUIC 退役与旧部署升级

本项目已停止支持 TUIC 入站及上游链接，不再提供安装、配置生成、分享链接或客户端导出支持。

**使用 TUIC 的主机应先用升级前的脚本迁移，再更新管理脚本。** 移除入站或替换上游会重建配置并重启核心，应安排维护时间：

1. 若 TUIC 是唯一入站，先增加一个继续支持的入站并验证连接，例如 `sb cfg protocol-add vless-reality`。
2. 用 `sb mport list` 检查 TUIC 的额外监听端口，并逐个执行 `sb mport remove tuic <端口>`；然后执行 `sb cfg protocol-remove tuic` 移除主入站。
3. 若上游也是 TUIC，先用 `sb set-route direct` 退出依赖代理的默认路由，处理显式代理域名规则，再通过 `sb set-egress --mode direct` 清除上游，或导入继续支持的节点并重新选择路由。
4. 确认节点、端口和客户端连接符合预期，再更新脚本。协议移除通过原有配置快照与防火墙托管流程处理，不手改生成的 `runtime.env`。

如果已经更新脚本，旧 runtime 仍可读取，状态查看、脚本更新、脚本回退和卸载入口仍可使用。新版会拒绝修改含 TUIC 的部署或恢复含 TUIC 的配置快照，避免静默丢失协议；可用 `sb update --rollback` 回到完整、仍支持 TUIC 的上一代脚本后迁移，或使用保留的升级前源码。归属检查等原有门禁仍然有效。

仅更新管理脚本不会停止核心中已经运行的 TUIC，也不会自动删除旧节点文件或备份。需要停止该协议时必须完成上述显式迁移；失败的脚本更新会保留旧部署及节点产物。

### Git 工作目录与已安装脚本

默认安装把源码复制成完整、不可变的 runtime，`sb` 跟随安装状态中的 `script_root`，通常解析到 `/opt/sing-box-deve/releases/...`。仅在原目录执行 `git pull` 不会改变这种默认安装。`sb --print-root` 显示实际执行目录，`sb --print-version` 读取其 `version` 文件。

希望 `git pull` 后 `sb` 立即跟随代码，可以**显式绑定一个永久 Git 目录**（菜单：更新管理 → 脚本来源与回退）：

```bash
# 先安装本版本，再绑定；以下路径请换成你自己的永久 checkout。
sudo sb update --bind-git /home/your-user/sing-box-deve --yes

# 退出已有 sb 菜单，暂停其他管理操作，然后以 checkout 所有者身份拉取。
git -C /home/your-user/sing-box-deve pull --ff-only
sudo sb --print-version
sudo sb version
sudo sb update --check-source
```

绑定只改变管理脚本来源，不改变核心、业务配置、端口或身份。`sb` 始终使用记录的物理绝对路径，不根据当前工作目录猜测。下一次调用自动读取新代码；同一版本号的新提交会在状态/版本输出中显示不同的 Git 提交号，未提交的修改另行标明。版本号以仓库 `version` 文件为准，不会把每个提交虚报成新发行版本。

绑定前校验完整源码清单、摘要、Shell 语法与加载图，并保存绑定前的完整版本和可独立运行的恢复代码。目录必须位于托管运行目录之外，不能使用 `/tmp` 等临时路径；源码及父目录不得允许组或其他用户写入。允许 root 和记录的 checkout 所有者持有文件；能修改该目录的用户也能修改 `sudo sb` 执行的代码，只绑定自己信任并维护的目录。

每次通过 `sb` 加载绑定源码前校验受管文件。手动修改源码时，必须审阅修改并重新运行 `./scripts/update-checksums.sh`；不要为绕过未知下载损坏而重建摘要。脚本不会替你 `git pull`、合并、reset、清理工作区或安装 Git hooks。普通 `update --script` 在绑定模式下只检查源码；安装发行包并解除绑定须明确使用 `update --release`。

**不要并发执行 `git pull` 与管理命令。** 脚本在入口加载前后和写操作前检查源码变化，检测到旧菜单时拒绝写入，但普通 Git 操作不持有脚本的写锁，这些检查不能保证多模块加载的原子性。需要完整版本原子切换时保留默认 Release 模式，或使用下方完整包同步方法。

```bash
sudo sb update --rollback  # 解除绑定，回到绑定前保存的完整版本
sudo sb --rollback-source # checkout 缺失/损坏时，通过保留的 Release 执行同一回退
```

配置快照回滚保留当前脚本来源；卸载不删除绑定的用户源码目录。回退也不会修改 Git 历史或工作区。旧安装尚不支持绑定参数时，先按下方方法更新管理脚本。

Release 模式下，普通 `sb update --script` 会安装所选公开 Release；如果手动源码领先于公开版本，该操作可能覆盖尚未发布的修复。请核对来源与提交号，不能只凭版本号相同判断代码相同。不要在 `releases/` 或 `current/` 内执行 Git 更新，也不要只覆盖单个 `.sh` 文件。

### 更新失败时手动更新脚本，保留正在运行的核心

`Service ownership unproven; transaction aborted: ...sing-box-deve-fw-replay.service` 表示更新事务无法确认服务文件归属，尚未开始本次更新。已知旧版模板使用 `ExecStart=/usr/local/bin/sb fw replay` 且缺少托管标记，旧更新器会误拒绝；新版只兼容完整匹配的旧模板，并验证 launcher 的项目归属。外部修改、附加指令或已有归属摘要不一致仍会拒绝，不应删除 unit、补写标记或关闭归属检查来绕过。

下面适用于默认路径的 Debian/Ubuntu root 安装。先退出旧菜单，暂停其他安装、配置修改和更新操作；源码必须包含对应的兼容修复，仅重新下载同一个旧版本不能解决更新器自身的缺陷。整个过程只更新管理脚本，不执行安装/重装、不升级核心、不重建业务配置，也不主动重启 sing-box。

```bash
(
  set -euo pipefail
  # 存在未完成事务时先诊断恢复；该恢复可能涉及服务重启，不属于本步骤。
  sudo test ! -e /var/lib/sing-box-deve.host/transactions/active
  sudo test ! -L /var/lib/sing-box-deve.host/transactions/active
  sbd_core_pid_before="$(sudo systemctl show sing-box-deve -p MainPID --value)"
  sudo systemctl is-active --quiet sing-box-deve

  # 使用单独目录，保留原 checkout 与已安装 runtime，供原生迁移/回退使用。
  sbd_repair_dir="$(mktemp -d)"
  trap 'rm -rf -- "$sbd_repair_dir"' EXIT
  git clone --depth 1 https://github.com/Develata/sing-box-deve.git "$sbd_repair_dir/source"
  cd "$sbd_repair_dir/source"
  sha256sum -c checksums.txt
  python3 scripts/runtime-archive.py pack "$PWD" "$sbd_repair_dir/runtime.tar.gz"
  sbd_repair_sum="$(sha256sum "$sbd_repair_dir/runtime.tar.gz")"
  sbd_repair_url="$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).resolve().as_uri())' "$sbd_repair_dir/runtime.tar.gz")"

  # 使用新源码中的更新器，并明确安装刚才生成的完整包。
  sudo env SBD_RELEASE_ARCHIVE_URL="$sbd_repair_url" \
    SBD_RELEASE_SHA256="${sbd_repair_sum%% *}" \
    bash ./sing-box-deve.sh update --release --yes

  sudo sb --print-root
  sudo sb --print-version
  sudo systemctl is-active --quiet sing-box-deve
  test "$sbd_core_pid_before" = "$(sudo systemctl show sing-box-deve -p MainPID --value)"
  echo '脚本更新完成，核心 PID 未改变'
)
```

已有经过校验的完整源码时，也可将示例中的临时 clone 换成该源码的绝对路径，其余打包、摘要和安装步骤保持相同；不要在打包期间继续 `git pull` 或修改源码。下载受限的 VPS 可先在另一台机器取得完整源码及其 `checksums.txt`，一并传到临时目录后按同样步骤执行。不要重新生成下载内容的校验清单来掩盖校验失败。

这条路径复用写锁、归属检查、完整包校验、原子版本切换和上一代保留；不会把 `sb` 绑定到临时目录。SHA256 用于检查内容完整性，源码本身仍须来自你信任的来源。成功后的版本回退使用 `sudo sb update --rollback`（需要已有完整上一代）。若仍出现归属错误，保留原运行状态，检查报错 unit 与归属记录；若出现 `Unfinished transaction` 或 `Recovery incomplete`，先按恢复文档处理，再尝试更新。

恢复、迁移、等待预算、保留策略、外部 bootstrap 和实机发布门禁见 [可靠性与恢复边界](docs/RELIABILITY.md)。

更新路径会校验 manifest 与 `checksums.txt`。如果 checksum manifest 缺失或校验失败，安装完整性验证会失败，不再静默跳过。`sb` launcher 也会在脚本更新后重新写入并校验，避免快捷入口指向旧脚本。

固定 Cloudflare Tunnel 的 token 存放在权限为 `0600` 的 `${SBD_DATA_DIR}/argo-token`；systemd/OpenRC/nohup 启动命令只使用 `--token-file`，不会把 token 写入 unit 的 `ExecStart` 或进程 argv。

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
