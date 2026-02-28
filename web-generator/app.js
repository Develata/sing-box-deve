/* sing-box-deve command generator - app.js */

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

const CDN_TLS_PORTS = [443, 8443, 2053, 2083, 2087, 2096];
const CDN_PLAIN_PORTS = [80, 8080, 8880, 2052, 2082, 2086, 2095];

const protocolsAll = Object.keys(protocolMeta);
const protocolBox = document.getElementById("protocols");
const output = document.getElementById("output");
const hint = document.getElementById("protocolHint");

/* ── Toast ── */
function showToast(msg, duration) {
  duration = duration || 2500;
  var el = document.getElementById("toast");
  el.textContent = msg;
  el.classList.remove("hidden");
  clearTimeout(el._timer);
  el._timer = setTimeout(function () { el.classList.add("hidden"); }, duration);
}

/* ── UUID generator ── */
function generateUUID() {
  if (crypto && crypto.randomUUID) return crypto.randomUUID();
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (c) {
    var r = (Math.random() * 16) | 0;
    return (c === "x" ? r : (r & 0x3) | 0x8).toString(16);
  });
}

/* ── Theme toggle ── */
function initTheme() {
  var saved = localStorage.getItem("sbd-theme") || "dark";
  document.body.setAttribute("data-theme", saved);
  updateThemeIcon(saved);
}
function toggleTheme() {
  var cur = document.body.getAttribute("data-theme") === "light" ? "dark" : "light";
  document.body.setAttribute("data-theme", cur);
  localStorage.setItem("sbd-theme", cur);
  updateThemeIcon(cur);
}
function updateThemeIcon(theme) {
  var btn = document.getElementById("themeToggle");
  if (btn) btn.textContent = theme === "light" ? "☀️" : "🌙";
}

/* ── Protocol list ── */
function initProtocolList() {
  protocolsAll.forEach(function (p) {
    var label = document.createElement("label");
    label.className = "pill";
    label.innerHTML = '<input type="checkbox" value="' + p + '"' + (p === "vless-reality" ? " checked" : "") + ">" + p;
    protocolBox.appendChild(label);
  });
  refreshProtocolHint();
}

function selectedProtocols() {
  var boxes = document.querySelectorAll('#protocols input[type="checkbox"]:checked');
  return Array.from(boxes).map(function (x) { return x.value; });
}

function refreshProtocolHint() {
  var selected = selectedProtocols();
  if (!selected.length) { hint.textContent = "未选择协议。"; return; }
  hint.innerHTML = selected.map(function (p) { return p + ": " + protocolMeta[p]; }).join("<br>");
}

/* ── CDN endpoints builder ── */
function getSelectedCdnEndpoints() {
  var argoMode = document.getElementById("argoMode").value;
  if (argoMode === "off") return "";
  var cdnHost = (document.getElementById("cdnHost").value || "").trim();
  var checks = document.querySelectorAll('#cdnPanel .cdn input[type="checkbox"]:checked');
  var eps = [];
  Array.from(checks).forEach(function (cb) {
    var port = cb.value;
    var tls = CDN_TLS_PORTS.indexOf(parseInt(port, 10)) >= 0 ? "tls" : "none";
    var host = cdnHost || "cdn.example.com";
    eps.push(host + ":" + port + ":" + tls);
  });
  return eps.join(",");
}

/* ── Toggle fields ── */
function toggleAdvancedFields() {
  var provider = document.getElementById("provider").value;
  var argoMode = document.getElementById("argoMode").value;
  var warpMode = document.getElementById("warpMode").value;
  var outboundProxyMode = document.getElementById("outboundProxyMode").value;

  document.getElementById("argoFixed").classList.toggle("hidden", argoMode !== "fixed");
  document.getElementById("warpKeys").classList.toggle("hidden", warpMode !== "global");
  document.getElementById("serv00Fields").classList.toggle("hidden", provider !== "serv00");
  document.getElementById("sapFields").classList.toggle("hidden", provider !== "sap");
  document.getElementById("outboundProxyFields").classList.toggle("hidden", outboundProxyMode === "direct");
  document.getElementById("cdnPanel").classList.toggle("hidden", argoMode === "off");
}

/* ── SAP region quick-select ── */
function onSapRegionChange() {
  var val = document.getElementById("sapRegion").value;
  if (val) document.getElementById("sapApi").value = val;
}

/* ── Validate ── */
function validateForm() {
  var profile = document.getElementById("profile").value;
  var engine = document.getElementById("engine").value;
  var protocols = selectedProtocols();
  var argoMode = document.getElementById("argoMode").value;
  var argoToken = (document.getElementById("argoToken").value || "").trim();
  var warpMode = document.getElementById("warpMode").value;
  var warpPK = (document.getElementById("warpPrivateKey").value || "").trim();
  var warpPub = (document.getElementById("warpPeerPublicKey").value || "").trim();
  var outMode = document.getElementById("outboundProxyMode").value;
  var outHost = (document.getElementById("outboundProxyHost").value || "").trim();
  var outPort = (document.getElementById("outboundProxyPort").value || "").trim();
  var provider = document.getElementById("provider").value;

  if (!protocols.length) return "至少选择一个协议";
  if (profile === "lite" && protocols.length > 2) return "Lite 模式最多 2 个协议";
  if (engine === "sing-box" && protocols.indexOf("vless-xhttp") >= 0) return "sing-box 暂不支持 vless-xhttp";
  if (engine === "xray" && protocols.indexOf("anytls") >= 0) return "xray 暂不支持 anytls";
  if (engine === "xray" && protocols.indexOf("any-reality") >= 0) return "xray 暂不支持 any-reality";
  if (protocols.indexOf("argo") >= 0 && argoMode === "off") return "启用 argo 协议时，Argo 模式不能为 off";
  if (argoMode === "fixed" && !argoToken) return "Argo fixed 模式必须填写 token";
  if (protocols.indexOf("warp") >= 0 && warpMode !== "global") return "启用 warp 协议时，WARP 模式建议 global";
  if (warpMode === "global" && outMode !== "direct") return "WARP global 与上游出站代理不能同时启用";
  if (warpMode === "global" && (!warpPK || !warpPub)) return "WARP global 模式必须填写两项 key";
  if (outMode !== "direct" && (!outHost || !outPort)) return "出站代理启用时必须填写 host 和 port";
  if (provider === "serv00") {
    if (!(document.getElementById("serv00Host").value || "").trim() || !(document.getElementById("serv00User").value || "").trim())
      return "serv00 场景建议填写 SERV00_HOST 和 SERV00_USER";
  }
  if (provider === "sap") {
    if (!(document.getElementById("sapApi").value || "").trim() || !(document.getElementById("sapOrg").value || "").trim() || !(document.getElementById("sapSpace").value || "").trim())
      return "sap 场景建议填写 API/ORG/SPACE";
  }
  return "";
}

/* ── Build command ── */
function buildCommand() {
  var err = validateForm();
  if (err) { showToast("⚠️ " + err, 3000); return; }

  var provider = document.getElementById("provider").value;
  var profile = document.getElementById("profile").value;
  var engine = document.getElementById("engine").value;
  var protocols = selectedProtocols();
  var argoMode = document.getElementById("argoMode").value;
  var argoDomain = (document.getElementById("argoDomain").value || "").trim();
  var argoToken = (document.getElementById("argoToken").value || "").trim();
  var warpMode = document.getElementById("warpMode").value;
  var outMode = document.getElementById("outboundProxyMode").value;
  var outHost = (document.getElementById("outboundProxyHost").value || "").trim();
  var outPort = (document.getElementById("outboundProxyPort").value || "").trim();
  var outUser = (document.getElementById("outboundProxyUser").value || "").trim();
  var outPass = (document.getElementById("outboundProxyPass").value || "").trim();
  var uuidVal = (document.getElementById("uuid").value || "").trim();
  var nodeName = (document.getElementById("nodeName").value || "").trim();
  var cdnEps = getSelectedCdnEndpoints();

  var args = ["install", "--provider " + provider, "--profile " + profile, "--engine " + engine,
    "--protocols " + protocols.join(","), "--argo " + argoMode, "--warp-mode " + warpMode,
    "--outbound-proxy-mode " + outMode];
  if (uuidVal) args.push("--uuid " + uuidVal);
  if (nodeName) args.push("--name " + nodeName);
  if (argoDomain) args.push("--argo-domain " + argoDomain);
  if (argoToken) args.push("--argo-token " + argoToken);
  if (cdnEps) args.push("--cdn-endpoints " + cdnEps);
  if (outMode !== "direct") {
    args.push("--outbound-proxy-host " + outHost);
    args.push("--outbound-proxy-port " + outPort);
    if (outUser) args.push("--outbound-proxy-user " + outUser);
    if (outPass) args.push("--outbound-proxy-pass " + outPass);
  }
  var cmd = "bash <(curl -fsSL https://raw.githubusercontent.com/Develata/sing-box-deve/main/sing-box-deve.sh) " + args.join(" ");
  document.getElementById("resultHint").textContent = "生成安装命令：";
  output.value = cmd;
  showToast("✅ 命令已生成");
}

/* ── Build env template ── */
function buildEnvTemplate() {
  var err = validateForm();
  if (err) { showToast("⚠️ " + err, 3000); return; }

  var provider = document.getElementById("provider").value;
  var profile = document.getElementById("profile").value;
  var engine = document.getElementById("engine").value;
  var protocols = selectedProtocols();
  var argoMode = document.getElementById("argoMode").value;
  var argoDomain = (document.getElementById("argoDomain").value || "").trim();
  var argoToken = (document.getElementById("argoToken").value || "").trim();
  var warpMode = document.getElementById("warpMode").value;
  var warpPK = (document.getElementById("warpPrivateKey").value || "").trim();
  var warpPub = (document.getElementById("warpPeerPublicKey").value || "").trim();
  var outMode = document.getElementById("outboundProxyMode").value;
  var outHost = (document.getElementById("outboundProxyHost").value || "").trim();
  var outPort = (document.getElementById("outboundProxyPort").value || "").trim();
  var outUser = (document.getElementById("outboundProxyUser").value || "").trim();
  var outPass = (document.getElementById("outboundProxyPass").value || "").trim();
  var uuidVal = (document.getElementById("uuid").value || "").trim();
  var nodeName = (document.getElementById("nodeName").value || "").trim();
  var cdnEps = getSelectedCdnEndpoints();

  var lines = [
    "# sing-box-deve env template", "provider=" + provider, "profile=" + profile,
    "engine=" + engine, "protocols=" + protocols.join(","), "",
    "# UUID (leave empty to auto-generate)", "UUID=" + uuidVal, "NODE_NAME=" + nodeName, "",
    "# Argo", "argo_mode=" + argoMode, "argo_domain=" + argoDomain, "argo_token=" + argoToken,
    "ARGO_CDN_ENDPOINTS=" + cdnEps, "",
    "# WARP", "warp_mode=" + warpMode, "WARP_PRIVATE_KEY=" + warpPK, "WARP_PEER_PUBLIC_KEY=" + warpPub, "",
    "# Outbound proxy", "outbound_proxy_mode=" + outMode, "outbound_proxy_host=" + outHost,
    "outbound_proxy_port=" + outPort, "outbound_proxy_user=" + outUser, "outbound_proxy_pass=" + outPass
  ];
  if (provider === "serv00") {
    lines.push("", "# Serv00", "SERV00_HOST=" + (document.getElementById("serv00Host").value || "").trim());
    lines.push("SERV00_USER=" + (document.getElementById("serv00User").value || "").trim());
  }
  if (provider === "sap") {
    lines.push("", "# SAP", "SAP_CF_API=" + (document.getElementById("sapApi").value || "").trim());
    lines.push("SAP_CF_ORG=" + (document.getElementById("sapOrg").value || "").trim());
    lines.push("SAP_CF_SPACE=" + (document.getElementById("sapSpace").value || "").trim());
  }
  document.getElementById("resultHint").textContent = "生成 env 模板：";
  output.value = lines.join("\n") + "\n";
  showToast("✅ env 模板已生成");
}

/* ── Copy ── */
async function copyOutput() {
  var text = output.value;
  if (!text) { showToast("⚠️ 当前没有可复制内容"); return; }
  try {
    await navigator.clipboard.writeText(text);
    showToast("✅ 已复制到剪贴板");
  } catch (_e) {
    showToast("❌ 复制失败，请手动复制");
  }
}

/* ── Shortcut commands ── */
function onShortcutClick(e) {
  var btn = e.target.closest(".shortcut");
  if (!btn) return;
  var cmd = btn.getAttribute("data-cmd");
  var full = "sb " + cmd;
  navigator.clipboard.writeText(full).then(function () {
    showToast("✅ 已复制: " + full);
  }).catch(function () {
    output.value = full;
    showToast("命令: " + full);
  });
}

/* ── Init ── */
document.getElementById("buildCmd").addEventListener("click", buildCommand);
document.getElementById("buildEnv").addEventListener("click", buildEnvTemplate);
document.getElementById("copyOut").addEventListener("click", copyOutput);
document.getElementById("themeToggle").addEventListener("click", toggleTheme);
document.getElementById("genUUID").addEventListener("click", function () {
  document.getElementById("uuid").value = generateUUID();
  showToast("✅ UUID 已生成");
});
document.getElementById("profile").addEventListener("change", refreshProtocolHint);
document.getElementById("provider").addEventListener("change", toggleAdvancedFields);
document.getElementById("argoMode").addEventListener("change", toggleAdvancedFields);
document.getElementById("warpMode").addEventListener("change", toggleAdvancedFields);
document.getElementById("outboundProxyMode").addEventListener("change", toggleAdvancedFields);
document.getElementById("protocols").addEventListener("change", refreshProtocolHint);
document.getElementById("sapRegion").addEventListener("change", onSapRegionChange);
document.querySelector(".shortcut-grid").addEventListener("click", onShortcutClick);

initTheme();
initProtocolList();
toggleAdvancedFields();
