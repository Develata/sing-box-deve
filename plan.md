# sing-box-deve 计划文档（规范版）

本文档用于先定义目标规范，再驱动代码实现。当前阶段以文档为准，不以现有代码行为倒推需求。

## 0) 文档约定
- `SPEC`：目标规范，后续必须实现。
- `CURRENT`：当前实现现状，只用于定位差距。
- `P0/P1/P2`：优先级，`P0` 必须先做。

术语：
- `主端口`：协议的真实监听端口（main inbound）。
- `多真实端口`：同协议的多个真实独立监听端口（mport）。
- `jump 附加端口`：通过防火墙重定向到某个主端口的端口，不是独立协议实例。

---

## 1) 全局工程约束（SPEC）
1. 模块化优先：新增逻辑优先拆到 `lib/*_*.sh` 小文件。
2. 单代码文件行数限制：`<=250` 行，建议 `<=150` 行。
3. 文档不受行数限制。
4. 每个命令必须定义：
   - 输入参数格式
   - 校验规则
   - 执行步骤
   - 输出格式
   - 失败处理/回滚策略
   - 持久化影响
5. 重要流程必须支持幂等执行（重复执行不产生脏状态）。

---

## 2) 主菜单（SPEC）

## 1) 安装/重装
首次部署或按新参数重建配置。

### 1) 交互安装（wizard）
- 命令：`sb wizard`
- 输入：向导交互输入 provider/profile/engine/protocols/port/argo/warp/egress/route。
- 校验：协议合法、端口合法、引擎兼容、资源档位限制。
- 执行：生成上下文 -> 快照防火墙 -> 安装内核 -> 生成配置 -> 写服务 -> 生成节点。
- 输出：安装结果、关键路径、后续命令提示。
- 失败处理：失败时回滚防火墙到安装前快照。
- 持久化：`/etc/sing-box-deve/runtime.env`、service 文件、节点文件、脚本入口。

### 2) 命令安装（install）
- 命令：`sb install ...`
- 输入：命令行参数。
- 校验：同上。
- 执行/输出/失败/持久化：同 1)。

### 3) 按运行态重装（apply --runtime）
- 命令：`sb apply --runtime`
- 输入：当前 runtime 文件。
- 校验：runtime 文件存在且关键字段完整。
- 执行：按 runtime 重建配置与节点。
- 输出：重建结果。
- 失败处理：保留旧配置并报错，不写脏状态。
- 持久化：更新 runtime 时间戳与生成产物。

### 4) 按配置文件安装（apply -f）
- 命令：`sb apply -f <config.env>`
- 输入：外部配置文件。
- 校验：文件存在、字段格式合法。
- 执行：按文件构建运行态并安装。
- 输出：重建结果。
- 失败处理：中断并保持旧状态。
- 持久化：同 1)。

### 0) 返回上级

## 2) 状态与节点查看
查看运行状态、节点信息与运行摘要。

### 1) 查看完整状态面板（panel --full）
- 命令：`sb panel --full`
- 输出：服务状态、runtime 全字段、settings、防火墙托管、版本状态。

### 2) 查看全量运行信息（list --all）
- 命令：`sb list --all`
- 输出：运行态与节点相关全量信息。

### 3) 仅查看节点链接（list --nodes）
- 命令：`sb list --nodes`
- 输出：仅节点链接。

### 0) 返回上级

## 3) 协议管理
协议增删与协议能力矩阵。

### 1) 查看协议能力矩阵（protocol matrix）
- 命令：`sb protocol matrix`
- 输出列（SPEC）：协议、内核支持、TLS、Reality、多端口、WARP 出站、订阅（是否参与订阅生成）。

### 2) 查看已启用协议及端口能力矩阵（protocol matrix --enabled）
- 命令：`sb protocol matrix --enabled`
- 输出列（SPEC）：
  1. 序号（1..n）
  2. 协议
  3. 端口类型（main/mport）
  4. inbound 端口
  5. outbound（direct/proxy/warp/psiphon）
  6. jump 附加端口
  7. TLS 
  8. Reality 
  9. 多端口 
  10. WARP 
  11. 订阅
- 规则（SPEC）：
  1. 同协议多端口时，每个端口都要单独一行，从第二个端口开始其余同上信息不填。
  2. 若存在 jump，必须显示主端口对应的 extra 端口集。
  3. 非监听类协议（如纯模式协议）可显示 `-` 占位。

### 3) 新增协议（cfg protocol-add）
- 命令：`sb cfg preview protocol-add ...` / `sb cfg apply protocol-add ...`
- 输入：协议名、端口模式、可选手动端口映射。
- 校验：协议合法、引擎兼容、端口不冲突、profile 限制。
- 执行：预览 -> 应用 -> 重建 runtime。
- 输出：新增协议与影响摘要。
- 失败处理：预览不落盘；应用失败恢复原状态。
- 持久化：runtime、配置文件、节点、托管规则。

### 4) 移除协议（cfg protocol-remove）
- 命令：`sb cfg preview protocol-remove ...` / `sb cfg apply protocol-remove ...`
- 输入：协议序号。
- 校验：目标协议存在，且删除后保留至少一个可运行协议。
- 执行：预览 -> 应用 -> 重建 runtime。
- 输出：移除结果与影响摘要。
- 失败处理：失败不落盘。
- 持久化：同 3)。

### 0) 返回上级

## 4) 端口管理
查看/修改各协议监听端口并自动放行防火墙。

### 1) 查看协议端口映射（set-port --list）
- 命令：`sb set-port --list`
- 输出：协议到主端口映射。

### 2) 修改指定协议端口（set-port --protocol --port）
- 命令：`sb set-port --protocol <name> --port <1-65535>`
- 校验：协议可管理、端口合法且不冲突。
- 执行：更新 inbound 端口 -> 防火墙规则调整 -> 重启核心。
- 输出：旧端口 -> 新端口。
- 失败处理：配置校验失败时回退。
- 持久化：配置文件、防火墙托管状态、runtime。

### 3) 查看多真实端口（mport list）
- 命令：`sb mport list`
- 输出：`protocol|port` 列表。

### 4) 新增多真实端口（mport add）
- 命令：`sb mport add <protocol> <port>`
- 校验：协议已启用且可监听，端口不冲突。
- 执行：写 `multi-ports.db` -> 开防火墙 -> 重建 runtime。
- 输出：新增记录。
- 失败处理：失败时不写入或撤销写入。

### 5) 移除多真实端口（mport remove）
- 命令：`sb mport remove <protocol> <port>`
- 校验：记录存在。
- 执行：删记录 -> 清理关联 jump -> 重建 runtime。
- 输出：移除结果。
- 失败处理：失败时保持原记录与规则一致性。

### 6) 清空多真实端口（mport clear）
- 命令：`sb mport clear`
- 执行：清空 mport 记录并同步清理 jump 关联。

### 0) 返回上级

## 5) 出站策略管理
设置直连/上游代理/分流路由/按端口策略/分享出口。

### 1) 切换为直连出站（set-egress direct）
- 命令：`sb set-egress --mode direct`
- 作用域：全局默认出站。

### 2) 配置上游代理出站（set-egress socks/http/https）
- 命令：`sb set-egress --mode socks|http|https --host ... --port ...`
- 作用域：全局默认出站。

### 3) 设置分流路由模式（set-route ...）
- 命令：`sb set-route <direct|global-proxy|cn-direct|cn-proxy>`

### 4) 设置分享出口端点（set-share ...）
- 命令：`sb set-share <direct|proxy|warp> <host:port,...>`

### 5) 设置按端口出站策略（set-port-egress）
- 命令：`sb set-port-egress --list|--map|--clear`
- 规则（SPEC）：端口级策略优先级高于全局默认出站。

### 0) 返回上级

## 6) 服务管理
重启核心与 Argo、刷新节点、看日志。

### 1) 重启全部服务（restart --all）
### 2) 仅重启核心服务（restart --core）
### 3) 仅重启 Argo 边车（restart --argo）
### 4) 重建节点文件（regen-nodes）
### 5) 查看核心日志（logs --core）
### 6) 查看 Argo 日志（logs --argo）
### 0) 返回上级

## 7) 更新管理
更新脚本或内核，支持主源/备源。

### 1) 更新核心内核（update --core）
### 2) 更新脚本与模块（update --script）
### 3) 同时更新内核与脚本（update --all）
### 4) 仅主源更新脚本（update --script --source primary）
### 5) 仅备源更新脚本（update --script --source backup）
### 0) 返回上级

备注（SPEC）：
1. `update --rollback` 作为 CLI 能力保留，不强制出现在菜单。
2. `sb` 执行目录由 `runtime.env:script_root` 决定。

## 8) 防火墙管理
### 1) 查看防火墙托管状态（fw status）
### 2) 回滚到上次防火墙快照（fw rollback）
### 3) 重放托管防火墙规则（fw replay）
### 0) 返回上级

## 9) 设置管理
### 1) 查看当前设置（settings show）
### 2) 设置界面语言（settings set lang）
### 3) 设置自动确认（settings set auto_yes）
### 0) 返回上级

## 10) 日志查看
### 1) 查看核心服务日志（logs --core）
### 2) 查看 Argo 边车日志（logs --argo）
### 0) 返回上级

## 11) 卸载管理
### 1) 卸载并保留设置（uninstall --keep-settings）
### 2) 完全卸载（uninstall）
### 0) 返回上级

## 12) 订阅与分享
### 1) 刷新订阅与分享产物（sub refresh）
### 2) 查看链接与二维码（sub show）
### 3) 重同步规则集（sub rules-update）
### 4) 配置 GitLab 推送目标（sub gitlab-set）
### 5) 推送订阅到 GitLab（sub gitlab-push）
### 6) 配置 Telegram 推送（sub tg-set）
### 7) 推送订阅到 Telegram（sub tg-push）
### 0) 返回上级

## 13) 配置变更中心
### 1) 预览配置变更（cfg preview <action>）
### 2) 应用配置变更并自动快照（cfg apply <action>）
### 3) 按快照回滚配置（cfg rollback ...）
### 4) 查看配置快照列表（cfg snapshots list）
### 5) 清理旧快照（cfg snapshots prune）
### 6) 查看三通道分流规则（split3 show）
### 7) 设置三通道分流规则（split3 set）
### 8) 多端口跳跃复用管理（jump set/clear/replay）
### 0) 返回上级

## 14) 内核与WARP
### 1) 查看内核版本状态（kernel show）
### 2) 切换到最新 sing-box（kernel set sing-box latest）
### 3) 切换到最新 xray（kernel set xray latest）
### 4) 指定内核版本标签（kernel set <engine> <tag>）
### 5) 查看 WARP 状态（warp status）
### 6) 注册 WARP 账户（warp register）
### 7) 检测 WARP 出口解锁（warp unlock）
### 8) 启动 WARP Socks5（warp socks5-start）
### 9) 查看 WARP Socks5 状态（warp socks5-status）
### 10) 停止 WARP Socks5（warp socks5-stop）
### 11) 查看 BBR 状态（sys bbr-status）
### 12) 启用 BBR（sys bbr-enable）
### 13) 安装 acme.sh（sys acme-install）
### 14) 申请证书（sys acme-issue）
### 15) 应用证书到运行时（sys acme-apply）
### 0) 返回上级

## 0) 退出

---

## 附录A) 数据契约（SPEC）
1. `runtime.env`
   - 必填：`provider/profile/engine/protocols/script_root/installed_at`
   - 可选：出站、分流、证书、端口策略等字段。
2. `multi-ports.db`
   - 格式：`protocol|port`
   - 唯一键：`(protocol, port)`。
3. `jump-ports.db`
   - 格式：`protocol|main_port|extra_csv`
   - 唯一键：`(protocol, main_port)`。
4. `jump-rules.db`
   - 格式：`backend|proto|from_port|to_port|tag`
   - 用途：重放 jump 规则。

---

## 附录B) 冲突处理规则（SPEC）
1. `mport add` 与现有监听端口冲突 -> 拒绝执行。
2. `jump set` 的 `main_port` 不是活动端口（主端口或 mport）-> 拒绝执行。
3. 删除 mport 时若该端口被 jump 用作主端口 -> 先移除对应 jump 目标，再重建。
4. `mport clear` -> 清理全部 mport 后，自动重放或清空 jump 规则。
5. 端口出站映射引用了不存在 inbound 端口 -> 拒绝执行。

---

## 附录C) 幂等与原子性（SPEC）
1. 重复执行同一 `mport add` 不应写重复记录。
2. 重复执行同一 `jump set` 应覆盖同键记录，不堆叠冲突规则。
3. 任何失败都不得留下“半更新状态”（配置写了但规则没写，或反之）。
4. 关键写入使用临时文件 + 原子替换（`mv`）策略。

---

## 附录D) 验收标准（SPEC）

### 6.1 协议矩阵（P0）
1. `protocol matrix --enabled` 显示 1..n 序号。
2. 同协议 `main + mport` 多行展示。
3. `jump` 显示在对应主端口行。
4. `outbound` 列能体现端口策略和全局策略。

### 6.2 多端口与 jump（P0）
1. `mport add/remove/clear` 全链路可用。
2. `jump set/clear/replay` 支持多主端口并存。
3. 节点变体包含 base/mport/jump，且去重。

### 6.3 更新与持久化（P1）
1. 更新后 `sb` 指向 `script_root` 行为稳定。
2. update 失败可回滚，且不破坏运行态。

---

## 附录E) 非目标（Out of Scope）
1. 不在本阶段实现全新 GUI。
2. 不在本阶段引入数据库服务。
3. 不在本阶段改写为非 shell 语言。

---

## 附录F) 里程碑（建议）
1. `M1 (P0)`：矩阵明细 + mport/jump 一致性。
2. `M2 (P0)`：端口冲突与回滚边界全覆盖。
3. `M3 (P1)`：更新/回滚与脚本目录一致性。
4. `M4 (P2)`：显示优化与文档补充。

---

## 附录G) CURRENT 差距清单（待持续更新）
1. 若菜单与 CLI 描述不一致，以 `SPEC` 为后续改造目标。
2. 每完成一项 P0/P1/P2，都要同步更新本节状态。
3. [已完成 2026-02-24][P0] `apply --runtime` 增加 runtime 必填字段校验（`provider/profile/engine/protocols/script_root/installed_at`）。
4. [已完成 2026-02-24][P0] `set-port` 增加失败回滚闭环：配置回滚、防火墙新规则撤销、`port_egress_map` 分支回滚 `runtime.env/nodes`。
5. [已完成 2026-02-24][P0] 移除多个高风险 `source *.env` 路径，改为安全 env 解析加载。
6. [已完成 2026-02-24][P1] `runtime.env` 与多个 provider 凭据文件补齐最小权限（`600`），并将关键写入改为临时文件 + `mv`。
7. [进行中][P0] 基于附录 D 的真实环境验收（矩阵展示、mport/jump 全链路）仍需在目标主机执行。
