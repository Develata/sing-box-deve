# 命名与目录规范

本项目的命名和目录规则尽量向上游官方风格靠拢（尤其是 sing-box）。

## 1) 配置文件命名

- sing-box 主配置：`/etc/sing-box-deve/config.json`
  - 对齐 sing-box 官方常见命名（`config.json`）
- xray 配置：`/etc/sing-box-deve/xray-config.json`

## 2) 目录约定

- 运行配置目录：`/etc/sing-box-deve`
- 状态目录：`/var/lib/sing-box-deve`
- 临时目录：`/run/sing-box-deve`
- 二进制与数据目录：`/opt/sing-box-deve/{bin,data}`

## 3) 命名风格

- 文件与目录统一使用 `kebab-case`
- 环境变量统一使用 `UPPER_SNAKE_CASE`
- 协议标识使用 sing-box / xray 生态通用命名（如 `vless-reality`、`hysteria2`）

## 4) 服务命名

- 主服务：`sing-box-deve.service`
- Argo sidecar：`sing-box-deve-argo.service`

## 5) 兼容原则

- 优先保证与上游配置语义一致
- 避免引入与官方冲突的缩写或魔改字段命名
