FROM node:18-alpine

LABEL maintainer="Develata <https://github.com/Develata/sing-box-deve>"
LABEL description="sing-box-deve multi-protocol proxy container"

RUN apk add --no-cache bash curl jq openssl tar unzip ca-certificates \
    iproute2 wireguard-tools tzdata && \
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone

WORKDIR /app

COPY container/nodejs/package.json ./
RUN npm install --production

COPY container/nodejs/index.js ./
COPY container/nodejs/start.sh ./
COPY sing-box-deve.sh ./
COPY lib/ ./lib/
COPY providers/ ./providers/
COPY rulesets/ ./rulesets/

RUN chmod +x start.sh sing-box-deve.sh

ENV PORT=3000
ENV ENGINE=sing-box
ENV PROTOCOLS=vless-reality,vmess-ws
ENV ARGO_MODE=off
ENV WARP_MODE=off

EXPOSE ${PORT}

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD curl -fs http://localhost:${PORT}/health || exit 1

CMD ["npm", "start"]
