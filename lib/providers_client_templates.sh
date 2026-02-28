#!/usr/bin/env bash

build_client_names_csv() {
  local names
  names="$(awk -F'#' '/#/{print $NF}' "$SBD_NODES_FILE" | sed 's/^ *//;s/ *$//' | grep -v '^$' | paste -sd ',' -)"
  echo "${names:-sbd-default}"
}

render_singbox_client_json() {
  local out_file="$1"
  local names_csv names_json
  names_csv="$(build_client_names_csv)"
  names_json="[$(printf '%s' "$names_csv" | awk -F, '{for(i=1;i<=NF;i++){gsub(/^ +| +$/, "", $i); if(length($i)){printf "%s\"%s\"", (j++?",":""), $i}}}')]"

  cat > "$out_file" <<EOF
{
  "log": {"level": "warn"},
  "experimental": {
    "clash_api": {
      "external_controller": "127.0.0.1:9090",
      "external_ui": "ui",
      "external_ui_download_url": "",
      "default_mode": "Rule"
    }
  },
  "dns": {
    "servers": [
      {"tag":"dns-remote","address":"https://1.1.1.1/dns-query","detour":"select"},
      {"tag":"dns-local","address":"223.5.5.5","detour":"direct"}
    ],
    "rules": [
      {"rule_set":["geosite-cn"],"server":"dns-local"},
      {"rule_set":["geosite-geolocation-!cn"],"server":"dns-remote"}
    ],
    "strategy": "prefer_ipv4"
  },
  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "address": ["172.19.0.1/30", "fd00::1/126"],
      "auto_route": true,
      "strict_route": true,
      "sniff": true,
      "sniff_override_destination": true,
      "domain_strategy": "prefer_ipv4"
    }
  ],
  "outbounds": [
    {"type":"selector","tag":"select","default":"auto","outbounds":["auto","direct","block"]},
    {"type":"urltest","tag":"auto","outbounds":["direct"],"url":"https://www.gstatic.com/generate_204","interval":"3m"},
    {"type":"direct","tag":"direct"},
    {"type":"block","tag":"block"}
  ],
  "route": {
    "rule_set": [
      {"tag":"geosite-cn","type":"local","format":"binary","path":"./sing-ruleset/geosite-cn.srs"},
      {"tag":"geoip-cn","type":"local","format":"binary","path":"./sing-ruleset/geoip-cn.srs"}
    ],
    "rules": [
      {"rule_set":["geosite-cn","geoip-cn"],"outbound":"direct"},
      {"clash_mode":"Direct","outbound":"direct"},
      {"clash_mode":"Global","outbound":"select"}
    ],
    "final": "select"
  },
  "sbd_subscription": {
    "aggregate_base64": "$(cat "$SBD_SUB_FILE")",
    "node_names": ${names_json},
    "nodes_file": "${SBD_NODES_FILE}"
  }
}
EOF
}

clash_custom_rules_file() {
  echo "${SBD_CONFIG_DIR}/clash_custom_rules.list"
}

ensure_clash_custom_rules_file() {
  local custom_file
  custom_file="$(clash_custom_rules_file)"
  [[ -f "$custom_file" ]] && return 0

  mkdir -p "${SBD_CONFIG_DIR}"
  cat > "$custom_file" <<'EOF'
# 每行写一条 clash 规则，格式示例：
# DOMAIN-SUFFIX,openai.com,PROXY
# DOMAIN-KEYWORD,github,DIRECT
# IP-CIDR,1.1.1.1/32,PROXY,no-resolve
EOF
}

append_clash_custom_rules() {
  local out_file="$1" custom_file line rule
  custom_file="$(clash_custom_rules_file)"
  [[ -f "$custom_file" ]] || return 0

  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" && "${line#\#}" == "$line" ]] || continue
    rule="${line#- }"
    printf '  - %s\n' "$rule" >> "$out_file"
  done < "$custom_file"
}

render_clash_meta_yaml() {
  local out_file="$1"
  ensure_clash_custom_rules_file
  cat > "$out_file" <<EOF
# sing-box-deve clash-meta template
# generated_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# ruleset_mode: local-snapshot
# ruleset_source: bundled repo files (rulesets/clash/*.yaml)
mixed-port: 7890
allow-lan: false
mode: rule
log-level: info

dns:
  enable: true
  ipv6: true
  nameserver:
    - 223.5.5.5
    - 119.29.29.29
  fallback:
    - https://1.1.1.1/dns-query
    - https://8.8.8.8/dns-query

proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - AUTO
      - DIRECT
  - name: AUTO
    type: url-test
    url: https://www.gstatic.com/generate_204
    interval: 180
    proxies:
      - DIRECT

rule-providers:
  geosite-cn:
    type: file
    behavior: domain
    path: ./clash-ruleset/geosite-cn.yaml
  geoip-cn:
    type: file
    behavior: ipcidr
    path: ./clash-ruleset/geoip-cn.yaml

rules:
  - DOMAIN-SUFFIX,lan,DIRECT
  - DOMAIN-SUFFIX,local,DIRECT
  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  - DOMAIN-SUFFIX,cn,DIRECT
  - DOMAIN-SUFFIX,doubleclick.net,REJECT
  - DOMAIN-SUFFIX,googlesyndication.com,REJECT
  - DOMAIN-KEYWORD,adservice,REJECT
  # CN major internet companies (explicit direct)
  - DOMAIN-SUFFIX,baidu.com,DIRECT
  - DOMAIN-SUFFIX,bdimg.com,DIRECT
  - DOMAIN-SUFFIX,bdstatic.com,DIRECT
  - DOMAIN-SUFFIX,bcebos.com,DIRECT
  - DOMAIN-SUFFIX,baidubce.com,DIRECT
  - DOMAIN-SUFFIX,tieba.com,DIRECT
  - DOMAIN-SUFFIX,hao123.com,DIRECT
  - DOMAIN-SUFFIX,qq.com,DIRECT
  - DOMAIN-SUFFIX,myapp.com,DIRECT
  - DOMAIN-SUFFIX,weiyun.com,DIRECT
  - DOMAIN-SUFFIX,wechat.com,DIRECT
  - DOMAIN-SUFFIX,weixin.qq.com,DIRECT
  - DOMAIN-SUFFIX,tencent.com,DIRECT
  - DOMAIN-SUFFIX,gtimg.com,DIRECT
  - DOMAIN-SUFFIX,tencent-cloud.net,DIRECT
  - DOMAIN-SUFFIX,tencentcloud.com,DIRECT
  - DOMAIN-SUFFIX,tencentcloudapi.com,DIRECT
  - DOMAIN-SUFFIX,alicdn.com,DIRECT
  - DOMAIN-SUFFIX,aliyun.com,DIRECT
  - DOMAIN-SUFFIX,1688.com,DIRECT
  - DOMAIN-SUFFIX,taobaocdn.com,DIRECT
  - DOMAIN-SUFFIX,alibaba.com,DIRECT
  - DOMAIN-SUFFIX,taobao.com,DIRECT
  - DOMAIN-SUFFIX,tmall.com,DIRECT
  - DOMAIN-SUFFIX,jd.com,DIRECT
  - DOMAIN-SUFFIX,jd.hk,DIRECT
  - DOMAIN-SUFFIX,360buyimg.com,DIRECT
  - DOMAIN-SUFFIX,jcloud.com,DIRECT
  - DOMAIN-SUFFIX,pinduoduo.com,DIRECT
  - DOMAIN-SUFFIX,pddpic.com,DIRECT
  - DOMAIN-SUFFIX,bilibili.com,DIRECT
  - DOMAIN-SUFFIX,bilivideo.com,DIRECT
  - DOMAIN-SUFFIX,biligame.com,DIRECT
  - DOMAIN-SUFFIX,douyin.com,DIRECT
  - DOMAIN-SUFFIX,douyinpic.com,DIRECT
  - DOMAIN-SUFFIX,bytedance.com,DIRECT
  - DOMAIN-SUFFIX,byteimg.com,DIRECT
  - DOMAIN-SUFFIX,zijieapi.com,DIRECT
  - DOMAIN-SUFFIX,amemv.com,DIRECT
  - DOMAIN-SUFFIX,toutiao.com,DIRECT
  - DOMAIN-SUFFIX,ixigua.com,DIRECT
  - DOMAIN-SUFFIX,kuaishou.com,DIRECT
  - DOMAIN-SUFFIX,xiaohongshu.com,DIRECT
  - DOMAIN-SUFFIX,zhihu.com,DIRECT
  - DOMAIN-SUFFIX,douban.com,DIRECT
  - DOMAIN-SUFFIX,csdn.net,DIRECT
  - DOMAIN-SUFFIX,oschina.net,DIRECT
  - DOMAIN-SUFFIX,gitee.com,DIRECT
  - DOMAIN-SUFFIX,coding.net,DIRECT
  - DOMAIN-SUFFIX,36kr.com,DIRECT
  - DOMAIN-SUFFIX,hupu.com,DIRECT
  - DOMAIN-SUFFIX,maoyan.com,DIRECT
  - DOMAIN-SUFFIX,dianping.com,DIRECT
  - DOMAIN-SUFFIX,ele.me,DIRECT
  - DOMAIN-SUFFIX,didichuxing.com,DIRECT
  - DOMAIN-SUFFIX,qunar.com,DIRECT
  - DOMAIN-SUFFIX,fliggy.com,DIRECT
  - DOMAIN-SUFFIX,suning.com,DIRECT
  - DOMAIN-SUFFIX,smzdm.com,DIRECT
  - DOMAIN-SUFFIX,alipay.com,DIRECT
  - DOMAIN-SUFFIX,alipayobjects.com,DIRECT
  - DOMAIN-SUFFIX,tenpay.com,DIRECT
  - DOMAIN-SUFFIX,huawei.com,DIRECT
  - DOMAIN-SUFFIX,myhuaweicloud.com,DIRECT
  - DOMAIN-SUFFIX,qcloud.com,DIRECT
  - DOMAIN-SUFFIX,aliyuncs.com,DIRECT
  - DOMAIN-SUFFIX,volcengine.com,DIRECT
  - DOMAIN-SUFFIX,jdcloud.com,DIRECT
  - DOMAIN-SUFFIX,iflytek.com,DIRECT
  - DOMAIN-SUFFIX,kingsoft.com,DIRECT
  - DOMAIN-SUFFIX,mi.com,DIRECT
  - DOMAIN-SUFFIX,xiaomi.com,DIRECT
  - DOMAIN-SUFFIX,oppo.com,DIRECT
  - DOMAIN-SUFFIX,vivo.com,DIRECT
  - DOMAIN-SUFFIX,oneplus.com,DIRECT
  - DOMAIN-SUFFIX,10010.com,DIRECT
  - DOMAIN-SUFFIX,10086.com,DIRECT
  # CN AI services
  - DOMAIN-SUFFIX,deepseek.com,DIRECT
  - DOMAIN-SUFFIX,deepseek.ai,DIRECT
  - DOMAIN-SUFFIX,baichuan-ai.com,DIRECT
  - DOMAIN-SUFFIX,minimax.chat,DIRECT
  # CN academic / literature platforms
  - DOMAIN-SUFFIX,cnki.net,DIRECT
  - DOMAIN-SUFFIX,cqvip.com,DIRECT
  - DOMAIN-SUFFIX,airitilibrary.com,DIRECT
  # CN portal / media ecosystem
  - DOMAIN-SUFFIX,sina.com,DIRECT
  - DOMAIN-SUFFIX,weibo.com,DIRECT
  - DOMAIN-SUFFIX,weibocdn.com,DIRECT
  - DOMAIN-SUFFIX,163.com,DIRECT
  - DOMAIN-SUFFIX,126.com,DIRECT
  - DOMAIN-SUFFIX,126.net,DIRECT
  - DOMAIN-SUFFIX,yeah.net,DIRECT
  - DOMAIN-SUFFIX,netease.com,DIRECT
  - DOMAIN-SUFFIX,youdao.com,DIRECT
  - DOMAIN-SUFFIX,lofter.com,DIRECT
  - DOMAIN-SUFFIX,sohu.com,DIRECT
  - DOMAIN-SUFFIX,sogou.com,DIRECT
  - DOMAIN-SUFFIX,ifeng.com,DIRECT
  # CN video / music / entertainment
  - DOMAIN-SUFFIX,youku.com,DIRECT
  - DOMAIN-SUFFIX,ykimg.com,DIRECT
  - DOMAIN-SUFFIX,iqiyi.com,DIRECT
  - DOMAIN-SUFFIX,qiyipic.com,DIRECT
  - DOMAIN-SUFFIX,mgtv.com,DIRECT
  - DOMAIN-SUFFIX,hunantv.com,DIRECT
  - DOMAIN-SUFFIX,kugou.com,DIRECT
  - DOMAIN-SUFFIX,y.qq.com,DIRECT
  - DOMAIN-SUFFIX,ximalaya.com,DIRECT
  # CN map / travel / local life
  - DOMAIN-SUFFIX,amap.com,DIRECT
  - DOMAIN-SUFFIX,autonavi.com,DIRECT
  - DOMAIN-SUFFIX,meituan.com,DIRECT
  - DOMAIN-SUFFIX,meituan.net,DIRECT
  - DOMAIN-SUFFIX,dianping.com,DIRECT
  - DOMAIN-SUFFIX,ctrip.com,DIRECT
  - DOMAIN-SUFFIX,trip.com,DIRECT
  - DOMAIN-SUFFIX,tuniu.com,DIRECT
  # CN productivity / collaboration
  - DOMAIN-SUFFIX,dingtalk.com,DIRECT
  - DOMAIN-SUFFIX,yuque.com,DIRECT
  - DOMAIN-SUFFIX,lanhuapp.com,DIRECT
  - DOMAIN-SUFFIX,processon.com,DIRECT
  - DOMAIN-SUFFIX,modao.cc,DIRECT
  # CN cloud / infra / enterprise
  - DOMAIN-SUFFIX,huaweicloud.com,DIRECT
  - DOMAIN-SUFFIX,tencentyun.com,DIRECT
  - DOMAIN-SUFFIX,upyun.com,DIRECT
  - DOMAIN-SUFFIX,qingcloud.com,DIRECT
  - DOMAIN-SUFFIX,ksyun.com,DIRECT
  # CN AI services (expanded)
  - DOMAIN-SUFFIX,kimi.com,DIRECT
  - DOMAIN-SUFFIX,kimi.ai,DIRECT
  - DOMAIN-SUFFIX,moonshot-ai.com,DIRECT
  - DOMAIN-SUFFIX,doubao.com,DIRECT
  - DOMAIN-SUFFIX,qwen.ai,DIRECT
  - DOMAIN-SUFFIX,hunyuan.tencent.com,DIRECT
  - DOMAIN-SUFFIX,yuanbao.tencent.com,DIRECT
  - DOMAIN-SUFFIX,yiyan.baidu.com,DIRECT
  - DOMAIN-SUFFIX,ernie.bot,DIRECT
  - DOMAIN-SUFFIX,01.ai,DIRECT
  # CN academic / education platforms (expanded)
  - DOMAIN-SUFFIX,chaoxing.com,DIRECT
  - DOMAIN-SUFFIX,x-mol.com,DIRECT
  - DOMAIN-SUFFIX,sciengine.com,DIRECT
  - DOMAIN-SUFFIX,cn-ki.net,DIRECT
  - DOMAIN-SUFFIX,icourse163.org,DIRECT
  - DOMAIN-SUFFIX,xuetangx.com,DIRECT
  - DOMAIN-SUFFIX,coursetea.com,DIRECT
  # Aggressive keyword-based CN direct fallback
  - DOMAIN-KEYWORD,kimi,DIRECT
  - DOMAIN-KEYWORD,moonshot,DIRECT
  - DOMAIN-KEYWORD,deepseek,DIRECT
  - DOMAIN-KEYWORD,doubao,DIRECT
  - DOMAIN-KEYWORD,qwen,DIRECT
  - DOMAIN-KEYWORD,zhipu,DIRECT
  - DOMAIN-KEYWORD,chatglm,DIRECT
  - DOMAIN-KEYWORD,cnki,DIRECT
  - DOMAIN-KEYWORD,wanfang,DIRECT
  - DOMAIN-KEYWORD,cqvip,DIRECT
  - DOMAIN-KEYWORD,baidu,DIRECT
  - DOMAIN-KEYWORD,tencent,DIRECT
  - DOMAIN-KEYWORD,wechat,DIRECT
  - DOMAIN-KEYWORD,alibaba,DIRECT
  - DOMAIN-KEYWORD,aliyun,DIRECT
  - DOMAIN-KEYWORD,taobao,DIRECT
  - DOMAIN-KEYWORD,tmall,DIRECT
  - DOMAIN-KEYWORD,jd,DIRECT
  - DOMAIN-KEYWORD,pinduoduo,DIRECT
  - DOMAIN-KEYWORD,bilibili,DIRECT
  - DOMAIN-KEYWORD,douyin,DIRECT
  - DOMAIN-KEYWORD,netease,DIRECT
  - DOMAIN-KEYWORD,weibo,DIRECT
  - DOMAIN-KEYWORD,sogou,DIRECT
  - DOMAIN-KEYWORD,meituan,DIRECT
  - DOMAIN-KEYWORD,dianping,DIRECT
  - DOMAIN-KEYWORD,ctrip,DIRECT
  - RULE-SET,geosite-cn,DIRECT
  - RULE-SET,geoip-cn,DIRECT,no-resolve
EOF
  append_clash_custom_rules "$out_file"
  cat >> "$out_file" <<EOF
  - MATCH,PROXY

# aggregate_base64:
# $(cat "$SBD_SUB_FILE")
# nodes:
EOF
  sed 's/^/# /' "$SBD_NODES_FILE" >> "$out_file"
}

render_sfa_sfi_sfw() {
  local app="$1" out_file="$2"
  cat > "$out_file" <<EOF
{
  "app": "${app}",
  "generated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "subscription_base64": "$(cat "$SBD_SUB_FILE")",
  "nodes_file": "${SBD_NODES_FILE}",
  "hint": "import aggregate_base64 as subscription"
}
EOF
}
