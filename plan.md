# sing-box-deve 计划文档（瘦身后主线）

## 1) 项目本体

`sing-box-deve` 管理六类对象：host、runtime、public inbounds、outbounds、artifacts、safety state。主线只保留直接服务这些对象的能力。

## 2) 保留能力

- 安装/重装：`wizard`, `install`, `apply -f`, `apply --runtime`
- 状态：`panel`, `list`, `doctor`, `logs`, `restart`
- 协议：`vless-reality`, `vless-ws`, `vless-xhttp`(xray compatibility), `shadowsocks-2022`, `naive`, `hysteria2`, `tuic`
- 端口：`set-port`, `mport`
- 出站：`set-egress`, `set-route`, `split3`
- 特性：Argo, WARP outbound
- 订阅：`sub refresh/show/rules-update`
- 安全：firewall managed rules, cfg snapshots/rollback, update checksums

## 3) 已裁剪能力

- SAP Cloud Foundry provider
- Workers templates
- Psiphon sidecar
- SFW Windows client packaging
- GitLab/TG subscription push
- jump port redirect
- set-share endpoint rewriting
- set-port-egress per-port outbound policy
- `anytls` / `trojan` public inbound

## 4) 验收标准

1. `help` 不出现已裁剪命令。
2. `protocol matrix` 不出现已裁剪协议。
3. `install --dry-run --provider vps --profile lite --engine sing-box --protocols vless-reality` 不写持久状态。
4. `bash -n`, shellcheck, CLI smoke, consistency, firewall-record tests, checksum verification 全部通过。
5. root 实机验证覆盖 VPS lite baseline、VPS full + Argo、WARP、上游代理、Serv00 best-effort。


## 6) 2026-09 reliability hardening（用户已授权执行）

目标：修复审查中已经复现的失败传播、env codec、更新清单演进、状态恢复、进程与卸载问题，并建立有限等待、统一写入串行化及可恢复发行机制。保持现有 CLI 和 VPS/Bash 技术栈；不在开发机安装真实服务或执行远端发布。

执行顺序：基础正确性 → I/O/进程/锁 → 权威状态快照与安装恢复 → runtime 发行及 CI → 实机验收。

约束与状态归属：

- 库函数对关键副作用显式返回错误；命令边界捕获失败并执行恢复，不能依赖条件上下文中的 errexit。
- mutation 锁在读入基线前取得，保护 install/apply/cfg/core/script update/uninstall 及直接写入口；锁不随安装目录删除。只读命令不持有长期写锁。
- `runtime.env`、身份/端口等 data 输入是恢复集合；配置/订阅为衍生产物。快照恢复输入之后再重建，缺失文件也必须记录，以撤销后来新增的状态。
- 安装恢复保留原配置、data、binary、service、firewall 与 host ownership；host 包管理的副作用只做可证明的补偿，失败时保留恢复记录，不能声称完整 ACID。
- 脚本 runtime 是不可变版本目录；`current` 是唯一版本选择器；入口先解析物理根再加载模块。旧 checkout 和已安装入口不会因当前目录不同而切换。
- 发行 archive 在候选目录验证格式、路径、摘要与加载图后切换；恢复与迁移保留上一代。网络使用分类型 deadline，重试次数和单次/总预算均有限。
- Serv00 remote 执行必须显式配置受信任 backend，核验主机密钥；不默认执行第三方 mutable main。
- 卸载仅移除可证明归属的资源；备份不得位于删除集合内。长期日志、快照和旧发行有默认保留策略。

验收：每个审查缺陷有旧版可失败的新回归；并发用两进程，I/O 用黑洞/半包/阻塞替身，发行切换覆盖新增模块与 SIGKILL；完整本地 pre-push 与 current-core suite；Ubuntu/Debian 实机 gate 需单独记录，不能用静态/mock 测试替代。发布需要另行明确 push 授权。
