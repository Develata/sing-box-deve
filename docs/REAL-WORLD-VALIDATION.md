# 实机验收执行单（含 PASS/FAIL 判定）

> 目标：覆盖 `VPS/Serv00/SAP/Docker × Lite/Full × Argo/WARP/上游代理` 的关键组合。
> 要求：在真实目标环境、root 权限下执行。

## 0) 基线准备

- 系统：Ubuntu/Debian
- 权限：root
- 网络：可访问 GitHub、Cloudflare（如测试 Argo/WARP）

执行：

```bash
sudo ./sing-box-deve.sh version
sudo ./sing-box-deve.sh doctor
```

PASS 判定：

- `doctor` 无致命错误（可有 warning）
- 能正确显示脚本版本

FAIL 判定：

- `doctor` 直接退出且无法定位原因
- 基础依赖缺失且无法自动安装

---

## 1) VPS Lite 基线（必测）

```bash
sudo ./sing-box-deve.sh install --provider vps --profile lite --engine sing-box --protocols vless-reality --yes
sudo ./sing-box-deve.sh panel
sudo ./sing-box-deve.sh list
```

PASS：

- `panel` 显示 core service `running`
- `list` 输出 vless 节点
- `doctor` 端口监听检查通过

FAIL：

- 服务启动失败
- 节点未生成

---

## 2) VPS Full + Argo（必测）

```bash
sudo ./sing-box-deve.sh install --provider vps --profile full --engine xray --protocols vless-reality,vmess-ws,argo --argo temp --yes
sudo ./sing-box-deve.sh panel
sudo ./sing-box-deve.sh doctor
```

PASS：

- Argo sidecar 运行中
- `doctor` 显示 Argo domain 检测通过（或已生成）

FAIL：

- Argo service 一直 inactive
- 无法生成/识别 Argo 域名

---

## 3) VPS 上游出站代理（必测）

```bash
sudo ./sing-box-deve.sh install --provider vps --profile lite --engine sing-box --protocols vless-reality \
  --outbound-proxy-mode socks --outbound-proxy-host <host> --outbound-proxy-port <port> \
  --outbound-proxy-user <user> --outbound-proxy-pass <pass> --yes
sudo ./sing-box-deve.sh panel
sudo ./sing-box-deve.sh doctor
```

PASS：

- `panel` 中 Egress 为 `socks`
- `doctor` 中 Outbound proxy diagnostic 显示 host/port

FAIL：

- 配置未生效（仍为 direct）
- 出站代理字段缺失或报错

---

## 4) WARP（与上游代理互斥）

```bash
sudo WARP_PRIVATE_KEY=<key> WARP_PEER_PUBLIC_KEY=<peer> \
./sing-box-deve.sh install --provider vps --profile full --engine sing-box --protocols vless-reality,warp --warp-mode global --yes
```

PASS：

- 安装成功且 `panel` 显示 WARP `global`

FAIL：

- 缺 key 未被拦截
- 与 outbound proxy 同时开启未被拦截

---

## 5) Serv00（单账号 + 批量）

单账号：

```bash
export SERV00_HOST=<host>
export SERV00_USER=<user>
export SERV00_PASS=<pass>
sudo ./sing-box-deve.sh install --provider serv00 --profile lite --engine sing-box --protocols vless-reality
```

批量：

```bash
export SERV00_ACCOUNTS_JSON="$(cat examples/serv00-accounts.json)"
export SERV00_RETRY_COUNT=1
sudo ./sing-box-deve.sh install --provider serv00 --profile full --engine sing-box --protocols vless-reality
```

PASS：

- 显示批量 summary（total/success/failed/skipped）
- 失败项有清晰提示

FAIL：

- JSON 缺字段未被拦截
- summary 不准确

---

## 6) SAP（单账号 + 批量）

单账号：

```bash
export SAP_CF_API=<api>
export SAP_CF_USERNAME=<user>
export SAP_CF_PASSWORD=<pass>
export SAP_CF_ORG=<org>
export SAP_CF_SPACE=<space>
export SAP_APP_NAME=<app>
sudo ./sing-box-deve.sh install --provider sap --profile full --engine sing-box --protocols vless-reality
```

批量：

```bash
export SAP_ACCOUNTS_JSON="$(cat examples/sap-accounts.json)"
export SAP_RETRY_COUNT=1
sudo ./sing-box-deve.sh install --provider sap --profile full --engine sing-box --protocols vless-reality
```

PASS：

- 批量 summary 正确
- 部署失败可定位到具体 app

FAIL：

- 缺字段未被校验
- 重试逻辑无效

---

## 7) Docker

```bash
sudo ./sing-box-deve.sh install --provider docker --profile lite --engine sing-box --protocols vless-reality
sudo /etc/sing-box-deve/docker-healthcheck.sh
```

PASS：

- 生成 `docker.env` / `docker-compose.yml`
- 容器运行状态正常

FAIL：

- 文件未生成
- 容器启动失败无提示

---

## 8) 更新与回滚

```bash
sudo ./sing-box-deve.sh update --core --yes
sudo ./sing-box-deve.sh fw status
```

PASS：

- core 更新成功并自动重启
- 防火墙规则仍可追踪

FAIL：

- 更新后服务不可用
- 防火墙状态异常

---

## 9) 最终验收结论模板

```text
环境：<OS/内存/架构>
场景覆盖：VPS[PASS] Serv00[PASS/FAIL] SAP[PASS/FAIL] Docker[PASS/FAIL]
功能覆盖：Lite[PASS] Full[PASS] Argo[PASS] WARP[PASS] 上游代理[PASS]
安全检查：防火墙增量[PASS] 回滚[PASS] 更新校验[PASS]
结论：<可发布/需修复后发布>
```
