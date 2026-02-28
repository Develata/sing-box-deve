# Docker 使用说明

本文说明如何通过 `sing-box-deve` 使用 Docker 模式。

## 1) 基础执行

```bash
./sing-box-deve.sh install --provider docker --profile lite --engine sing-box --protocols vless-reality
```

执行后会生成：

- `/etc/sing-box-deve/docker.env`
- `/etc/sing-box-deve/docker-compose.yml`
- `/etc/sing-box-deve/docker-run.sh`
- `/etc/sing-box-deve/docker-healthcheck.sh`

## 2) 使用 Dockerfile 构建

项目根目录提供 `Dockerfile`，可直接构建镜像：

```bash
docker build -t sing-box-deve .
docker run -d --name sbd -p 3000:3000 -e UUID=your-uuid sing-box-deve
```

### Container Node.js 网关

`container/nodejs/` 目录包含容器内的 VLESS-WS 协议网关：

- `index.js` — HTTP 服务 + WebSocket VLESS 代理
- `start.sh` — 容器启动脚本（自动检测 IP、下载引擎、配置 Argo）

## 3) 自定义镜像

```bash
export SBD_DOCKER_IMAGE="ghcr.io/develata/sing-box-deve:latest"
./sing-box-deve.sh install --provider docker --profile full --engine sing-box --protocols vless-reality,hysteria2
```

## 4) 使用示例 env

可直接参考：`examples/docker.env`

## 5) 注意事项

- 默认使用 host network，部署前请确认端口规划
- Docker 模式仍遵循脚本安全策略（防火墙增量与回滚）
- SAP Cloud Foundry 部署也使用此 Docker 镜像
