/* sing-box-deve command generator - app.js */

const schema = window.SBD_WEB_SCHEMA || {};
const protocolHints = schema.protocolHints || {};
const protocolMeta = {};
Object.keys(protocolHints).forEach(function (p) { protocolMeta[p] = protocolHints[p]; });
const protocolsAll = schema.protocols || Object.keys(protocolMeta);
const domainCertProtocols = ["hysteria2", "tuic", "naive"];
const CDN_TLS_PORTS = [443, 8443, 2053, 2083, 2087, 2096];
const CDN_PLAIN_PORTS = [80, 8080, 8880, 2052, 2082, 2086, 2095];

const protocolBox = document.getElementById("protocols");
const output = document.getElementById("output");
const hint = document.getElementById("protocolHint");

function byId(id) { return document.getElementById(id); }
function fieldValue(id) { return (byId(id).value || "").trim(); }

function showToast(msg, duration) {
  duration = duration || 2500;
  var el = byId("toast");
  el.textContent = msg;
  el.classList.remove("hidden");
  clearTimeout(el._timer);
  el._timer = setTimeout(function () { el.classList.add("hidden"); }, duration);
}

function generateUUID() {
  if (crypto && crypto.randomUUID) return crypto.randomUUID();
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (c) {
    var r = (Math.random() * 16) | 0;
    return (c === "x" ? r : (r & 0x3) | 0x8).toString(16);
  });
}

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
  var btn = byId("themeToggle");
  if (btn) btn.textContent = theme === "light" ? "☀️" : "🌙";
}

function fillSelect(id, values, labels) {
  var el = byId(id);
  el.innerHTML = "";
  (values || []).forEach(function (value) {
    var opt = document.createElement("option");
    opt.value = value;
    opt.textContent = labels && labels[value] ? labels[value] : value;
    el.appendChild(opt);
  });
}

function initSchemaSelects() {
  fillSelect("tlsMode", schema.tlsModes || ["self-signed", "acme", "acme-auto"], {
    "self-signed": "self-signed（仅非域名证书协议）",
    acme: "acme（已有证书路径）",
    "acme-auto": "acme-auto（standalone 自动签发）"
  });
  fillSelect("webFrontMode", schema.webFrontModes || ["auto", "off", "nginx", "openresty"], {
    auto: "auto（OpenResty 优先，其次 nginx）",
    off: "off（仅 Hysteria2 masquerade）",
    nginx: "nginx-family（若有 OpenResty 仍优先）",
    openresty: "openresty"
  });
  fillSelect("hy2ObfsMode", schema.hy2ObfsModes || ["off", "salamander"], {
    off: "off（默认）",
    salamander: "salamander（高级 opt-in）"
  });
}

function initProtocolList() {
  protocolsAll.forEach(function (p) {
    var label = document.createElement("label");
    label.className = "pill";
    label.innerHTML = '<input type="checkbox" value="' + p + '">' + p;
    protocolBox.appendChild(label);
  });
  applyPresetToForm();
  refreshProtocolHint();
}

function setSelectedProtocols(protocols) {
  var wanted = new Set(protocols || []);
  document.querySelectorAll('#protocols input[type="checkbox"]').forEach(function (cb) {
    cb.checked = wanted.has(cb.value);
  });
}

function selectedProtocols() {
  var boxes = document.querySelectorAll('#protocols input[type="checkbox"]:checked');
  return Array.from(boxes).map(function (x) { return x.value; });
}

function currentPreset() { return byId("preset").value; }
function presetMeta() { return (schema.presets || {})[currentPreset()] || null; }
function requiresDomainCert() {
  var preset = presetMeta();
  if (preset) return !!preset.requiresDomainCert;
  return selectedProtocols().some(function (p) { return domainCertProtocols.indexOf(p) >= 0; });
}
function hasHy2() { return selectedProtocols().indexOf("hysteria2") >= 0; }

function applyPresetToForm() {
  var preset = presetMeta();
  if (!preset) return;
  byId("engine").value = preset.engine;
  byId("profile").value = preset.profile;
  setSelectedProtocols(preset.protocols.split(","));
  refreshProtocolHint();
  toggleAdvancedFields();
}

function refreshProtocolHint() {
  var selected = selectedProtocols();
  if (!selected.length) { hint.textContent = "未选择协议。"; return; }
  hint.innerHTML = selected.map(function (p) {
    return p + ": " + (protocolMeta[p] || "n/a");
  }).join("<br>");
}

function getSelectedCdnEndpoints() {
  var argoMode = byId("argoMode").value;
  if (argoMode === "off") return "";
  var cdnHost = fieldValue("cdnHost");
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

function shQuote(value) {
  value = String(value == null ? "" : value);
  if (/^[A-Za-z0-9_@%+=:,./-]+$/.test(value)) return value;
  return "'" + value.replace(/'/g, "'\\''") + "'";
}
function pushArg(args, flag, value) {
  args.push(flag);
  args.push(shQuote(value));
}

function toggleAdvancedFields() {
  var provider = byId("provider").value;
  var preset = currentPreset();
  var argoMode = byId("argoMode").value;
  var warpMode = byId("warpMode").value;
  var outboundProxyMode = byId("outboundProxyMode").value;
  var tlsMode = byId("tlsMode").value;
  var hy2ObfsMode = byId("hy2ObfsMode").value;
  var domainRequired = requiresDomainCert();

  byId("argoFixed").classList.toggle("hidden", argoMode !== "fixed");
  byId("warpKeys").classList.toggle("hidden", warpMode !== "global");
  byId("serv00Fields").classList.toggle("hidden", provider !== "serv00");
  byId("outboundProxyFields").classList.toggle("hidden", outboundProxyMode === "direct");
  byId("cdnPanel").classList.toggle("hidden", argoMode === "off");
  byId("tlsPanel").classList.toggle("hidden", !domainRequired && preset !== "custom");
  byId("tlsAcmePaths").classList.toggle("hidden", tlsMode !== "acme");
  byId("tlsAcmeAuto").classList.toggle("hidden", tlsMode !== "acme-auto");
  byId("hy2ObfsPasswordRow").classList.toggle("hidden", hy2ObfsMode === "off");
}

function validateForm() {
  var profile = byId("profile").value;
  var engine = byId("engine").value;
  var protocols = selectedProtocols();
  var support = (schema.engineSupport || {})[engine] || protocolsAll;
  var argoMode = byId("argoMode").value;
  var argoToken = fieldValue("argoToken");
  var warpMode = byId("warpMode").value;
  var warpPK = fieldValue("warpPrivateKey");
  var warpPub = fieldValue("warpPeerPublicKey");
  var outMode = byId("outboundProxyMode").value;
  var outHost = fieldValue("outboundProxyHost");
  var outPort = fieldValue("outboundProxyPort");
  var provider = byId("provider").value;
  var tlsMode = byId("tlsMode").value;
  var tlsSni = fieldValue("tlsSni");
  var cert = fieldValue("acmeCertPath");
  var key = fieldValue("acmeKeyPath");
  var email = fieldValue("acmeEmail");
  var hy2ObfsMode = byId("hy2ObfsMode").value;
  var hy2ObfsPassword = fieldValue("hy2ObfsPassword");

  if (!protocols.length) return "至少选择一个协议";
  if (profile === "lite" && protocols.length > 2) return "Lite 模式最多 2 个协议";
  var unsupported = protocols.filter(function (p) { return support.indexOf(p) < 0; });
  if (unsupported.length) return engine + " 不支持: " + unsupported.join(",");
  if (requiresDomainCert()) {
    if (!tlsSni) return "域名证书协议必须填写 TLS 域名 / SNI";
    if (tlsMode === "self-signed") return "域名证书协议不能使用 self-signed，请选择 acme 或 acme-auto";
    if (tlsMode === "acme" && (!cert || !key)) return "TLS 模式 acme 必须填写证书和私钥路径";
    if (tlsMode === "acme-auto" && !email) return "TLS 模式 acme-auto 必须填写 ACME_EMAIL";
  }
  if (hy2ObfsMode !== "off" && !hasHy2()) return "启用 Hysteria2 obfs 时必须选择 hysteria2";
  if (hy2ObfsPassword && hy2ObfsPassword.length < 8) return "HY2_OBFS_PASSWORD 至少 8 个字符";
  if (argoMode === "fixed" && !argoToken) return "Argo fixed 模式必须填写 token";
  if (warpMode === "global" && outMode !== "direct") return "WARP global 与上游出站代理不能同时启用";
  if (warpMode === "global" && (!warpPK || !warpPub)) return "WARP global 模式必须填写两项 key";
  if (outMode !== "direct" && (!outHost || !outPort)) return "出站代理启用时必须填写 host 和 port";
  if (provider === "serv00" && (!fieldValue("serv00Host") || !fieldValue("serv00User"))) return "serv00 场景建议填写 SERV00_HOST 和 SERV00_USER";
  return "";
}

function collectValues() {
  return {
    provider: byId("provider").value,
    profile: byId("profile").value,
    engine: byId("engine").value,
    preset: currentPreset(),
    protocols: selectedProtocols(),
    uuid: fieldValue("uuid"),
    tlsMode: byId("tlsMode").value,
    tlsSni: fieldValue("tlsSni"),
    acmeCertPath: fieldValue("acmeCertPath"),
    acmeKeyPath: fieldValue("acmeKeyPath"),
    acmeEmail: fieldValue("acmeEmail"),
    webFrontMode: byId("webFrontMode").value,
    hy2ObfsMode: byId("hy2ObfsMode").value,
    hy2ObfsPassword: fieldValue("hy2ObfsPassword"),
    argoMode: byId("argoMode").value,
    argoDomain: fieldValue("argoDomain"),
    argoToken: fieldValue("argoToken"),
    warpMode: byId("warpMode").value,
    outMode: byId("outboundProxyMode").value,
    outHost: fieldValue("outboundProxyHost"),
    outPort: fieldValue("outboundProxyPort"),
    outUser: fieldValue("outboundProxyUser"),
    outPass: fieldValue("outboundProxyPass"),
    cdnEps: getSelectedCdnEndpoints()
  };
}

function appendDomainArgs(args, v) {
  if (v.tlsSni) pushArg(args, "--tls-sni", v.tlsSni);
  if (v.tlsMode !== "self-signed" || requiresDomainCert()) pushArg(args, "--tls-mode", v.tlsMode);
  if (v.tlsMode === "acme") {
    if (v.acmeCertPath) pushArg(args, "--acme-cert-path", v.acmeCertPath);
    if (v.acmeKeyPath) pushArg(args, "--acme-key-path", v.acmeKeyPath);
  }
  if (v.tlsMode === "acme-auto" && v.acmeEmail) pushArg(args, "--acme-email", v.acmeEmail);
  if (requiresDomainCert() || v.webFrontMode !== "auto") pushArg(args, "--web-front", v.webFrontMode);
  if (v.hy2ObfsMode !== "off") {
    pushArg(args, "--hy2-obfs", v.hy2ObfsMode);
    if (v.hy2ObfsPassword) pushArg(args, "--hy2-obfs-password", v.hy2ObfsPassword);
  }
}

function buildCommand() {
  var err = validateForm();
  if (err) { showToast("⚠️ " + err, 3000); return; }
  var v = collectValues();
  var args = ["install"];
  pushArg(args, "--provider", v.provider);
  if (v.preset !== "custom") {
    pushArg(args, "--preset", v.preset);
  } else {
    pushArg(args, "--profile", v.profile);
    pushArg(args, "--engine", v.engine);
    pushArg(args, "--protocols", v.protocols.join(","));
  }
  pushArg(args, "--argo", v.argoMode);
  pushArg(args, "--warp-mode", v.warpMode);
  pushArg(args, "--outbound-proxy-mode", v.outMode);
  if (v.uuid) pushArg(args, "--uuid", v.uuid);
  appendDomainArgs(args, v);
  if (v.argoDomain) pushArg(args, "--argo-domain", v.argoDomain);
  if (v.argoToken) pushArg(args, "--argo-token", v.argoToken);
  if (v.cdnEps) pushArg(args, "--cdn-endpoints", v.cdnEps);
  if (v.outMode !== "direct") {
    pushArg(args, "--outbound-proxy-host", v.outHost);
    pushArg(args, "--outbound-proxy-port", v.outPort);
    if (v.outUser) pushArg(args, "--outbound-proxy-user", v.outUser);
    if (v.outPass) pushArg(args, "--outbound-proxy-pass", v.outPass);
  }
  output.value = "bash <(curl -fsSL https://raw.githubusercontent.com/Develata/sing-box-deve/main/sing-box-deve.sh) " + args.join(" ");
  byId("resultHint").textContent = "生成安装命令：";
  showToast("✅ 命令已生成");
}

function buildEnvTemplate() {
  var err = validateForm();
  if (err) { showToast("⚠️ " + err, 3000); return; }
  var v = collectValues();
  var protocolsValue = v.preset !== "custom" && schema.presets[v.preset] ? schema.presets[v.preset].protocols : v.protocols.join(",");
  var lines = [
    "# sing-box-deve env template", "provider=" + v.provider, "profile=" + v.profile,
    "engine=" + v.engine, "protocols=" + protocolsValue, "", "# UUID", "UUID=" + v.uuid, "",
    "# Domain TLS / web front", "tls_mode=" + v.tlsMode, "tls_server_name=" + v.tlsSni,
    "acme_cert_path=" + v.acmeCertPath, "acme_key_path=" + v.acmeKeyPath, "acme_email=" + v.acmeEmail,
    "web_front_mode=" + v.webFrontMode, "hy2_obfs_mode=" + v.hy2ObfsMode, "hy2_obfs_password=" + v.hy2ObfsPassword, "",
    "# Argo", "argo_mode=" + v.argoMode, "argo_domain=" + v.argoDomain, "argo_token=" + v.argoToken,
    "ARGO_CDN_ENDPOINTS=" + v.cdnEps, "", "# WARP", "warp_mode=" + v.warpMode,
    "", "# Outbound proxy", "outbound_proxy_mode=" + v.outMode, "outbound_proxy_host=" + v.outHost,
    "outbound_proxy_port=" + v.outPort, "outbound_proxy_user=" + v.outUser, "outbound_proxy_pass=" + v.outPass
  ];
  if (v.provider === "serv00") {
    lines.push("", "# Serv00", "SERV00_HOST=" + fieldValue("serv00Host"), "SERV00_USER=" + fieldValue("serv00User"));
  }
  byId("resultHint").textContent = "生成 env 模板：";
  output.value = lines.join("\n") + "\n";
  showToast("✅ env 模板已生成");
}

async function copyOutput() {
  var text = output.value;
  if (!text) { showToast("⚠️ 当前没有可复制内容"); return; }
  try { await navigator.clipboard.writeText(text); showToast("✅ 已复制到剪贴板"); }
  catch (_e) { showToast("❌ 复制失败，请手动复制"); }
}

function onShortcutClick(e) {
  var btn = e.target.closest(".shortcut");
  if (!btn) return;
  var full = "sb " + btn.getAttribute("data-cmd");
  navigator.clipboard.writeText(full).then(function () { showToast("✅ 已复制: " + full); }).catch(function () {
    output.value = full;
    showToast("命令: " + full);
  });
}

byId("buildCmd").addEventListener("click", buildCommand);
byId("buildEnv").addEventListener("click", buildEnvTemplate);
byId("copyOut").addEventListener("click", copyOutput);
byId("themeToggle").addEventListener("click", toggleTheme);
byId("genUUID").addEventListener("click", function () { byId("uuid").value = generateUUID(); showToast("✅ UUID 已生成"); });
byId("preset").addEventListener("change", applyPresetToForm);
byId("profile").addEventListener("change", refreshProtocolHint);
byId("engine").addEventListener("change", refreshProtocolHint);
byId("provider").addEventListener("change", toggleAdvancedFields);
byId("argoMode").addEventListener("change", toggleAdvancedFields);
byId("warpMode").addEventListener("change", toggleAdvancedFields);
byId("outboundProxyMode").addEventListener("change", toggleAdvancedFields);
byId("tlsMode").addEventListener("change", toggleAdvancedFields);
byId("hy2ObfsMode").addEventListener("change", toggleAdvancedFields);
byId("protocols").addEventListener("change", function () { byId("preset").value = "custom"; refreshProtocolHint(); toggleAdvancedFields(); });
document.querySelector(".shortcut-grid").addEventListener("click", onShortcutClick);

initTheme();
initSchemaSelects();
initProtocolList();
toggleAdvancedFields();
