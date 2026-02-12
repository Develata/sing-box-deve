#!/usr/bin/env bash

usage() {
  cat <<'EOF'
Usage:
  sing-box-deve.sh wizard
  sing-box-deve.sh menu
  sing-box-deve.sh install [--provider vps|serv00|sap|docker] [--profile lite|full] [--engine sing-box|xray] [--protocols p1,p2] [--port-mode random|manual] [--port-map proto:port[,proto:port...]] [--main-port PORT|--random-main-port] [--argo off|temp|fixed] [--argo-domain DOMAIN] [--argo-token TOKEN] [--cdn-endpoints HOST:PORT:TLS,...] [--psiphon-enable on|off] [--psiphon-mode off|proxy|global] [--psiphon-region auto|cc] [--warp-mode off|global|s|s4|s6|x|x4|x6|...] [--route-mode direct|global-proxy|cn-direct|cn-proxy] [--port-egress-map <port:direct|proxy|warp|psiphon,...>] [--outbound-proxy-mode direct|socks|http|https] [--outbound-proxy-host HOST] [--outbound-proxy-port PORT] [--outbound-proxy-user USER] [--outbound-proxy-pass PASS] [--reality-sni SNI] [--reality-fp FP] [--tls-sni SNI] [--vmess-ws-path PATH] [--vless-ws-path PATH] [--vless-xhttp-path PATH] [--vless-xhttp-mode MODE] [--xray-vless-enc true|false] [--xray-xhttp-reality true|false] [--cdn-host-vmess HOST] [--cdn-host-vless-ws HOST] [--cdn-host-vless-xhttp HOST] [--proxyip-vmess IP] [--proxyip-vless-ws IP] [--proxyip-vless-xhttp IP] [--direct-share-endpoints CSV] [--proxy-share-endpoints CSV] [--warp-share-endpoints CSV] [--yes]
  sing-box-deve.sh apply -f config.env
  sing-box-deve.sh apply --runtime
  sing-box-deve.sh list [--runtime|--nodes|--settings|--all]
  sing-box-deve.sh panel [--compact|--full]           (alias: status)
  sing-box-deve.sh restart [--core|--argo|--all]
  sing-box-deve.sh logs [--core|--argo]
  sing-box-deve.sh set-port --list
  sing-box-deve.sh set-port --protocol <name> --port <1-65535>
  sing-box-deve.sh set-port-egress --list|--clear|--map <port:direct|proxy|warp|psiphon,...>
  sing-box-deve.sh set-egress --mode direct|socks|http|https [--host HOST] [--port PORT] [--user USER] [--pass PASS]
  sing-box-deve.sh set-route <direct|global-proxy|cn-direct|cn-proxy>
  sing-box-deve.sh set-share <direct|proxy|warp> <host:port[,host:port...]>
  sing-box-deve.sh split3 show
  sing-box-deve.sh split3 set <direct_csv> <proxy_csv> <block_csv>
  sing-box-deve.sh jump show|replay|set <protocol> <main_port> <extra_csv>|clear [protocol] [main_port]
  sing-box-deve.sh mport list|add <protocol> <port>|remove <protocol> <port>|clear
  sing-box-deve.sh sub refresh|show|rules-update
  sing-box-deve.sh sub gitlab-set <token> <group/project> [branch] [path]
  sing-box-deve.sh sub gitlab-push
  sing-box-deve.sh sub tg-set <bot_token> <chat_id>
  sing-box-deve.sh sub tg-push
  sing-box-deve.sh cfg preview <rotate-id|argo|psiphon|ip-pref|cdn-host|domain-split|tls|protocol-add|protocol-remove|rebuild> ...
  sing-box-deve.sh cfg apply <rotate-id|argo|psiphon|ip-pref|cdn-host|domain-split|tls|protocol-add|protocol-remove|rebuild> ...
  sing-box-deve.sh cfg rollback [snapshot_id|latest]
  sing-box-deve.sh cfg snapshots list
  sing-box-deve.sh cfg snapshots prune [keep_count]
  sing-box-deve.sh cfg rotate-id
  sing-box-deve.sh cfg argo <off|temp|fixed> [token] [domain]
  sing-box-deve.sh cfg psiphon <off|on> [off|proxy|global] [auto|cc]
  sing-box-deve.sh cfg ip-pref <auto|v4|v6>
  sing-box-deve.sh cfg cdn-host <domain>
  sing-box-deve.sh cfg domain-split <direct_csv> <proxy_csv> <block_csv>
  sing-box-deve.sh cfg tls <self-signed|acme|acme-auto> [cert_path|domain] [key_path|email] [dns_provider]
  sing-box-deve.sh cfg rebuild
  sing-box-deve.sh kernel show
  sing-box-deve.sh kernel set <sing-box|xray> [tag|latest]
  sing-box-deve.sh warp status|register|unlock|socks5-start [port]|socks5-stop|socks5-status
  sing-box-deve.sh psiphon status|start|stop|set-region <auto|cc>
  sing-box-deve.sh sys bbr-status
  sing-box-deve.sh sys bbr-enable
  sing-box-deve.sh sys acme-install
  sing-box-deve.sh sys acme-issue <domain> <email> [dns_provider]
  sing-box-deve.sh sys acme-apply <cert_path> <key_path>
  sing-box-deve.sh regen-nodes
  sing-box-deve.sh update [--script|--core|--all] [--source auto|primary|backup] [--yes] [--rollback]
  sing-box-deve.sh version
  sing-box-deve.sh protocol matrix [--enabled]
  sing-box-deve.sh settings show
  sing-box-deve.sh settings set <key> <value>
  sing-box-deve.sh settings set key1=value1 key2=value2 ...
  sing-box-deve.sh uninstall [--keep-settings]
  sing-box-deve.sh doctor
  sing-box-deve.sh fw status
  sing-box-deve.sh fw rollback
  sing-box-deve.sh fw replay
Examples:
  ./sing-box-deve.sh install --provider vps --profile lite --engine sing-box --protocols vless-reality
  ./sing-box-deve.sh apply -f ./config.env
EOF
}
