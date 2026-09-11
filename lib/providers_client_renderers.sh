#!/usr/bin/env bash

client_node_model_ready() {
  [[ -s "$SBD_NODE_MODEL_FILE" ]] && jq -e '.version == 1 and (.nodes | type == "array")' \
    "$SBD_NODE_MODEL_FILE" >/dev/null 2>&1
}

singbox_client_proxy_outbounds() {
  jq '
    def dial:
      if (.server | test(":")) or (.server | test("^[0-9]+(\\.[0-9]+){3}$"))
      then {} else {domain_resolver:"dns-local"} end;
    [.nodes[] | select(.singbox_compatible != false) |
      if .kind == "vless-reality" then
        ({type:"vless",tag:.tag,server:.server,server_port:.port,uuid:.uuid,
          flow:"xtls-rprx-vision",
          tls:{enabled:true,server_name:.sni,
            utls:{enabled:true,fingerprint:.fingerprint},
            reality:{enabled:true,public_key:.public_key,short_id:.short_id}}} + dial)
      elif .kind == "vless-ws" then
        ({type:"vless",tag:.tag,server:.server,server_port:.port,uuid:.uuid,
          transport:({type:"ws",path:.path} +
            (if .host == "" then {} else {headers:{Host:.host}} end))} +
          (if .tls then {tls:{enabled:true,server_name:.sni}} else {} end) + dial)
      elif .kind == "shadowsocks-2022" then
        ({type:"shadowsocks",tag:.tag,server:.server,server_port:.port,
          method:"2022-blake3-aes-128-gcm",password:.password} + dial)
      elif .kind == "naive" then
        ({type:"naive",tag:.tag,server:.server,server_port:.port,
          username:.username,password:.password,
          tls:{enabled:true,server_name:.sni}} + dial)
      elif .kind == "hysteria2" then
        ({type:"hysteria2",tag:.tag,server:.server,server_port:.port,password:.password,
          tls:{enabled:true,server_name:.sni,insecure:.insecure}} +
          (if .obfs_mode == "off" then {} else
            {obfs:{type:.obfs_mode,password:.obfs_password}} end) + dial)
      else empty end
    ]' "$SBD_NODE_MODEL_FILE"
}

clash_client_proxies() {
  jq '
    [.nodes[] | select(.clash_compatible != false) |
      if .kind == "vless-reality" then
        {name:.tag,type:"vless",server:.server,port:.port,uuid:.uuid,network:"tcp",
          tls:true,udp:true,flow:"xtls-rprx-vision",servername:.sni,
          "client-fingerprint":.fingerprint,
          "reality-opts":{"public-key":.public_key,"short-id":.short_id}}
      elif .kind == "vless-ws" then
        ({name:.tag,type:"vless",server:.server,port:.port,uuid:.uuid,network:"ws",udp:true,
          "ws-opts":({path:.path} +
            (if .host == "" then {} else {headers:{Host:.host}} end))} +
          (if .tls then {tls:true,servername:.sni} else {tls:false} end))
      elif .kind == "shadowsocks-2022" then
        {name:.tag,type:"ss",server:.server,port:.port,
          cipher:"2022-blake3-aes-128-gcm",password:.password,udp:true}
      elif .kind == "hysteria2" then
        ({name:.tag,type:"hysteria2",server:.server,port:.port,password:.password,
          sni:.sni,"skip-cert-verify":.insecure} +
          (if .obfs_mode == "off" then {} else
            {obfs:.obfs_mode,"obfs-password":.obfs_password} end))
      else empty end
    ]' "$SBD_NODE_MODEL_FILE"
}

render_singbox_client_from_model() {
  local out_file="$1" proxies tags tmp
  client_node_model_ready || die "Structured node model not found; run regen-nodes"
  proxies="$(singbox_client_proxy_outbounds)"
  [[ "$(jq 'length' <<< "$proxies")" -gt 0 ]] || return 2
  tags="$(jq '[.[].tag]' <<< "$proxies")"
  tmp="${out_file}.tmp.$$"

  jq -n --argjson proxies "$proxies" --argjson tags "$tags" '
    {
      log:{level:"warn"},
      experimental:{clash_api:{external_controller:"127.0.0.1:9090",default_mode:"Rule"}},
      dns:{
        servers:[
          {type:"https",tag:"dns-remote",server:"1.1.1.1",server_port:443,
            path:"/dns-query",tls:{enabled:true,server_name:"cloudflare-dns.com"},detour:"select"},
          {type:"udp",tag:"dns-local",server:"223.5.5.5",server_port:53,detour:"direct"}
        ],
        rules:[
          {rule_set:["geosite-cn"],action:"route",server:"dns-local"}
        ],
        final:"dns-remote",strategy:"prefer_ipv4"
      },
      inbounds:[{type:"tun",tag:"tun-in",address:["172.19.0.1/30","fd00::1/126"],
        auto_route:true,strict_route:true}],
      outbounds:([{
        type:"selector",tag:"select",default:"auto",
        outbounds:(["auto"] + $tags + ["direct"])
      },{
        type:"urltest",tag:"auto",outbounds:$tags,
        url:"https://www.gstatic.com/generate_204",interval:"3m"
      }] + $proxies + [{type:"direct",tag:"direct"}]),
      route:{
        default_domain_resolver:"dns-local",
        rule_set:[
          {tag:"geosite-cn",type:"local",format:"binary",path:"./sing-ruleset/geosite-cn.srs"},
          {tag:"geoip-cn",type:"local",format:"binary",path:"./sing-ruleset/geoip-cn.srs"}
        ],
        rules:[
          {action:"sniff"},
          {clash_mode:"Direct",action:"route",outbound:"direct"},
          {clash_mode:"Global",action:"route",outbound:"select"},
          {rule_set:["geosite-cn","geoip-cn"],action:"route",outbound:"direct"}
        ],
        final:"select"
      }
    }' > "$tmp"
  chmod 0600 "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$out_file"
}

render_clash_proxy_section_from_model() {
  local out_file="$1" proxies names
  client_node_model_ready || die "Structured node model not found; run regen-nodes"
  proxies="$(clash_client_proxies)"
  [[ "$(jq 'length' <<< "$proxies")" -gt 0 ]] || return 2
  names="$(jq '[.[].name]' <<< "$proxies")"
  {
    printf 'proxies: %s\n\n' "$(jq -c . <<< "$proxies")"
    printf 'proxy-groups:\n'
    printf '  - name: PROXY\n    type: select\n    proxies: %s\n' \
      "$(jq -c '["AUTO"] + . + ["DIRECT"]' <<< "$names")"
    printf '  - name: AUTO\n    type: url-test\n'
    printf '    url: https://www.gstatic.com/generate_204\n    interval: 180\n'
    printf '    proxies: %s\n\n' "$(jq -c . <<< "$names")"
  } >> "$out_file"
}
