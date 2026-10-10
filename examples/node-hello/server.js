// Tiny app used by the updatool end-to-end test: answers with its version.
const http = require("http");
const version = process.env.APP_VERSION || "dev";
const delay = Number(process.env.RESPONSE_DELAY_MS || 50);
let shuttingDown = false;
const server = http.createServer((req, res) => {
  if (req.url === "/health") { res.writeHead(shuttingDown ? 503 : 200); return res.end("ok\n"); }
  setTimeout(() => { res.writeHead(200, { "content-type": "text/plain" }); res.end(version + "\n"); }, delay);
});
server.listen(Number(process.env.PORT || 3000), "0.0.0.0");
// Graceful stop: finish in-flight requests, then exit (what updatool expects on SIGTERM).
process.on("SIGTERM", () => { shuttingDown = true; server.close(() => process.exit(0)); setTimeout(() => process.exit(0), 10000).unref(); });
