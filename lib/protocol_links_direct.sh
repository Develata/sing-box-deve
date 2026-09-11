#!/usr/bin/env bash

node_link_vless_reality() {
  local uuid="$1" ip="$2" port="$3" sni="$4" fp="$5" pbk="$6" sid="$7"
  ip="$(uri_authority_host "$ip")"
  echo "vless://$uuid@$ip:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$sni&fp=$fp&pbk=$pbk&sid=$sid&type=tcp#sbd-vless-reality"
}

node_link_vless_ws() {
  local uuid="$1" ip="$2" port="$3" enc="$4" path_uri="$5" host="$6"
  local security="${7:-none}" sni="${8:-}" tag="${9:-sbd-vless-ws}" vh="" tls_q=""
  ip="$(uri_authority_host "$ip")"
  [[ -n "$host" ]] && vh="&host=${host}"
  [[ -n "$sni" ]] && tls_q="&sni=${sni}"
  echo "vless://$uuid@$ip:${port}?encryption=$enc&security=${security}${tls_q}&type=ws&path=${path_uri}${vh}#${tag}"
}

node_link_vless_xhttp() {
  local uuid="$1" ip="$2" port="$3" enc="$4" sni="$5" fp="$6" pbk="$7" sid="$8" path_uri="$9" mode="${10}" host="${11}"
  local vh="" flow="" security="${12:-reality}" tls_q=""
  [[ "$enc" == none ]] || flow="&flow=xtls-rprx-vision"
  ip="$(uri_authority_host "$ip")"
  [[ -n "$host" ]] && vh="&host=$host"
  [[ "$security" != reality ]] || tls_q="&sni=$sni&fp=$fp&pbk=$pbk&sid=$sid"
  echo "vless://$uuid@$ip:${port}?encryption=${enc}${flow}&security=${security}${tls_q}&type=xhttp&path=${path_uri}&mode=$mode${vh}#sbd-vless-xhttp"
}

node_link_ss2022() {
  local password="$1" ip="$2" port="$3"
  ip="$(uri_authority_host "$ip")"
  echo "ss://$(printf '%s' "2022-blake3-aes-128-gcm:${password}" | base64 -w 0)@$ip:${port}#sbd-shadowsocks-2022"
}

node_link_naive() {
  local uuid="$1" ip="$2" port="$3" sni="$4"
  ip="$(uri_authority_host "$ip")"
  echo "naive+https://$uuid:$uuid@$ip:${port}?sni=$sni#sbd-naive"
}

node_link_hysteria2() {
  local uuid="$1" ip="$2" port="$3" sni="$4" obfs_mode="${5:-off}" obfs_password="${6:-}"
  local obfs_q=""
  ip="$(uri_authority_host "$ip")"
  if [[ "$obfs_mode" != "off" ]]; then
    obfs_q="&obfs=$(uri_encode "$obfs_mode")&obfs-password=$(uri_encode "$obfs_password")"
  fi
  echo "hysteria2://$uuid@$ip:${port}?security=tls&sni=$sni${obfs_q}#sbd-hysteria2"
}

node_link_warp_mode() {
  local mode="${1:-off}"
  echo "warp-mode://${mode}"
}
