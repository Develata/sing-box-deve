# 可靠性与恢复边界

## 状态与写入入口

安装、重装、卸载、配置、端口、WARP、core 更新和脚本切换使用持久恢复记录；脚本发行采用独立的不可变版本目录。写入口共享一把 `flock`，在读取基线之前取得。root 模式控制状态位于 `/var/lib/sing-box-deve.host`，用户模式位于 `~/sing-box-deve.host`；锁不会随卸载删除，也不会由 nohup 子进程继承。

事务先保存并核验权威输入，再记录阶段，最后提交。权威集合包括 runtime/config、UUID 与密钥、Argo/WARP 参数、多端口与防火墙记录、服务定义；core 更新另外保存二进制、配套 `libcronet.so` 与 Xray `geoip.dat` / `geosite.dat`。新快照使用 schema 4，继续读取 schema 2/3 快照；旧快照只恢复其原有清单。`runtime.env` 新写入采用 schema 2 和整份 SHA256，旧格式在下一次写入时迁移。不要手改生成的 runtime 文件，使用 CLI 或 `apply -f` 输入配置。

配置快照另保存并校验 WARP SOCKS5 的运行、开机启用状态与 cron 记录。回滚先停止现有侧车，再恢复文件与原状态，避免端口文件与运行进程不一致。schema 2/3 未保存侧车生命周期：有侧车配置时沿用回滚前的运行状态，无侧车配置时保持停止，并给出提示。

防火墙操作只有在后端确认成功后才登记规则；失败会中止当前事务。新增规则先写入事务意图记录，firewalld 仅永久规则成功等部分写入也可恢复。查询失败与规则不存在分别处理；删除失败保留托管记录。防火墙单次命令默认限时 15 秒（`SBD_FIREWALL_TIMEOUT`），iptables 重复删除共享总预算。事务发布前准备失败会删除本次私有快照目录。

旧版没有托管标记的防火墙重放服务，只有在完整内容符合旧版生成模板、且启动器可确认为本项目文件时才被识别；已有归属摘要时仍优先校验摘要。文件被外部修改、附加指令或无法证明归属时，操作会在提交前中止。

普通错误、TERM/HUP/INT 会尝试恢复；SIGKILL 后由下一次写操作先恢复，也可执行：

```bash
sb recover
# 若首次安装尚未生成可用 sb，使用完整源码/发行包中的入口：
./sing-box-deve.sh recover
```

恢复失败保留 `transactions/active` 并阻止后续写操作。`recovery-failed` 不能视为恢复成功。恢复集合中的缺失文件也有记录，以撤销后来创建的身份或配置。旧版不完整 cfg snapshot 不会被冒充为 v2 快照自动恢复。

这不是跨系统 ACID：包管理、证书签发、远端 SSH 工作不能靠复制文件撤销。事务记录 Debian 包列表变化并保留共享依赖；包数据库不健康时先执行下述有界检查与一轮修复，仍可能需要管理员处理。SSH 超时不能证明远端任务已经结束，任意 bootstrap 默认不自动重试。

## 等待预算

| 操作 | 默认预算 |
|---|---|
| API/版本等小响应 | connect 5 秒，total 20 秒，响应上限 2 MiB |
| 二进制/发行包下载 | connect 15 秒，所有重试共享 300 秒 |
| 防火墙命令 | 15 秒；iptables 重复删除共享总预算 |
| service 命令 | 30 秒；健康轮询使用剩余总预算 |
| 包管理 | 每条 mutation 300 秒 + 独立 TERM 宽限 30 秒；audit 15 秒、锁探测 5 秒 |
| SSH | connect 10 秒，keepalive 10 秒 × 3，总计 180 秒 |
| core 校验与密钥生成 | 30 秒 |

普通命令 deadline 到期先 TERM，再等待默认 3 秒后 KILL；包管理使用独立策略。不能承诺中断内核不可中断 I/O，也不能撤销外部系统已经完成的动作。可用 `SBD_HTTP_TIMEOUT`、`SBD_DOWNLOAD_TOTAL_TIME`、`SBD_SERVICE_TIMEOUT`、`SBD_PACKAGE_TIMEOUT`、`SBD_SSH_TIMEOUT` 调整预算。

## 包管理失败边界

`SBD_PACKAGE_TIMEOUT` 默认 300 秒，`SBD_PACKAGE_TERM_GRACE` 默认 30 秒，不继承通用 `SBD_TIMEOUT_KILL_AFTER`。短时 Python helper 只在包操作期间运行，不增加常驻服务。它为命令创建独立进程组；超时先 TERM，保留父进程身份直到宽限期结束，再 KILL 同组残留进程。父进程先退出不会取消这段终止宽限。命令 stdin 为 `/dev/null`，Debian 使用 `DEBIAN_FRONTEND=noninteractive`。

Debian 的 apt/dpkg mutation 开始前在 host control 目录写入 `0600` 的 `package_recovery_required`。每次 mutation 前检查数据库锁和 `dpkg --audit`；失败后再次检查。audit 报告问题时，整次调用最多执行一轮有相同独立 deadline 的 `dpkg --configure -a`，随后重新 audit。不会自动运行 `apt-get -f install`、删除数据库锁或递归重试。锁被占用、audit 失败或修复后仍有问题时保留 marker 并拒绝新的 mutation；数据库经检查恢复正常后才清除 marker。修复成功也不会把原操作的失败/超时改成成功。

`package-recovery.log` 位于同一 control 目录，保存本次状态、audit 摘要和修复退出码，下次调用覆盖；包管理器的完整日志仍由主机管理。marker 不随 runtime 事务回滚或卸载消失。

这是有限补偿，不是包数据库快照回滚。`dpkg --configure -a` 可能执行主机上其他待配置包的维护脚本。进程主动脱离进程组、外部管理员同时运行包管理器、磁盘故障及内核不可中断 I/O 无法被这个 helper 完整控制；锁探测也不能替代 apt/dpkg 自身的数据库锁。修复失败时应先检查日志和 `dpkg --audit`，由管理员处理原因后再重试。参见 [Debian dpkg 手册](https://manpages.debian.org/trixie/dpkg/dpkg.1.en.html)。

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

nohup 内部启动和重启使用 argv，保留空参数、空格、等号、冒号和 Unicode。新 cron 条目使用显式 `--argv` 入口及 POSIX quoting；旧四参数 cron 和持久化 `argo-exec` 仅在边界用非执行解析器解码。未闭合引号或包含 shell 运算/展开的歧义字符串会拒绝，绝不 eval。cron 自身会解释的换行和 `%` 参数也会拒绝。

Linux nohup 状态同时记录 PID、boot ID、start time、可执行文件 inode；不会仅凭 `kill -0` 发信号。旧裸 PID 或身份冲突需要人工核实，不能直接删除 PID 文件并假定服务已停。原子替换二进制后仍可验证旧进程。传统 PID 检查与发送信号之间仍有竞态窗口，不承诺完全消除 PID reuse。

nohup 日志通过 pipe writer 连续按大小轮转，默认每文件 10 MiB、共 3 份（`SBD_LOG_MAX_BYTES`），writer 随管道 EOF 退出。systemd 服务使用 journald，由主机 journald 配额管理。OpenRC 日志仍需目标机配置 logrotate；该路径属于 best-effort。

cfg snapshot 默认保留 20 份（`SBD_CFG_SNAPSHOT_KEEP`）；事务保留最近的完成/恢复记录，未完成记录不会被清理。发行候选目录在成功切换后的持锁清理中回收。

```bash
sb uninstall --keep-settings
sb uninstall --keep-settings --purge-managed-host-changes
```

卸载在同一 mutation lock 下执行 `prepared → committing → complete`。准备阶段验证绝对/规范路径、受保护根目录、symlink 和服务/入口归属，保存带校验的权威状态、二进制及配套资产、当前/上一代脚本、节点与本地规则集、受管理 host 文件及原服务运行/启用状态。只复制清单中的恢复必需文件，不复制整个安装目录、下载缓存或日志；安装脚本快照受 64 MiB/2048 文件上限约束。外部 Git checkout 保留。

进入 `committing` 后停止受管理服务，移除已验证的 unit/launcher，删除账本中的防火墙规则，按选项撤销 host 文件，最后重新验证目录与现存文件再删除 runtime/config/state/install 根目录。防火墙账本保留到根目录删除，部分后端失败可按原记录重放。iptables/nftables 的容器可以保留，不能仅凭名称删除整个 table/chain。

普通失败及可捕获的中断会恢复已删除的关键文件、脚本选择器、服务定义、launcher 和受管理防火墙状态，daemon-reload 后只重新启动此前 active 的服务。现存文件与快照或事务已记录写入不符时拒绝覆盖，恢复失败保留 active 记录并阻止进一步 mutation。SIGKILL/reboot 后，下次能加载模块的 CLI invocation 会先恢复 unfinished uninstall；若 `sb` 或模块已删除，使用卸载前打印的持久入口：

```bash
# root 默认路径；用户模式对应 ~/sing-box-deve.host/transactions/active/recover.sh
sudo bash /var/lib/sing-box-deve.host/transactions/active/recover.sh
```

此入口携带原路径设置并获取同一把锁。恢复本身失败时，先解决报告的冲突、磁盘或服务问题，再重复该命令；不手动删除 active 指针。成功卸载会删除内部恢复快照。若已写入 `complete` 后仅快照清理失败，恢复入口重试清理，不复活已完成的卸载；恢复脚本已随清理删除时，可从完整 checkout/发行包执行 `recover`。

`--keep-settings` 的用户备份与内部事务快照独立。用户备份位于安装目录同级 `*.backup-*`，保存经过完整校验的权威状态集合（`files/config`、`files/data` 等），不包含 core 二进制，成功卸载后仍保留。

恢复不承诺重建日志、下载缓存、任意用户放入安装目录的文件或所有历史发行版本。损坏/丢失的恢复盘、持续的服务或防火墙错误、外部并发改写、已结束的连接以及外部系统效果无法自动撤销；管理员应暂停其他管理操作直到恢复结束。这不是跨文件系统的原子卸载，也不能保证恢复一定成功。

host 文件有写前基线及写后摘要，覆盖托管服务、launcher、nginx 仓库/配置与静态站文件。事务恢复会重新加载原 Web 服务状态，并补偿已记录的 BBR 内核参数；外部修改导致无法安全补偿时保留失败记录。额外的 purge 只撤销仍与托管摘要一致的 host 文件；外部修改的文件和共享包会保留。目录名字或程序名字相同不足以证明资源归属。

## 外部 bootstrap

Serv00 不再默认执行第三方 mutable main。必须配置 `SERV00_BOOTSTRAP_URL` + `SERV00_BOOTSTRAP_SHA256`，或显式提供兼容入口 `SERV00_BOOTSTRAP_CMD`。SSH 使用预先核实的 `SERV00_KNOWN_HOSTS_FILE`，不自动接受未知主机密钥；密码通过 sshpass 环境变量传递。

ACME 自动安装要求已有可执行的 `/root/.acme.sh/acme.sh`，或者显式提供经过审阅的 `SBD_ACME_INSTALLER_URL` + `SBD_ACME_INSTALLER_SHA256`。该 installer 必须支持 `--install --home`，其后续下载行为也属于调用者的信任边界。不会默认执行 `get.acme.sh`。自动签发检查证书域名、期限、密钥匹配，并注册托管证书部署及重新加载 hook。

## 验收与发布

文件长度只是维护提醒：`test-module-size.sh` 默认超过 600 行打印 warning，始终 exit 0；不再以 400 行强制拆分模块。真正的检查继续包括 ShellCheck、完整 source graph 的重复函数检测、syntax、故障注入和清单/归属验证。

本地和 CI 统一执行 `bash scripts/sing-box-deve-pre-push.sh`：逐文件 Bash syntax、shellcheck、Node/schema、CLI/firewall、并发、失败注入、archive/迁移/SIGKILL、日志和真实 stable-core 配置矩阵。

实机验收通过 SSH 独立运行 `primary-vps-acceptance.sh`，使用 Debian systemd VPS，项目运行目录必须为空、源码 checkout 必须干净。它会真实安装、重装、切换 core、运行 Reality/Argo 客户端流量、测试 WARP/上游 SOCKS、卸载并核验备份。需要显式授权，失败后保留私有诊断日志；临时使用已有部署的主机时，provisioner 必须事先核验备份并在测试结束后恢复原部署。回执记录源码 SHA、退出码、源码是否保持干净及已通过用例。

Real-host acceptance is SHA-bound. Any lifecycle-affecting commit after acceptance invalidates the previous acceptance for release purposes.

实机验收仅证明回执中的 exact commit。发行门禁更严格：任何不同 SHA（即使 runtime archive 内容相同）都不能沿用旧回执，外层回执、acceptance、restoration 的 SHA 必须全部等于 release checkout 的 HEAD。

`Publish Runtime Release` 接收维护者通过 SSH 获取的脱敏 JSON 回执；`verify-release-receipt.py` 拒绝不同源码 SHA、不完整/失败验收、未核验的原部署恢复或不同运行包 SHA256。工作流再次执行完整 suite、重建并核对运行包，随后把运行包、摘要文件和回执一起发布。不要求安装自托管 runner；`Primary VPS Acceptance` workflow 保留为可选执行方式，不能代替发布所需的恢复证据。

回执是有发布权限的维护者对 SSH 执行结果的确认，不是独立签名或对远端主机的密码学证明。它不包含 SSH/sudo 凭据、节点链接、主机地址或私有日志。执行步骤和字段约定见 [REAL-WORLD-VALIDATION.md](REAL-WORLD-VALIDATION.md)。静态 CI 通过不能替代实机 gate。Ubuntu 未在本轮实机验证，真实域名 ACME、OpenRC、FreeBSD/Serv00 和长期负载仍需相应目标环境的额外证据。
