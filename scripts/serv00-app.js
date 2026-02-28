#!/usr/bin/env node
/**
 * serv00-app.js — Serv00 management web service for sing-box-deve
 * Endpoints:
 *   GET /up           — Keepalive: run serv00keep.sh
 *   GET /re           — Restart core engine process
 *   GET /rp           — Reset ports via webport.sh
 *   GET /jc           — Show running processes
 *   GET /list/:uuid   — Show node list if uuid matches
 *   GET /health       — Health check
 */

const http = require("http");
const { exec, spawn } = require("child_process");
const os = require("os");

const PORT = process.env.SBD_SERV00_PORT || process.env.PORT || 3000;
const SBD_UUID = process.env.SBD_UUID || "";
const KEEPALIVE_INTERVAL_MS = (2 * 60 + 15) * 60 * 1000; // ~2h15m

const USERNAME = (os.userInfo().username || "").toLowerCase();
const HOME = os.homedir();
const LOGS_DIR = `${HOME}/domains/${USERNAME}.serv00.net/logs`;

// ── Helpers ──────────────────────────────────────────────────────

function execCommand(cmd, opts = {}) {
  return new Promise((resolve, reject) => {
    exec(cmd, { maxBuffer: 10 * 1024 * 1024, ...opts }, (err, stdout, stderr) => {
      if (err) return reject({ err, stdout, stderr });
      resolve({ stdout, stderr });
    });
  });
}

function html(title, body) {
  return `<!DOCTYPE html><html><head><meta charset="utf-8"><title>${title}</title></head><body><pre>${body}</pre></body></html>`;
}

// ── Keepalive ────────────────────────────────────────────────────

async function runKeepalive() {
  try {
    const { stdout } = await execCommand(`cd ${HOME} && bash serv00keep.sh`);
    console.log("[keepalive] OK:", stdout.trim().slice(0, 200));
  } catch (e) {
    console.error("[keepalive] FAIL:", e.err?.message || e.stderr);
  }
}

// ── Route handlers ───────────────────────────────────────────────

async function handleUp(req, res) {
  runKeepalive();
  res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
  res.end(html("Keepalive", "sing-box-deve keepalive triggered. UP! UP! UP!"));
}

async function handleRestart(req, res) {
  const cmd = `
    cd "${LOGS_DIR}" 2>/dev/null || cd "${HOME}"
    pkill -f 'run -c con' 2>/dev/null || echo "No process to kill, proceeding to restart..."
    sbb="$(cat sb.txt 2>/dev/null || echo 'sing-box')"
    nohup ./"$sbb" run -c config.json >/dev/null 2>&1 &
    sleep 2
    (cd "${HOME}" && bash serv00keep.sh >/dev/null 2>&1) &
    echo 'Core engine restarted. Check nodes availability.'
  `;
  try {
    const { stdout } = await execCommand(cmd);
    res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
    res.end(stdout);
  } catch (e) {
    res.writeHead(500, { "Content-Type": "text/plain; charset=utf-8" });
    res.end(`Error: ${e.stderr || e.stdout || e.err?.message}`);
  }
}

async function handleResetPorts(req, res) {
  try {
    await execCommand(`cd "${HOME}" && bash webport.sh`);
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    res.end(html("Reset Ports",
      "Ports reset complete. Close this page, wait 20s, then visit /list/YOUR_UUID to see updated nodes."));
  } catch (e) {
    res.writeHead(500, { "Content-Type": "text/plain; charset=utf-8" });
    res.end(`Error: ${e.stderr || e.err?.message}`);
  }
}

function handleProcessList(req, res) {
  const ps = spawn("ps", ["aux"]);
  res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
  ps.stdout.on("data", (d) => res.write(d));
  ps.stderr.on("data", (d) => res.write(d));
  ps.on("close", () => res.end());
  ps.on("error", (err) => {
    res.writeHead(500);
    res.end(`Error: ${err.message}`);
  });
}

async function handleList(req, uuid) {
  // Require valid UUID
  const res = arguments[1];
  const reqUuid = arguments[2];
  if (!SBD_UUID || reqUuid !== SBD_UUID) {
    res.writeHead(403, { "Content-Type": "text/plain" });
    res.end("Invalid or missing UUID.");
    return;
  }

  const listFile = `${LOGS_DIR}/list.txt`;
  const altFile = `${HOME}/sing-box-deve/data/nodes.txt`;
  const cmd = `cat "${listFile}" 2>/dev/null || cat "${altFile}" 2>/dev/null || echo "No node list found."`;
  try {
    const { stdout } = await execCommand(cmd);
    res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
    res.end(stdout);
  } catch (e) {
    res.writeHead(404, { "Content-Type": "text/plain" });
    res.end("Node list not found.");
  }
}

function handleHealth(req, res) {
  res.writeHead(200, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ status: "ok", user: USERNAME, uptime: process.uptime() | 0 }));
}

// ── HTTP server ──────────────────────────────────────────────────

const server = http.createServer((req, res) => {
  const url = req.url.replace(/\?.*$/, "");

  if (url === "/up") return handleUp(req, res);
  if (url === "/re") return handleRestart(req, res);
  if (url === "/rp") return handleResetPorts(req, res);
  if (url === "/jc") return handleProcessList(req, res);
  if (url === "/health") return handleHealth(req, res);

  const listMatch = url.match(/^\/list\/([a-f0-9-]+)$/i);
  if (listMatch) return handleList(req, res, listMatch[1]);

  res.writeHead(404, { "Content-Type": "text/html; charset=utf-8" });
  res.end(html("sing-box-deve Serv00",
    "Endpoints:\n" +
    "  /up         - Keepalive\n" +
    "  /re         - Restart engine\n" +
    "  /rp         - Reset ports\n" +
    "  /jc         - Process list\n" +
    "  /list/:uuid - Node & subscription info\n" +
    "  /health     - Health check"));
});

server.listen(PORT, () => {
  console.log(`[serv00-app] Listening on port ${PORT}`);
  runKeepalive();
});

// Periodic keepalive
setInterval(runKeepalive, KEEPALIVE_INTERVAL_MS);
