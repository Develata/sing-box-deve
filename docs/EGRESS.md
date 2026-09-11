# 出口节点

`set-egress` 设置一个上游出口，`set-route` 决定哪些流量使用它。两者独立：`direct` 以直连为默认，`global-proxy` 以出口为默认，`cn-direct` / `cn-proxy` 延续现有分流规则。显式域名规则和 UDP 策略仍可覆盖默认路由。

## 导入与切换

已安装主机使用 `sb`，源码 checkout 使用 `./sing-box-deve.sh`：

```bash
sb set-egress --link-file /root/egress.link --udp proxy
sb set-route global-proxy
# 停用出口前，先退出依赖出口的路由模式
sb set-route direct
sb set-egress --mode direct
```

链接文件仅含一条分享链接，可带末尾换行；建议权限 `0600`。也可使用 `--link '分享链接'`，或 `sb menu` 的出口设置粘贴链接（输入不回显）。链接含凭据，避免放进共享终端记录。`--link` / `--link-file` 不与 `--mode`、`--host`、`--port`、`--user`、`--pass` 混用。

安装参数为 `--outbound-proxy-link` / `--outbound-proxy-link-file`；配置文件为 `outbound_proxy_link`，非空时由链接确定出口协议与地址。显式写入 `outbound_proxy_link=""` 会覆盖继承的同名环境输入；恢复直连时还需设置 `outbound_proxy_mode=direct` 和 `route_mode=direct`。网页生成器同样提供“节点分享链接”入口。SOCKS、HTTP、HTTPS 仍使用原有逐项参数。

链接作为权威输入保存在受权限保护的 `runtime.env`，修改路由、重建配置、重启与事务恢复均保留它。切回 `--mode direct` 或旧式代理会清除链接。日志和 context 只记录协议、地址或链接是否存在，不输出链接凭据。

## 协议与内核

以下是本项目出口实现的范围，不代表内核的全部能力。验证基线：sing-box **1.14.0**、Xray **26.3.27**。

| 分享链接 | sing-box | Xray | 说明 |
| --- | --- | --- | --- |
| VLESS TCP + Reality | 支持 | 支持 | UUID、SNI、公钥、short ID；可选 Vision |
| VLESS-WS | 支持 | 支持 | 无 TLS 或 TLS；path、Host |
| Hysteria2 / HY2 | 支持 | 支持 | TLS；可选 Salamander |
| TUIC | 支持 | 不支持 | UUID + password、拥塞控制、UDP relay mode |
| Shadowsocks-2022 | 支持 | 支持 | AES-128、AES-256、ChaCha20；标准 SIP002 编码 |
| Naive HTTPS | 支持 | 不支持 | 用户名 + 密码；正常验证 TLS |
| VLESS-XHTTP | 不支持 | 支持 | path、Host、mode；无 TLS、TLS 或 Reality |

VLESS `flow` 按链接原值导入，缺省或空值均不启用 Vision；需要 Vision 时必须明确填写 `flow=xtls-rprx-vision`。Naive/TUIC 的用户名与密码先按 URI 中的冒号分隔，再各自解码；Naive Basic auth 用户名不能含冒号。

VLESS `encryption` 非 `none` 需要 Xray，具体参数仍由当前内核检查。XHTTP 使用 Vision 时还必须启用 VLESS Encryption；旧链接若带 `encryption=none&flow=xtls-rprx-vision`，需在更新后的远端重新生成配置和链接。本次同时修正该组合的服务端和分享链接生成。Naive 出口需要 sing-box 的 Cronet 支持；安装及 core 更新会部署已校验发行包附带的 `libcronet.so`，并将动态库和二进制一起纳入回滚。旧版 core 或缺失构建功能会在配置检查阶段报错，不应绕过检查启动。

`vless://`、`hy2://`、`hysteria2://`、`tuic://`、`ss://`、`naive+https://` 均可导入。优先使用本项目输出的节点链接；对外部链接采取严格解析，拒绝重复参数、未知选项、畸形编码、不支持的传输及错误凭据格式。暂不支持 HY2 端口跳跃、Gecko、SS 插件、XHTTP extra JSON 等扩展。

## UDP 与 TLS

- `--udp proxy`：按选定路由由出口承载 UDP；默认值。
- `--udp direct`：UDP 直接发送，TCP 继续按路由处理。
- `--udp block`：阻断 UDP，TCP 继续按路由处理。

Naive 只有链接显式带 `uot=true` 且远端支持对应 UDP-over-TCP 扩展时才允许 `proxy`；普通 Naive 链接必须选 `direct` 或 `block`。HTTP/HTTPS 也必须选这两者之一。WARP 与上游出口不能同时启用。

TLS 默认验证证书。sing-box 的 HY2、TUIC、VLESS TLS 可显式使用链接的 `insecure=true`，仅在明确接受该语义时使用；Reality 和 Naive 不接受这一选项。Xray 26.3.27 已移除 `allowInsecure=true`，其出口要求正常验证 TLS，导入时拒绝 insecure 链接。链接文件和 URI 凭据不会作为 shell 代码执行。

## 依据与验证边界

能力与字段由以下一手资料和上述版本的真实内核共同核对（2026-09-10）：

- [sing-box VLESS](https://sing-box.sagernet.org/configuration/outbound/vless/)、[Hysteria2](https://sing-box.sagernet.org/configuration/outbound/hysteria2/)、[TUIC](https://sing-box.sagernet.org/configuration/outbound/tuic/)、[Naive](https://sing-box.sagernet.org/configuration/outbound/naive/)：出口字段和 Naive Cronet 依赖。
- [VLESS 分享链接规范](https://github.com/XTLS/Xray-core/discussions/716)：保留 `flow` 的原始语义，不替用户补入 Vision。
- [Xray Hysteria 出口](https://xtls.github.io/config/outbounds/hysteria.html)、[Hysteria 传输](https://xtls.github.io/config/transports/hysteria.html)、[FinalMask](https://xtls.github.io/config/transports/finalmask.html)：HY2 与 Salamander 映射。
- [Xray v26.3.27 传输配置源码](https://github.com/XTLS/Xray-core/blob/v26.3.27/infra/conf/transport_internet.go)：以固定版本确认 `hysteriaSettings.auth` 和 `finalmask.udp` 字段，避免滚动文档的新字段误用于旧内核。

`test-egress-link.py` 检查链接解析边界，`test-egress-protocols.sh` 检查生成、持久化、拒绝路径和事务恢复；`test-egress-traffic.py` 使用本机回环服务检查真实内核 TCP/UDP 转发。配置检查与回环通信不能替代公网延迟、CDN、真实证书链和各供应商链接扩展的实机验证。
