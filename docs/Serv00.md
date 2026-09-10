# Serv00 使用说明

本文说明如何通过 `sing-box-deve` 使用 Serv00 模式。

## 1) 单账号远程引导

先准备环境变量：

```bash
export SERV00_HOST="s0.serv00.com"
export SERV00_USER="your_user"
export SERV00_PASS="your_pass"
export SERV00_KNOWN_HOSTS_FILE="$HOME/.ssh/known_hosts"
export SERV00_BOOTSTRAP_URL="https://your-host.example/releases/backend.sh"
export SERV00_BOOTSTRAP_SHA256="<经独立核实的 SHA256>"
```

执行：

```bash
./sing-box-deve.sh install --provider serv00 --profile lite --engine sing-box --protocols vless-reality
```

脚本会在执行前给出确认提示，按 `Y/n` 决定，回车走默认。

## 2) 多账号批量引导

使用 `examples/serv00-accounts.json` 作为模板，填好后：

```bash
export SERV00_ACCOUNTS_JSON="$(cat examples/serv00-accounts.json)"
./sing-box-deve.sh install --provider serv00 --profile lite --engine sing-box --protocols vless-reality
```

## 3) 可选自定义引导命令

没有默认第三方引导命令。优先设置固定 URL 和摘要；只有确认远端现有入口的行为与幂等性后，才使用兼容入口：

```bash
export SERV00_BOOTSTRAP_CMD='bash "$HOME/reviewed-backend/install.sh"'
```

该命令由使用者负责审阅，其后续下载不由本项目的摘要检查覆盖。

## 4) Web 管理服务 (app.js)

Serv00 环境下提供 Node.js Web 管理服务，支持以下端点：

| 路径 | 功能 |
|------|------|
| `/up` | 触发保活（运行 serv00keep.sh） |
| `/re` | 重启核心引擎进程 |
| `/rp` | 重置节点端口 |
| `/jc` | 查看当前系统进程 |
| `/list/:uuid` | 查看节点与订阅信息 |
| `/health` | 健康检查 |

部署方法：

```bash
# 在 Serv00 上
cd ~/sing-box-deve/scripts
node serv00-app.js &
```

设置环境变量 `SBD_UUID` 来保护 `/list` 端点。

## 5) 保活方案

### 方案一：serv00keep.sh 本地保活

```bash
# 部署到 Serv00
bash ~/sing-box-deve/scripts/serv00keep.sh
# 添加 crontab
*/5 * * * * bash ~/sing-box-deve/scripts/serv00keep.sh >> /tmp/keepalive.log 2>&1
```

### 方案二：GitHub Actions 保活

使用 `ssh-keepalive.yml` 工作流，在 Secrets 中设置 `KEEPALIVE_URLS`：

```
http://user.serv00.net/up http://user2.serv00.net/up
```

### 方案三：VPS / 路由器远程保活

使用 `scripts/kp.sh`：

```bash
# 单次执行
KP_URLS="http://user.serv00.net/up" bash scripts/kp.sh

# 循环模式（默认每 135 分钟）
KP_URLS="http://user.serv00.net/up" bash scripts/kp.sh --loop

# 安装为 crontab
KP_URLS="http://user.serv00.net/up" bash scripts/kp.sh --install-cron
```

### 方案四：GitHub Actions SSH 部署

使用 `serv00.yml` 工作流，在 Secrets 中设置 `SERV00_ACCOUNTS_JSON` 和经过核实的 `SERV00_KNOWN_HOSTS`，在 Variables 中设置 `SERV00_BOOTSTRAP_URL` / `SERV00_BOOTSTRAP_SHA256`。

## 6) 注意事项

- 建议先在单账号验证后再批量执行
- 批量模式下会逐账号确认
- 账号信息建议通过 CI Secrets 或本地安全方式注入，不要明文提交
- Serv00 为 FreeBSD 环境；远端 backend 必须支持该平台，当前本地回归不能替代 Serv00 实机验证
- 使用非 root 模式时，所有文件存储在 `~/sing-box-deve/` 下


## Bootstrap 信任与超时

远端执行前必须提供 `SERV00_BOOTSTRAP_URL` + `SERV00_BOOTSTRAP_SHA256` 或明确的 `SERV00_BOOTSTRAP_CMD`。准备已经核实主机指纹的 `SERV00_KNOWN_HOSTS_FILE`；脚本不关闭 host-key 检查。账号 JSON 使用独立 FD，SSH 不读取账号流。超时后不推断远端已经停止；仅在 backend 明确幂等并设置 `SERV00_BOOTSTRAP_IDEMPOTENT=true` 时重试。
