# sing-box-deve

`sing-box-deve` 是一个以安全为优先、支持交互与自动化的 sing-box / xray 代理入口部署工具。

GitHub：`https://github.com/Develata/sing-box-deve`

## 特性概览

- **6 种公开入站协议**：`vless-reality`, `vless-ws`, `shadowsocks-2022`, `naive`, `hysteria2`, `tuic`；`vless-xhttp` 作为 xray compatibility 协议保留。
- **默认主线**：VPS + `sing-box` + `vless-reality,hysteria2`。
- **可选兼容**：Serv00/Hostuno 受限环境、xray compatibility engine。
- **Argo 隧道**：临时/固定模式，用于受限入口或 CDN 辅助暴露。
- **WARP 出站**：仅作为 outbound mode，不暴露 WireGuard public inbound。
- **运维闭环**：panel/list/doctor/logs/restart/update/uninstall/settings。
- **安全边界**：增量防火墙托管、规则重放、managed rollback、checksum manifest。
- **订阅产物**：本地刷新/查看节点、聚合订阅、sing-box/clash/SFA/SFI 客户端配置。

已裁剪的旧功能：SAP Cloud Foundry provider、Workers 模板、Psiphon sidecar、SFW Windows 打包、GitLab/TG 订阅推送、jump 端口跳跃、set-share 手工分享端点、set-port-egress 按端口出站策略、`anytls`/`trojan` public inbound。

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
```

## 自动化安装示例

```bash
./sing-box-deve.sh install --provider vps --profile lite --engine sing-box --protocols vless-reality --yes
./sing-box-deve.sh install --provider vps --profile lite --engine sing-box --protocols vless-reality,hysteria2 --random-main-port --yes
./sing-box-deve.sh install --provider vps --profile full --engine sing-box --protocols vless-reality,hysteria2,tuic --argo temp --yes
```

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
./sing-box-deve.sh cfg tls self-signed|acme|acme-auto [cert_path|domain] [key_path|email] [dns_provider]
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
./sing-box-deve.sh sys acme-issue <domain> <email> [dns_provider]
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
./sing-box-deve.sh update --script
./sing-box-deve.sh update --core
./sing-box-deve.sh update --all
./sing-box-deve.sh uninstall --keep-settings
```

## 安全承诺

- 不清空系统防火墙。
- 不接管无法证明归属的预存防火墙规则。
- 重复安装同一 endpoint 不重复堆叠托管规则。
- `fw status` 在无可用后端时仍会展示托管记录。
- 更新脚本通过 manifest + checksum 验证。

## 许可证

MIT
