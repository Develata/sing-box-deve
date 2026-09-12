#!/usr/bin/env node
// Management requires an independent bearer token. Keepalive also runs locally.
const http = require("http");
const { exec } = require("child_process");
const { timingSafeEqual } = require("crypto");
const os = require("os");

function createApp({ env = process.env, execute = exec } = {}) {
  const token = env.SBD_SERV00_ADMIN_TOKEN || "";
  const uuid = env.SBD_UUID || "";
  const home = os.homedir();
  const username = os.userInfo().username.toLowerCase();
  const logs = `${home}/domains/${username}.serv00.net/logs`;
  const quote = value => "'" + value.replace(/'/g, "'\\''") + "'";
  let busy = false;
  function command(cmd) {
    return new Promise((resolve, reject) => {
      execute(cmd, { timeout: 120000, killSignal: "SIGKILL", maxBuffer: 1024 * 1024 }, (error, stdout) => {
        if (error) reject(error); else resolve(stdout);
      });
    });
  }
  async function keepalive() {
    if (busy) return false;
    busy = true;
    try { await command(`cd ${quote(home)} && bash serv00keep.sh`); return true; }
    finally { busy = false; }
  }
  function authorized(req) {
    if (Buffer.byteLength(token) < 32) return false;
    const actual = Buffer.from(req.headers.authorization || "");
    const expected = Buffer.from(`Bearer ${token}`);
    return actual.length === expected.length && timingSafeEqual(actual, expected);
  }
  function send(res, status, body, headers = {}) {
    res.writeHead(status, { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store", ...headers });
    res.end(body);
  }
  const commands = {
    "/up": `cd ${quote(home)} && bash serv00keep.sh`,
    "/re": `
      cd ${quote(logs)} 2>/dev/null || cd ${quote(home)} || exit 1
      sbb="$(cat sb.txt 2>/dev/null || echo sing-box)"
      test -x "./$sbb" && test -s config.json || exit 1
      pkill -f 'run -c con' 2>/dev/null || true
      nohup "./$sbb" run -c config.json >/dev/null 2>&1 &
      sleep 2
      cd ${quote(home)} && bash serv00keep.sh
    `,
    "/rp": `cd ${quote(home)} && bash webport.sh`,
    "/jc": "ps aux"
  };
  const server = http.createServer(async (req, res) => {
    const path = req.url.split("?")[0];
    if (Object.hasOwn(commands, path)) {
      if (!authorized(req)) return send(res, 403, "Management token required.\n");
      const method = path === "/jc" ? "GET" : "POST";
      if (req.method !== method) return send(res, 405, `Use ${method}.\n`, { Allow: method });
      if (busy) return send(res, 409, "A management operation is running.\n");
      busy = true;
      try {
        const stdout = await command(commands[path]);
        send(res, 200, path === "/jc" ? stdout : "Operation completed.\n");
      } catch (_error) { send(res, 500, "Management operation failed.\n"); }
      finally { busy = false; }
      return;
    }
    if (req.method !== "GET") return send(res, 405, "Use GET.\n", { Allow: "GET" });
    if (path === "/health") return send(res, 200, JSON.stringify({ status: "ok" }), { "Content-Type": "application/json" });
    const match = path.match(/^\/list\/([a-f0-9-]+)$/i);
    if (match) {
      if (!uuid || match[1] !== uuid) return send(res, 403, "Invalid or missing UUID.\n");
      try {
        const stdout = await command(`cat ${quote(logs + "/list.txt")} 2>/dev/null || cat ${quote(home + "/sing-box-deve/data/nodes.txt")} 2>/dev/null`);
        send(res, 200, stdout);
      } catch (_error) { send(res, 404, "Node list not found.\n"); }
      return;
    }
    send(res, 404, "Use /health or /list/:uuid. Management requires Authorization: Bearer <token>.\n");
  });
  server.requestTimeout = 15000;
  server.headersTimeout = 10000;
  return { server, keepalive, host: env.SBD_SERV00_HOST || "127.0.0.1" };
}

if (require.main === module) {
  const app = createApp();
  const run = () => app.keepalive().catch(() => console.error("[keepalive] failed"));
  app.server.listen(process.env.SBD_SERV00_PORT || process.env.PORT || 3000, app.host, () => {
    console.log("[serv00-app] Listening on", app.host);
    run();
  });
  const timer = setInterval(run, 135 * 60 * 1000);
  app.server.on("close", () => clearInterval(timer));
}
module.exports = { createApp };
