# Serv00 使用说明

本文说明如何通过 `sing-box-deve` 使用 Serv00 模式。

## 1) 单账号远程引导

先准备环境变量：

```bash
export SERV00_HOST="s0.serv00.com"
export SERV00_USER="your_user"
export SERV00_PASS="your_pass"
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

默认引导命令可通过 `SERV00_BOOTSTRAP_CMD` 覆盖：

```bash
export SERV00_BOOTSTRAP_CMD='bash <(curl -Ls https://your-script-url)'
```

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

使用 `serv00.yml` 工作流，在 Secrets 中设置 `SERV00_HOSTS` / `SERV00_USERS` / `SERV00_PASSES`。

## 6) 注意事项

- 建议先在单账号验证后再批量执行
- 批量模式下会逐账号确认
- 账号信息建议通过 CI Secrets 或本地安全方式注入，不要明文提交
- Serv00 为 FreeBSD 环境，脚本已自动适配 FreeBSD 特性
- 使用非 root 模式时，所有文件存储在 `~/sing-box-deve/` 下
