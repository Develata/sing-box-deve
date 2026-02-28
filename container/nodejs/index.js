const os = require("os");
const http = require("http");
const fs = require("fs");
const net = require("net");
const { exec } = require("child_process");
const { WebSocket, createWebSocketStream } = require("ws");

const HOME = process.env.HOME || "/root";
const SUB_FILE = `${HOME}/sing-box-deve/data/jhdy.txt`;
const PORT = parseInt(process.env.PORT, 10) || 3000;
const uuid = process.env.UUID || process.env.uuid || "79411d85-b0dc-4cd2-b46c-01789a18c650";
const DOMAIN = process.env.DOMAIN || process.env.domain || "";
const NAME = process.env.NAME || process.env.name || os.hostname();
const uuidKey = uuid.replace(/-/g, "");

const vlessInfo = DOMAIN
  ? `vless://${uuid}@${DOMAIN}:443?encryption=none&security=tls&sni=${DOMAIN}&fp=chrome&type=ws&host=${DOMAIN}&path=%2F#sbd-vl-ws-tls-${NAME}`
  : "";

if (vlessInfo) {
  console.log(`vless-ws-tls node: ${vlessInfo}`);
}

fs.access("start.sh", fs.constants.F_OK, (err) => {
  if (err) {
    console.log("start.sh not found, skipping protocol bootstrap.");
    return;
  }
  fs.chmod("start.sh", 0o777, (chmodErr) => {
    if (chmodErr) {
      console.error(`start.sh chmod failed: ${chmodErr}`);
      return;
    }
    console.log("Launching start.sh ...");
    const child = exec("bash start.sh");
    child.stdout.on("data", (data) => process.stdout.write(data));
    child.stderr.on("data", (data) => process.stderr.write(data));
    child.on("close", (code) => {
      console.log(`start.sh exited with code ${code}`);
    });
  });
});

const server = http.createServer((req, res) => {
  if (req.url === "/") {
    res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("sing-box-deve container is running.\n\nView nodes: /<uuid>");
    return;
  }
  if (req.url === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ status: "ok", uptime: process.uptime() }));
    return;
  }
  if (req.url === `/${uuid}`) {
    res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
    const header = vlessInfo ? vlessInfo + "\n" : "";
    if (fs.existsSync(SUB_FILE)) {
      fs.readFile(SUB_FILE, "utf8", (readErr, data) => {
        if (readErr) {
          res.end(header || "No nodes available.");
        } else {
          res.end(header + data);
        }
      });
    } else {
      res.end(header || "No nodes generated yet. Run the installer first.");
    }
    return;
  }
  res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
  res.end("404 Not Found");
});

server.listen(PORT, () => {
  console.log(`Server listening on port ${PORT}`);
});

const wss = new (require("ws").Server)({ server });

wss.on("connection", (ws) => {
  ws.once("message", (msg) => {
    const VERSION = msg[0];
    const id = msg.slice(1, 17);
    const valid = id.every(
      (v, i) => v === parseInt(uuidKey.substr(i * 2, 2), 16)
    );
    if (!valid) return;

    let i = msg.slice(17, 18).readUInt8() + 19;
    const port = msg.slice(i, (i += 2)).readUInt16BE(0);
    const ATYP = msg.slice(i, (i += 1)).readUInt8();

    let host = "";
    if (ATYP === 1) {
      host = msg.slice(i, (i += 4)).join(".");
    } else if (ATYP === 2) {
      const len = msg.slice(i, i + 1).readUInt8();
      host = new TextDecoder().decode(msg.slice(i + 1, (i += 1 + len)));
    } else if (ATYP === 3) {
      host = msg
        .slice(i, (i += 16))
        .reduce(
          (s, b, idx, a) => (idx % 2 ? s.concat(a.slice(idx - 1, idx + 1)) : s),
          []
        )
        .map((b) => b.readUInt16BE(0).toString(16))
        .join(":");
    }

    ws.send(new Uint8Array([VERSION, 0]));
    const duplex = createWebSocketStream(ws);
    net
      .connect({ host, port }, function () {
        this.write(msg.slice(i));
        duplex
          .on("error", () => {})
          .pipe(this)
          .on("error", () => {})
          .pipe(duplex);
      })
      .on("error", () => {});
  });
  ws.on("error", () => {});
});
