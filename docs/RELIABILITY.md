# 可靠性与恢复边界

## 状态与写入入口

安装、重装、配置、端口、WARP、core 更新和脚本切换使用持久恢复记录；脚本发行采用独立的不可变版本目录。写入口共享一把 `flock`，在读取基线之前取得。root 模式控制状态位于 `/var/lib/sing-box-deve.host`，用户模式位于 `~/sing-box-deve.host`；锁不会随卸载删除，也不会由 nohup 子进程继承。

事务先保存并核验权威输入，再记录阶段，最后提交。权威集合包括 runtime/config、UUID 与密钥、Argo/WARP 参数、多端口与防火墙记录、服务定义；core 更新另外保存二进制及配套 `libcronet.so`。新快照使用 schema 3，继续读取 schema 2 快照；schema 2 未记录动态库，因此只恢复其原有清单。`runtime.env` 新写入采用 schema 2 和整份 SHA256，旧格式在下一次写入时迁移。不要手改生成的 runtime 文件，使用 CLI 或 `apply -f` 输入配置。

旧版没有托管标记的防火墙重放服务，只有在完整内容符合旧版生成模板、且启动器可确认为本项目文件时才被识别；已有归属摘要时仍优先校验摘要。文件被外部修改、附加指令或无法证明归属时，操作会在提交前中止。

普通错误、TERM/HUP/INT 会尝试恢复；SIGKILL 后由下一次写操作先恢复，也可执行：

```bash
sb recover
# 若首次安装尚未生成可用 sb，使用完整源码/发行包中的入口：
./sing-box-deve.sh recover
```

恢复失败保留 `transactions/active` 并阻止后续写操作。`recovery-failed` 不能视为恢复成功。恢复集合中的缺失文件也有记录，以撤销后来创建的身份或配置。旧版不完整 cfg snapshot 不会被冒充为 v2 快照自动恢复。

这不是跨系统 ACID：包管理、证书签发、远端 SSH 工作不能靠复制文件撤销。事务记录 Debian 包列表变化并保留共享依赖；中断的 dpkg 仍可能需要管理员检查 `dpkg --audit`。SSH 超时不能证明远端任务已经结束，任意 bootstrap 默认不自动重试。

## 等待预算

| 操作 | 默认预算 |
|---|---|
| API/版本等小响应 | connect 5 秒，total 20 秒，响应上限 2 MiB |
| 二进制/发行包下载 | connect 15 秒，所有重试共享 300 秒 |
| service 命令 | 30 秒；健康轮询使用剩余总预算 |
| 包管理 | 300 秒，APT 自身另有限制 |
| SSH | connect 10 秒，keepalive 10 秒 × 3，总计 180 秒 |
| core 校验与密钥生成 | 30 秒 |

命令 deadline 到期先 TERM，再等待默认 3 秒后 KILL。不能承诺中断内核不可中断 I/O，也不能撤销外部系统已经完成的动作。可用 `SBD_HTTP_TIMEOUT`、`SBD_DOWNLOAD_TOTAL_TIME`、`SBD_SERVICE_TIMEOUT`、`SBD_PACKAGE_TIMEOUT`、`SBD_SSH_TIMEOUT` 调整预算。

## 脚本发行与迁移

TUIC 退役后仍保留旧 runtime 的解码，供状态查看和完整脚本更新/回退使用；配置修改与核心更新在事务开始前拒绝含 TUIC 的部署。含退役协议的配置快照在进入提交阶段前拒绝恢复；失败的脚本事务保留旧节点产物，不用删掉协议后的生成器覆盖它们。升级前的显式迁移步骤见 [README](../README.md#tuic-退役与旧部署升级)。

默认安装会把源码打包为 runtime，再部署到 `releases/<version>-<digest>`。`current` 通过原子 symlink 选择完整版本；入口在加载模块前解析物理目录。`sb` 从安装对应的 `runtime.env` 读取根目录，不跟随当前工作目录。源码调试继续使用 `./sing-box-deve.sh`。

显式 Git 绑定是可选来源：封存的 `runtime.env` 记录固定目录、所有者 UID 和绑定前的完整回退版本；`current` 保留独立的恢复实现。绑定、解除和 Release 更新沿用脚本事务，不重启核心；失败恢复只还原脚本选择器、运行状态和相关托管文件，不重建节点或操作服务。旧 runtime 无来源字段时按 Release 语义兼容，回到 Release 时移除新增字段，便于旧版读取。

绑定入口在执行可变源码前使用 launcher 内保存的校验器验证清单、摘要、路径与权限。缺失或损坏时明确失败，`sb --rollback-source` 通过保留的完整 Release 解除绑定。Git HEAD/摘要检查可发现部分并发改写，但不能保证普通 `git pull` 与 Bash 加载之间的原子性；须先退出菜单并暂停管理操作。配置快照只恢复业务状态，不恢复旧的来源绑定；卸载保留外部 checkout。操作说明见 [README](../README.md#git-工作目录与已安装脚本)。

发行包只含 entrypoint、version/LICENSE、lib/providers/rulesets 和必要 runtime helper。网页、测试和 CI 文件不随 runtime 下载。包内包含非执行的完整文件清单与摘要，拒绝路径穿越、链接、重复条目和超限包。

```bash
sb update --script --yes
sb update --rollback
# 私有镜像或离线文件必须提供已核实的完整包摘要：
SBD_RELEASE_ARCHIVE_URL=<url> SBD_RELEASE_SHA256=<sha256> sb update --release --yes
```

默认从项目 GitHub Release 读取 `sing-box-deve-runtime.tar.gz` 及其 asset digest。第一次使用新 updater 时先保存旧 runtime 为完整上一代；不会逐文件覆盖 checkout。仓库尚无此资产时必须先完成发行流程，或显式提供包和摘要。raw entrypoint bootstrap 同样依赖已发布 runtime 资产与 Python 3。

`--source` / `--force` 保留参数兼容；发行选择由 `SBD_RELEASE_TAG` 或显式 URL/digest 控制。旧 `SBD_UPDATE_BASE_URL` 仅用于版本信息探测。SHA256 与同源 Release 元数据提供传输/完整性校验，不等于独立签名。

默认保留 3 代，包括 current/previous；二者与 Git 绑定前的回退版本始终保留。可用 `SBD_RELEASE_KEEP` 调整，或在 `release-pins/<版本目录名>` 创建保留标记。标记放在版本目录外，避免修改不可变 payload。

## 进程、日志与卸载

Linux nohup 状态同时记录 PID、boot ID、start time、可执行文件 inode；不会仅凭 `kill -0` 发信号。旧裸 PID 或身份冲突需要人工核实，不能直接删除 PID 文件并假定服务已停。原子替换二进制后仍可验证旧进程。传统 PID 检查与发送信号之间仍有竞态窗口，不承诺完全消除 PID reuse。

nohup 日志通过 pipe writer 连续按大小轮转，默认每文件 10 MiB、共 3 份（`SBD_LOG_MAX_BYTES`），writer 随管道 EOF 退出。systemd 服务使用 journald，由主机 journald 配额管理。OpenRC 日志仍需目标机配置 logrotate；该路径属于 best-effort。

cfg snapshot 默认保留 20 份（`SBD_CFG_SNAPSHOT_KEEP`）；事务保留最近的完成/恢复记录，未完成记录不会被清理。发行候选目录在成功切换后的持锁清理中回收。

```bash
sb uninstall --keep-settings
sb uninstall --keep-settings --purge-managed-host-changes
```

卸载先验证目录边界及服务/入口归属，停止进程后才删状态。备份位于安装目录的同级 `*.backup-*`，保存经过完整校验的 v2 权威状态集合（`files/config`、`files/data` 等），不包含 core 二进制。它不在删除集合内。

host 文件有写前基线及写后摘要，覆盖托管服务、launcher、nginx 仓库/配置与静态站文件。事务恢复会重新加载原 Web 服务状态，并补偿已记录的 BBR 内核参数；外部修改导致无法安全补偿时保留失败记录。额外的 purge 只撤销仍与托管摘要一致的 host 文件；外部修改的文件和共享包会保留。目录名字或程序名字相同不足以证明资源归属。

## 外部 bootstrap

Serv00 不再默认执行第三方 mutable main。必须配置 `SERV00_BOOTSTRAP_URL` + `SERV00_BOOTSTRAP_SHA256`，或显式提供兼容入口 `SERV00_BOOTSTRAP_CMD`。SSH 使用预先核实的 `SERV00_KNOWN_HOSTS_FILE`，不自动接受未知主机密钥；密码通过 sshpass 环境变量传递。

ACME 自动安装要求已有可执行的 `/root/.acme.sh/acme.sh`，或者显式提供经过审阅的 `SBD_ACME_INSTALLER_URL` + `SBD_ACME_INSTALLER_SHA256`。该 installer 必须支持 `--install --home`，其后续下载行为也属于调用者的信任边界。不会默认执行 `get.acme.sh`。自动签发检查证书域名、期限、密钥匹配，并注册托管证书部署及重新加载 hook。

## 验收与发布

本地和 CI 统一执行 `bash scripts/sing-box-deve-pre-push.sh`：逐文件 Bash syntax、shellcheck、Node/schema、CLI/firewall、并发、失败注入、archive/迁移/SIGKILL、日志和真实 stable-core 配置矩阵。

实机验收通过 SSH 独立运行 `primary-vps-acceptance.sh`，使用 Debian systemd VPS，项目运行目录必须为空、源码 checkout 必须干净。它会真实安装、重装、切换 core、运行 Reality/Argo 客户端流量、测试 WARP/上游 SOCKS、卸载并核验备份。需要显式授权，失败后保留私有诊断日志；临时使用已有部署的主机时，provisioner 必须事先核验备份并在测试结束后恢复原部署。回执记录源码 SHA、退出码、源码是否保持干净及已通过用例。

`Publish Runtime Release` 接收维护者通过 SSH 获取的脱敏 JSON 回执；`verify-release-receipt.py` 拒绝不同源码 SHA、不完整/失败验收、未核验的原部署恢复或不同运行包 SHA256。工作流再次执行完整 suite、重建并核对运行包，随后把运行包、摘要文件和回执一起发布。不要求安装自托管 runner；`Primary VPS Acceptance` workflow 保留为可选执行方式，不能代替发布所需的恢复证据。

回执是有发布权限的维护者对 SSH 执行结果的确认，不是独立签名或对远端主机的密码学证明。它不包含 SSH/sudo 凭据、节点链接、主机地址或私有日志。执行步骤和字段约定见 [REAL-WORLD-VALIDATION.md](REAL-WORLD-VALIDATION.md)。静态 CI 通过不能替代实机 gate。Ubuntu 未在本轮实机验证，真实域名 ACME、OpenRC、FreeBSD/Serv00 和长期负载仍需相应目标环境的额外证据。
