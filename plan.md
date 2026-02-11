# sing-box-deve plan文档
“sb” 启动脚本，启动以后首次部署需要 USER 进入面板以后手动输入 `1` 进行安装。

说明：本计划文档用于明确“当前实现”和“目标行为”，不受代码文件 250 行约束，允许详细展开。

---

## 1) 安装/重装
首次部署或按新参数重建配置。

具体流程依次是：
1. 进入向导（`wizard`）并采集 provider/profile/engine/protocols。
2. 采集端口策略：随机端口或手动端口映射。
3. 采集可选能力：Argo、WARP、上游代理、分流策略。
4. 生成安装上下文与防火墙快照。
5. 安装内核并写入配置（sing-box 或 xray）。
6. 生成 systemd、节点文件、订阅聚合文件。
7. 持久化 runtime 到 `/etc/sing-box-deve/runtime.env`。
8. 持久化脚本目录并写入 `sb` 命令入口。

### 1) 交互安装（wizard）
通过问答完成安装参数选择，适合首次部署。

### 2) 命令安装（install）
通过 `sb install --provider ... --engine ...` 直接执行，适合自动化。

### 3) 按运行态重装（apply --runtime）
读取当前 runtime.env，按现有参数整体重建。

### 4) 按配置文件安装（apply -f）
读取外部配置文件重建，适合迁移和批量部署。

### 0) 返回上级
返回主菜单。

---

## 2) 状态与节点查看
查看运行状态、节点信息与运行摘要。

### 1) 查看完整状态面板（panel --full）
显示核心状态、Argo 状态、runtime 全字段、settings、防火墙托管状态、版本对比信息。

### 2) 查看全量运行信息（list --all）
输出运行时关键配置与节点产物摘要，便于排查问题。

### 3) 仅查看节点链接（list --nodes）
仅展示节点链接，适合复制与快速分发。

### 0) 返回上级
返回主菜单。

---

## 3) 协议管理
协议增删与协议能力矩阵。

### 1) 查看协议能力矩阵（protocol matrix）
显示当前脚本支持的所有协议能力矩阵。

矩阵含义：
1. 协议是否被当前 engine 支持。
2. 是否具备 TLS/Reality 能力。
3. 是否支持多端口能力。
4. 是否支持 WARP 相关出站。
5. 是否参与订阅生成。

### 2) 查看已启用协议及端口能力矩阵（protocol matrix --enabled）
最左边是从1到n的序列数用于标号，显示当前脚本已经启用了的所有协议（必须注明对应端口）能力矩阵，由于支持多个不同端口的相同协议，因此每个协议必须要注明对应的入站inbound和出站outbound端口号，如果是jump多端口，也需要注明。

当前实现说明：
1. 已支持 `--enabled` 仅显示已启用协议。
2. 已支持根据运行时状态显示 WARP/mport/jump 是否 active。
3. “序号+端口明细(inbound/outbound/jump)”目前仍需继续细化展示格式。

### 3) 新增协议（cfg protocol-add）
打印出当前脚本支持的所有协议（不是协议能力矩阵）。
等待 USER 输入协议并校验是否支持（不需要检查该协议是否已创建过，重复项会自动去重）。
若支持，则继续选择接下来的端口策略（随机/手动），并执行预览再应用。

当前实现路径：
1. `cfg preview protocol-add ...` 先看变更。
2. `cfg apply protocol-add ...` 再落盘。
3. 自动重建 runtime、节点与相关服务。

### 4) 移除协议（cfg protocol-remove）
调用已启用协议矩阵后，等待 USER 选择要删除的协议（当前命令行为 csv 输入）。
应用后自动重建运行时、节点与相关服务。

### 5) 端口修改（由 4) 端口管理承接）
你原始规划中的“协议菜单内端口修改”已在当前实现中拆分为独立 `4) 端口管理`。
拆分原因：端口相关操作已扩展到主端口修改 + 多真实端口 + jump 绑定，独立菜单更清晰。

### 0) 返回上级
返回主菜单。

---

## 4) 端口管理
查看/修改各协议监听端口，并自动放行防火墙；支持多真实独立端口。

### 1) 查看协议端口映射（set-port --list）
列出当前 engine 下可管理协议的主端口映射。

### 2) 修改指定协议端口（set-port --protocol --port）
修改协议主监听端口。
流程要求：
1. 校验协议与端口。
2. 修改配置文件中的对应 inbound 端口。
3. 自动放行新端口防火墙。
4. 可选移除旧端口防火墙托管规则。
5. 重启核心或重建策略后重启。

### 3) 查看多真实端口（mport list）
查看已启用的“同协议多真实独立监听端口”记录。

### 4) 新增多真实端口（mport add）
为某协议新增一个真实监听端口。
流程要求：
1. 校验协议已启用且支持本地监听。
2. 校验端口范围与冲突。
3. 写入 `multi-ports.db`。
4. 自动放行该端口防火墙。
5. 重建 runtime（自动把额外 inbound 注入配置）。

### 5) 移除多真实端口（mport remove）
移除某协议某个真实监听端口。
流程要求：
1. 从 `multi-ports.db` 删除记录。
2. 清理该端口关联 jump 目标。
3. 更新 jump 规则重放状态。
4. 清理对应防火墙托管记录。
5. 重建 runtime 与节点。

### 6) 清空多真实端口（mport clear）
清理所有 mport 记录，并同步清理相关 jump 与防火墙状态。

### 0) 返回上级
返回主菜单。

---

## 5) 出站策略管理
设置直连/上游代理/分流路由/按端口策略/分享出口。

### 1) 切换为直连出站（set-egress direct）
调用2.2，打印出已启用协议及端口能力矩阵
等待USER输入需要修改端口的对应协议的序列数
将其改为直连出站

### 2) 配置上游代理出站（set-egress socks/http/https）
调用2.2，打印出已启用协议及端口能力矩阵
等待USER输入需要修改端口的对应协议的序列数
配置其socks/http/https代理出站

### 3) 设置分流路由模式（set-route ...）
设置 `direct/global-proxy/cn-direct/cn-proxy`。

### 4) 设置分享出口端点（set-share ...）
设置 `direct/proxy/warp` 三类分享出口端点。

### 5) 设置按端口出站策略（set-port-egress）
支持 `list/set/clear`。
用于指定某些入口端口走 direct/proxy/warp/psiphon。

### 0) 返回上级
返回主菜单。

---

## 6) 服务管理
重启核心与 Argo、刷新节点、看日志。

### 1) 重启全部服务（restart --all）
重启核心服务及相关边车。

### 2) 仅重启核心服务（restart --core）
仅重启主服务。

### 3) 仅重启 Argo 边车（restart --argo）
仅重启 Argo 服务。

### 4) 重建节点文件（regen-nodes）
按当前配置重新生成节点与订阅产物。

### 5) 查看核心日志（logs --core）
查看核心服务日志。

### 6) 查看 Argo 日志（logs --argo）
查看 Argo 日志。

### 0) 返回上级
返回主菜单。

---

## 7) 更新管理
更新脚本或内核，支持主源/备源。

### 1) 更新核心内核（update --core）
更新已安装的 sing-box/xray 内核。

### 2) 更新脚本与模块（update --script）
更新脚本本体与模块文件。
当前逻辑：
1. 若当前 `PROJECT_ROOT` 是 git 仓库，走 `git pull` 流程。
2. 否则走 `checksums + manifest` 的下载校验更新流程。
3. 支持失败回滚。

### 3) 同时更新内核与脚本（update --all）
执行脚本更新后再执行内核更新。

### 4) 仅主源更新脚本（update --script --source primary）
指定主源更新。

### 5) 仅备源更新脚本（update --script --source backup）
指定备源更新。

### 6) 更新回滚（update --rollback）
从最近备份恢复脚本与模块文件。

### 0) 返回上级
返回主菜单。

补充注意：
1. `sb` 的实际执行目录来自 `runtime.env` 的 `script_root`。
2. 若你在别的目录 `git pull`，不会自动影响 `sb`，除非同步到 `script_root` 目录。

---

## 8) 防火墙管理
查看托管规则、回滚、重放持久化规则。

### 1) 查看防火墙托管状态（fw status）
显示后端类型与托管规则明细。

### 2) 回滚到上次防火墙快照（fw rollback）
从快照恢复防火墙。

### 3) 重放托管防火墙规则（fw replay）
按托管记录重新应用规则。

### 0) 返回上级
返回主菜单。

---

## 9) 设置管理
语言与自动确认开关。

### 1) 查看当前设置（settings show）
显示当前 settings。

### 2) 设置界面语言（settings set lang）
设置 `zh/en`。

### 3) 设置自动确认（settings set auto_yes）
设置 `true/false`。

### 0) 返回上级
返回主菜单。

---

## 10) 日志查看
快速查看核心或 Argo 日志。

### 1) 查看核心服务日志（logs --core）
显示核心日志。

### 2) 查看 Argo 边车日志（logs --argo）
显示 Argo 日志。

### 0) 返回上级
返回主菜单。

---

## 11) 卸载管理
保留设置或完全卸载。

### 1) 卸载并保留设置（uninstall --keep-settings）
保留 settings/uuid/keys 备份，移除服务与运行状态。

### 2) 完全卸载（uninstall）
移除托管服务、状态目录、脚本入口及相关残留。

### 0) 返回上级
返回主菜单。

---

## 12) 订阅与分享
刷新订阅、展示二维码、推送目标配置。

### 1) 刷新订阅与分享产物（sub refresh）
重新生成节点、订阅与变体产物。

### 2) 查看链接与二维码（sub show）
展示订阅链接与二维码。

### 3) 重同步规则集（sub rules-update）
重拉并同步规则集。

### 4) 配置 GitLab 推送目标（sub gitlab-set）
设置 token、项目、分支、路径。

### 5) 推送订阅到 GitLab（sub gitlab-push）
推送产物到 GitLab。

### 6) 配置 Telegram 推送（sub tg-set）
设置 bot token 与 chat id。

### 7) 推送订阅到 Telegram（sub tg-push）
推送产物到 Telegram。

### 0) 返回上级
返回主菜单。

---

## 13) 配置变更中心
预览/应用/回滚快照与高级变更。

### 1) 预览配置变更（cfg preview <action>）
预览动作结果，不落盘。

### 2) 应用配置变更并自动快照（cfg apply <action>）
应用动作并落盘快照。

### 3) 按快照回滚配置（cfg rollback ...）
按 snapshot_id 或 latest 回滚。

### 4) 查看配置快照列表（cfg snapshots list）
查看历史快照。

### 5) 清理旧快照（cfg snapshots prune）
按保留数量清理。

### 6) 查看三通道分流规则（split3 show）
查看 direct/proxy/block 三通道规则。

### 7) 设置三通道分流规则（split3 set）
设置 direct/proxy/block 三通道规则。

### 8) 多端口跳跃复用管理（jump set/clear/replay）
支持多个主端口目标：
1. `jump set <protocol> <main_port> <extra_csv>`
2. `jump clear [protocol] [main_port]`
3. `jump replay`

### 0) 返回上级
返回主菜单。

---

## 14) 内核与WARP
内核切换、WARP、BBR、证书工具。

### 1) 查看内核版本状态（kernel show）
显示当前内核状态。

### 2) 切换到最新 sing-box（kernel set sing-box latest）
切换到最新 sing-box。

### 3) 切换到最新 xray（kernel set xray latest）
切换到最新 xray。

### 4) 指定内核版本标签（kernel set <engine> <tag>）
按 tag 切换版本。

### 5) 查看 WARP 状态（warp status）
查看 WARP IPv4/IPv6 状态。

### 6) 注册 WARP 账户（warp register）
执行 WARP 注册。

### 7) 检测 WARP 出口解锁（warp unlock）
检测解锁状态。

### 8) 启动 WARP Socks5（warp socks5-start）
启动本地 Socks5。

### 9) 查看 WARP Socks5 状态（warp socks5-status）
查看 Socks5 运行状态。

### 10) 停止 WARP Socks5（warp socks5-stop）
停止 Socks5。

### 11) 查看 BBR 状态（sys bbr-status）
查看 BBR 状态。

### 12) 启用 BBR（sys bbr-enable）
启用 BBR。

### 13) 安装 acme.sh（sys acme-install）
安装 ACME 工具。

### 14) 申请证书（sys acme-issue）
签发证书。

### 15) 应用证书到运行时（sys acme-apply）
应用证书路径到运行时。

### 0) 返回上级
返回主菜单。

---

## 15) 多真实独立端口 + jump 多主端口（设计与落地）
该节用于锁定你本次提出的重点能力，防止后续偏差。

### 1) 核心目标
1. 同一协议可开多个真实独立监听端口。
2. 每个真实端口可分别设置 jump 多端口映射。
3. 节点生成需要体现主端口、mport 变体、jump 变体。

### 2) 状态文件
1. `multi-ports.db`：`/var/lib/sing-box-deve/multi-ports.db`（`protocol|port`）。
2. `jump-ports.db`：`/var/lib/sing-box-deve/jump-ports.db`（`protocol|main_port|extra_csv`）。
3. `jump-rules.db`：`/var/lib/sing-box-deve/jump-rules.db`（防火墙 jump 规则）。

### 3) 生效机制
1. `mport add/remove/clear` 会触发 runtime 重建。
2. runtime 重建会注入额外 inbound（按协议主 inbound 克隆）。
3. `jump set/clear/replay` 维护防火墙 REDIRECT 规则并持久化。
4. 节点生成流程按 base -> share -> mport -> jump 顺序叠加后去重。

### 4) 你定义的显示要求（后续必须完成）
`protocol matrix --enabled` 需要完整达到：
1. 有 1..n 序号。
2. 每个启用协议都标明端口。
3. 支持同协议多端口时，逐条标明 inbound/outbound。
4. 若配置 jump，明确标注主端口与附加端口关系。

### 5) 当前差距
以上第 4) 的展示格式目前仍未完全落地，需要下一阶段直接实现。

---

## 0) 退出
退出脚本。
