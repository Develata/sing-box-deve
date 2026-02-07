# 面板输出样例模板（中英文）

本文提供 `./sing-box-deve.sh panel` 的标准输出模板，便于你后续统一风格。

- `./sing-box-deve.sh panel --compact`：简版（默认）
- `./sing-box-deve.sh panel --full`：完整信息（含 runtime/settings/firewall）

## 中文模板（推荐）

```text
[INFO] ========== sing-box-deve panel ==========
[INFO] Provider: <provider> | Profile: <profile> | Engine: <engine>
[INFO] Protocols: <protocols_csv>
[INFO] Argo: <argo_mode> | WARP: <warp_mode> | Egress: <outbound_proxy_mode>
[SUCCESS] Core service: running
[INFO] sing-box core version: <sing_box_version>
[INFO] xray core version: <xray_version>
[INFO] cloudflared version: <cloudflared_version>
[SUCCESS] Argo sidecar: running
[INFO] Script version: <script_version>
[INFO] Remote script version: <remote_script_version>
[INFO] Nodes file: /opt/sing-box-deve/data/nodes.txt
[INFO] =========================================
```

## Full 模板附加区块（`--full`）

```text
[INFO] ----- Runtime Details -----
<runtime.env 内容>
[INFO] ----- Settings -----
lang=<...>;auto_yes=<...>;update_channel=<...>
[INFO] ----- Managed Firewall Rules -----
<fw status 输出>
```

## English Template

```text
[INFO] ========== sing-box-deve panel ==========
[INFO] Provider: <provider> | Profile: <profile> | Engine: <engine>
[INFO] Protocols: <protocols_csv>
[INFO] Argo: <argo_mode> | WARP: <warp_mode> | Egress: <outbound_proxy_mode>
[SUCCESS] Core service: running
[INFO] sing-box core version: <sing_box_version>
[INFO] xray core version: <xray_version>
[INFO] cloudflared version: <cloudflared_version>
[SUCCESS] Argo sidecar: running
[INFO] Script version: <script_version>
[INFO] Remote script version: <remote_script_version>
[INFO] Nodes file: /opt/sing-box-deve/data/nodes.txt
[INFO] =========================================
```

## 异常场景模板

```text
[WARN] Runtime state not found (/etc/sing-box-deve/runtime.env)
[WARN] Core service: not running
[WARN] Argo sidecar: not running
[WARN] Unable to fetch remote version (set SBD_UPDATE_BASE_URL if needed)
```
