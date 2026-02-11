#!/usr/bin/env bash

node_link_vless_reality() {
  local uuid="$1" ip="$2" port="$3" sni="$4" fp="$5" pbk="$6" sid="$7"
  echo "vless://$uuid@$ip:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$sni&fp=$fp&pbk=$pbk&sid=$sid&type=tcp#sbd-vless-reality"
}

node_link_vmess_ws() {
  local uuid="$1" ip="$2" port="$3" host="$4" path="$5"
  echo "vmess://$(printf '{"v":"2","ps":"sbd-vmess-ws","add":"%s","port":"%s","id":"%s","aid":"0","net":"ws","type":"none","host":"%s","path":"%s","tls":""}' "$ip" "$port" "$uuid" "$host" "$path" | base64 -w 0)"
}

node_link_vless_ws() {
  local uuid="$1" ip="$2" port="$3" enc="$4" path_uri="$5" host="$6"
  local vh=""
  [[ -n "$host" ]] && vh="&host=${host}"
  echo "vless://$uuid@$ip:${port}?encryption=$enc&security=none&type=ws&path=${path_uri}${vh}#sbd-vless-ws"
}

node_link_vless_xhttp() {
  local uuid="$1" ip="$2" port="$3" enc="$4" sni="$5" fp="$6" pbk="$7" sid="$8" path_uri="$9" mode="${10}" host="${11}"
  local vh=""
  [[ -n "$host" ]] && vh="&host=$host"
  echo "vless://$uuid@$ip:${port}?encryption=$enc&flow=xtls-rprx-vision&security=reality&sni=$sni&fp=$fp&pbk=$pbk&sid=$sid&type=xhttp&path=${path_uri}&mode=$mode${vh}#sbd-vless-xhttp"
}

node_link_ss2022() {
  local uuid="$1" ip="$2" port="$3"
  echo "ss://$(printf '%s' "2022-blake3-aes-128-gcm:${uuid}" | base64 -w 0)@$ip:${port}#sbd-shadowsocks-2022"
}

node_link_hysteria2() {
  local uuid="$1" ip="$2" port="$3" sni="$4"
  echo "hysteria2://$uuid@$ip:${port}?security=tls&sni=$sni&insecure=1#sbd-hysteria2"
}

node_link_tuic() {
  local uuid="$1" ip="$2" port="$3" sni="$4"
  echo "tuic://$uuid:$uuid@$ip:${port}?congestion_control=bbr&sni=$sni&allow_insecure=1#sbd-tuic"
}

node_link_trojan() {
  local uuid="$1" ip="$2" port="$3" sni="$4"
  echo "trojan://$uuid@$ip:${port}?security=tls&sni=$sni#sbd-trojan"
}

node_link_anytls() {
  local uuid="$1" ip="$2" port="$3" sni="$4"
  echo "anytls://$uuid@$ip:${port}?security=tls&sni=$sni#sbd-anytls"
}

node_link_any_reality() {
  local uuid="$1" ip="$2" port="$3" sni="$4" pbk="$5" sid="$6"
  echo "anytls://$uuid@$ip:${port}?security=reality&sni=$sni&pbk=$pbk&sid=$sid#sbd-any-reality"
}

node_link_wireguard() {
  local ip="$1" port="$2"
  echo "wireguard://$ip:${port}#sbd-wireguard-server"
}

node_link_socks5() {
  local uuid="$1" ip="$2" port="$3"
  echo "socks://$uuid:$uuid@$ip:${port}#sbd-socks5"
}

node_link_warp_mode() {
  local mode="${1:-off}"
  echo "warp-mode://${mode}"
}
