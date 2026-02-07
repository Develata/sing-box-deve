#!/usr/bin/env bash

provider_docker_install() {
  local profile="$1"
  local engine="$2"
  local protocols_csv="$3"

  validate_feature_modes
  mkdir -p /etc/sing-box-deve
  local docker_image
  docker_image="${SBD_DOCKER_IMAGE:-ghcr.io/sing-box-deve/sing-box-deve:latest}"

  cat > /etc/sing-box-deve/docker.env <<EOF
PROFILE=${profile}
ENGINE=${engine}
PROTOCOLS=${protocols_csv}
ARGO_MODE=${ARGO_MODE:-off}
ARGO_DOMAIN=${ARGO_DOMAIN:-}
ARGO_TOKEN=${ARGO_TOKEN:-}
WARP_MODE=${WARP_MODE:-off}
OUTBOUND_PROXY_MODE=${OUTBOUND_PROXY_MODE:-direct}
OUTBOUND_PROXY_HOST=${OUTBOUND_PROXY_HOST:-}
OUTBOUND_PROXY_PORT=${OUTBOUND_PROXY_PORT:-}
OUTBOUND_PROXY_USER=${OUTBOUND_PROXY_USER:-}
OUTBOUND_PROXY_PASS=${OUTBOUND_PROXY_PASS:-}
WARP_PRIVATE_KEY=${WARP_PRIVATE_KEY:-}
WARP_PEER_PUBLIC_KEY=${WARP_PEER_PUBLIC_KEY:-}
EOF
  cat > /etc/sing-box-deve/docker-compose.yml <<EOF
services:
  sing-box-deve:
    image: ${docker_image}
    container_name: sing-box-deve
    restart: unless-stopped
    env_file:
      - /etc/sing-box-deve/docker.env
    network_mode: host
EOF

  if command -v docker >/dev/null 2>&1; then
    if docker compose version >/dev/null 2>&1; then
      if prompt_yes_no "$(msg "现在启动 docker compose 部署吗？" "Start docker compose deployment now?")" "Y"; then
        docker compose -f /etc/sing-box-deve/docker-compose.yml up -d || die "docker compose up failed"
      else
        log_warn "$(msg "用户已跳过 docker compose 启动" "Docker compose start skipped by user")"
      fi
      log_success "Docker provider deployed via docker compose"
    else
      if prompt_yes_no "$(msg "现在通过 docker run 启动容器吗？" "Start docker container now (docker run)?")" "Y"; then
        docker run -d --name sing-box-deve --restart unless-stopped --network host --env-file /etc/sing-box-deve/docker.env "${docker_image}" || \
          log_warn "Docker run failed; verify image and env values"
      else
        log_warn "$(msg "用户已跳过 docker run 启动" "Docker run skipped by user")"
      fi
    fi
  else
    log_warn "Docker not installed; generated compose/env files only"
  fi

  cat > /etc/sing-box-deve/docker-run.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if command -v docker >/dev/null 2>&1; then
  if docker compose version >/dev/null 2>&1; then
    docker compose -f /etc/sing-box-deve/docker-compose.yml up -d
  else
    echo "docker compose not available, use docker run manually"
  fi
else
  echo "docker is not installed"
  exit 1
fi
EOF
  chmod +x /etc/sing-box-deve/docker-run.sh

  cat > /etc/sing-box-deve/docker-healthcheck.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if ! command -v docker >/dev/null 2>&1; then
  echo "docker not installed"
  exit 1
fi

docker ps --format '{{.Names}} {{.Status}}' | grep '^sing-box-deve ' || {
  echo "sing-box-deve container not running"
  exit 1
}

echo "sing-box-deve container is running"
EOF
  chmod +x /etc/sing-box-deve/docker-healthcheck.sh

  log_success "Docker deployment bundle generated at /etc/sing-box-deve/docker.env and docker-compose.yml"
  return 0
}
