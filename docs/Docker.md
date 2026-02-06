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

## 2) 自定义镜像

```bash
export SBD_DOCKER_IMAGE="ghcr.io/develata/sing-box-deve:latest"
./sing-box-deve.sh install --provider docker --profile full --engine sing-box --protocols vless-reality,hysteria2
```

## 3) 使用示例 env

可直接参考：`examples/docker.env`

## 4) 注意事项

- 默认使用 host network，部署前请确认端口规划
- Docker 模式仍遵循脚本安全策略（防火墙增量与回滚）
