const protocolMeta = {
  "vless-reality": "风险: 低 | 资源: 低 | 默认推荐",
  "vmess-ws": "风险: 中 | 资源: 低 | CDN 兼容好",
  "vless-xhttp": "风险: 中 | 资源: 中 | 需 xray",
  "vless-ws": "风险: 中 | 资源: 低 | 结构简单",
  "shadowsocks-2022": "风险: 低 | 资源: 低 | 需安全保管密码",
  "hysteria2": "风险: 中 | 资源: 中 | 高吞吐下 UDP 开销较高",
  "tuic": "风险: 中 | 资源: 中 | UDP + TLS",
  "anytls": "风险: 中 | 资源: 中 | 客户端生态较少",
  "any-reality": "风险: 中 | 资源: 中 | 需管理 Reality 密钥",
  "argo": "风险: 中 | 资源: 低 | 依赖 cloudflared",
  "warp": "风险: 中 | 资源: 低 | 需有效 WG key",
  "trojan": "风险: 低 | 资源: 低 | 证书管理要规范",
  "wireguard": "风险: 中 | 资源: 低 | 对端配置要正确"
};

const protocolsAll = Object.keys(protocolMeta);
const protocolBox = document.getElementById("protocols");
const output = document.getElementById("output");
const hint = document.getElementById("protocolHint");

function initProtocolList() {
  protocolsAll.forEach((p) => {
    const label = document.createElement("label");
    label.className = "pill";
    label.innerHTML = `<input type="checkbox" value="${p}" ${p === "vless-reality" ? "checked" : ""}>${p}`;
    protocolBox.appendChild(label);
  });
  refreshProtocolHint();
}

function selectedProtocols() {
  const boxes = document.querySelectorAll('#protocols input[type="checkbox"]:checked');
  return Array.from(boxes).map((x) => x.value);
}

function refreshProtocolHint() {
  const selected = selectedProtocols();
  if (!selected.length) {
    hint.textContent = "未选择协议。";
    return;
  }
  hint.innerHTML = selected.map((p) => `${p}: ${protocolMeta[p]}`).join("<br>");
}

function toggleAdvancedFields() {
  const provider = document.getElementById("provider").value;
  const argoMode = document.getElementById("argoMode").value;
  const warpMode = document.getElementById("warpMode").value;
  const outboundProxyMode = document.getElementById("outboundProxyMode").value;

  document.getElementById("argoFixed").classList.toggle("hidden", argoMode !== "fixed");
  document.getElementById("warpKeys").classList.toggle("hidden", warpMode !== "global");
  document.getElementById("serv00Fields").classList.toggle("hidden", provider !== "serv00");
  document.getElementById("sapFields").classList.toggle("hidden", provider !== "sap");
  document.getElementById("outboundProxyFields").classList.toggle("hidden", outboundProxyMode === "direct");
}

function validateForm() {
  const provider = document.getElementById("provider").value;
  const profile = document.getElementById("profile").value;
  const engine = document.getElementById("engine").value;
  const protocols = selectedProtocols();
  const argoMode = document.getElementById("argoMode").value;
  const argoToken = document.getElementById("argoToken").value.trim();
  const warpMode = document.getElementById("warpMode").value;
  const warpPrivateKey = document.getElementById("warpPrivateKey").value.trim();
  const warpPeerPublicKey = document.getElementById("warpPeerPublicKey").value.trim();
  const outboundProxyMode = document.getElementById("outboundProxyMode").value;
  const outboundProxyHost = document.getElementById("outboundProxyHost").value.trim();
  const outboundProxyPort = document.getElementById("outboundProxyPort").value.trim();

  if (!protocols.length) return "至少选择一个协议";
  if (profile === "lite" && protocols.length > 2) return "Lite 模式最多 2 个协议";
  if (engine === "sing-box" && protocols.includes("vless-xhttp")) return "sing-box 模式暂不支持 vless-xhttp";
  if (engine === "xray" && protocols.includes("anytls")) return "xray 暂不支持 anytls";
  if (engine === "xray" && protocols.includes("any-reality")) return "xray 暂不支持 any-reality";
  if (protocols.includes("argo") && argoMode === "off") return "启用 argo 协议时，Argo 模式不能为 off";
  if (argoMode === "fixed" && !argoToken) return "Argo fixed 模式必须填写 token";
  if (protocols.includes("warp") && warpMode !== "global") return "启用 warp 协议时，WARP 模式建议使用 global";
  if (warpMode === "global" && outboundProxyMode !== "direct") return "WARP global 与上游出站代理不能同时启用";
  if (warpMode === "global" && (!warpPrivateKey || !warpPeerPublicKey)) return "WARP global 模式必须填写两项 key";
  if (outboundProxyMode !== "direct" && (!outboundProxyHost || !outboundProxyPort)) return "出站代理启用时必须填写 host 和 port";
  if (provider === "serv00") {
    const host = document.getElementById("serv00Host").value.trim();
    const user = document.getElementById("serv00User").value.trim();
    if (!host || !user) return "serv00 场景建议填写 SERV00_HOST 和 SERV00_USER";
  }
  if (provider === "sap") {
    const api = document.getElementById("sapApi").value.trim();
    const org = document.getElementById("sapOrg").value.trim();
    const space = document.getElementById("sapSpace").value.trim();
    if (!api || !org || !space) return "sap 场景建议填写 API/ORG/SPACE";
  }
  return "";
}

function buildCommand() {
  const provider = document.getElementById("provider").value;
  const profile = document.getElementById("profile").value;
  const engine = document.getElementById("engine").value;
  const protocols = selectedProtocols();
  const argoMode = document.getElementById("argoMode").value;
  const argoDomain = document.getElementById("argoDomain").value.trim();
  const argoToken = document.getElementById("argoToken").value.trim();
  const warpMode = document.getElementById("warpMode").value;
  const outboundProxyMode = document.getElementById("outboundProxyMode").value;
  const outboundProxyHost = document.getElementById("outboundProxyHost").value.trim();
  const outboundProxyPort = document.getElementById("outboundProxyPort").value.trim();
  const outboundProxyUser = document.getElementById("outboundProxyUser").value.trim();
  const outboundProxyPass = document.getElementById("outboundProxyPass").value.trim();
  const err = validateForm();
  if (err) {
    alert(err);
    return;
  }

  const args = [
    "install",
    `--provider ${provider}`,
    `--profile ${profile}`,
    `--engine ${engine}`,
    `--protocols ${protocols.join(",")}`,
    `--argo ${argoMode}`,
    `--warp-mode ${warpMode}`,
    `--outbound-proxy-mode ${outboundProxyMode}`
  ];
  if (argoDomain) args.push(`--argo-domain ${argoDomain}`);
  if (argoToken) args.push(`--argo-token ${argoToken}`);
  if (outboundProxyMode !== "direct") {
    args.push(`--outbound-proxy-host ${outboundProxyHost}`);
    args.push(`--outbound-proxy-port ${outboundProxyPort}`);
    if (outboundProxyUser) args.push(`--outbound-proxy-user ${outboundProxyUser}`);
    if (outboundProxyPass) args.push(`--outbound-proxy-pass ${outboundProxyPass}`);
  }

  const cmd = `bash <(curl -fsSL https://raw.githubusercontent.com/Develata/sing-box-deve/main/sing-box-deve.sh) ${args.join(" ")}`;
  document.getElementById("resultHint").textContent = "生成命令：";
  output.value = cmd;
}

function buildEnvTemplate() {
  const provider = document.getElementById("provider").value;
  const profile = document.getElementById("profile").value;
  const engine = document.getElementById("engine").value;
  const protocols = selectedProtocols();
  const argoMode = document.getElementById("argoMode").value;
  const argoDomain = document.getElementById("argoDomain").value.trim();
  const argoToken = document.getElementById("argoToken").value.trim();
  const warpMode = document.getElementById("warpMode").value;
  const warpPrivateKey = document.getElementById("warpPrivateKey").value.trim();
  const warpPeerPublicKey = document.getElementById("warpPeerPublicKey").value.trim();
  const outboundProxyMode = document.getElementById("outboundProxyMode").value;
  const outboundProxyHost = document.getElementById("outboundProxyHost").value.trim();
  const outboundProxyPort = document.getElementById("outboundProxyPort").value.trim();
  const outboundProxyUser = document.getElementById("outboundProxyUser").value.trim();
  const outboundProxyPass = document.getElementById("outboundProxyPass").value.trim();

  const err = validateForm();
  if (err) {
    alert(err);
    return;
  }

  const lines = [
    `provider=${provider}`,
    `profile=${profile}`,
    `engine=${engine}`,
    `protocols=${protocols.join(",")}`,
    `argo_mode=${argoMode}`,
    `argo_domain=${argoDomain}`,
    `argo_token=${argoToken}`,
    `warp_mode=${warpMode}`,
    `outbound_proxy_mode=${outboundProxyMode}`,
    `outbound_proxy_host=${outboundProxyHost}`,
    `outbound_proxy_port=${outboundProxyPort}`,
    `outbound_proxy_user=${outboundProxyUser}`,
    `outbound_proxy_pass=${outboundProxyPass}`,
    `WARP_PRIVATE_KEY=${warpPrivateKey}`,
    `WARP_PEER_PUBLIC_KEY=${warpPeerPublicKey}`
  ];

  if (provider === "serv00") {
    lines.push(`SERV00_HOST=${document.getElementById("serv00Host").value.trim()}`);
    lines.push(`SERV00_USER=${document.getElementById("serv00User").value.trim()}`);
  }
  if (provider === "sap") {
    lines.push(`SAP_CF_API=${document.getElementById("sapApi").value.trim()}`);
    lines.push(`SAP_CF_ORG=${document.getElementById("sapOrg").value.trim()}`);
    lines.push(`SAP_CF_SPACE=${document.getElementById("sapSpace").value.trim()}`);
  }

  document.getElementById("resultHint").textContent = "生成 env 模板：";
  output.value = lines.join("\n") + "\n";
}

async function copyOutput() {
  const text = output.value;
  if (!text) {
    alert("当前没有可复制内容");
    return;
  }
  try {
    await navigator.clipboard.writeText(text);
    document.getElementById("resultHint").textContent = "已复制到剪贴板";
  } catch (_e) {
    alert("复制失败，请手动复制");
  }
}

document.getElementById("buildCmd").addEventListener("click", buildCommand);
document.getElementById("buildEnv").addEventListener("click", buildEnvTemplate);
document.getElementById("copyOut").addEventListener("click", copyOutput);
document.getElementById("profile").addEventListener("change", refreshProtocolHint);
document.getElementById("provider").addEventListener("change", toggleAdvancedFields);
document.getElementById("argoMode").addEventListener("change", toggleAdvancedFields);
document.getElementById("warpMode").addEventListener("change", toggleAdvancedFields);
document.getElementById("outboundProxyMode").addEventListener("change", toggleAdvancedFields);
document.getElementById("protocols").addEventListener("change", refreshProtocolHint);

initProtocolList();
toggleAdvancedFields();
