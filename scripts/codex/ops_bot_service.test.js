"use strict";

const assert = require("assert");
const fs = require("fs");
const http = require("http");
const os = require("os");
const path = require("path");
const test = require("node:test");

const { createServer, loadConfig } = require("./ops_bot_service");

function listen(server, host = "127.0.0.1", port = 0) {
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(port, host, () => {
      server.removeListener("error", reject);
      const address = server.address();
      resolve(address && typeof address === "object" ? address.port : port);
    });
  });
}

function closeServer(server) {
  return new Promise((resolve) => {
    server.close(() => resolve());
  });
}

function request({ method, url, headers = {}, body = "" }) {
  return new Promise((resolve, reject) => {
    const parsed = new URL(url);
    const req = http.request(
      {
        protocol: parsed.protocol,
        hostname: parsed.hostname,
        port: parsed.port,
        path: `${parsed.pathname}${parsed.search}`,
        method,
        headers: {
          ...headers,
          "Content-Length": Buffer.byteLength(body),
        },
      },
      (res) => {
        const chunks = [];
        res.on("data", (chunk) => chunks.push(chunk));
        res.on("end", () => {
          resolve({
            statusCode: res.statusCode || 0,
            headers: res.headers || {},
            bodyText: Buffer.concat(chunks).toString("utf8"),
          });
        });
      },
    );
    req.on("error", reject);
    if (body.length > 0) {
      req.write(body);
    }
    req.end();
  });
}

async function requestJson(options) {
  const result = await request(options);
  return {
    ...result,
    body: result.bodyText.trim() ? JSON.parse(result.bodyText) : {},
  };
}

function createTempScripts(t) {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "planka-ops-bot-"));
  t.after(() => {
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  const snapshotScript = path.join(tempDir, "status_snapshot_mock.sh");
  const summaryScript = path.join(tempDir, "log_summary_mock.sh");

  fs.writeFileSync(
    snapshotScript,
    `#!/usr/bin/env bash
set -euo pipefail
cat <<'JSON'
{"generated_at":"2026-03-05T00:00:00Z","overall_status":"HEALTHY","headline":"ok","action_required":"none"}
JSON
`,
    "utf8",
  );
  fs.writeFileSync(
    summaryScript,
    `#!/usr/bin/env bash
set -euo pipefail
echo "summary ok"
`,
    "utf8",
  );
  fs.chmodSync(snapshotScript, 0o755);
  fs.chmodSync(summaryScript, 0o755);

  return { snapshotScript, summaryScript };
}

function createConfig(t, overrides = {}) {
  const scripts = createTempScripts(t);
  return loadConfig({
    OPS_BOT_BIND: "127.0.0.1",
    OPS_BOT_PORT: "0",
    OPS_BOT_WEBHOOK_PATH: "/telegram/webhook",
    OPS_BOT_TG_SECRET_TOKEN: overrides.telegramSecretToken || "",
    OPS_BOT_ALLOWED_CHAT_IDS: "",
    OPS_BOT_STATUS_SNAPSHOT_SCRIPT: scripts.snapshotScript,
    OPS_BOT_LOG_SUMMARY_SCRIPT: scripts.summaryScript,
    OPS_BOT_REFRESH_SEC: "3",
    OPS_BOT_CMD_TIMEOUT_MS: "5000",
    OPS_BOT_PUBLIC_BASE_URL: "https://planka.ewg40.ru",
    OPS_BOT_TG_BOT_TOKEN: "",
  });
}

test("ops bot endpoints and invalid updates are handled safely", async (t) => {
  const config = createConfig(t);
  const service = createServer(config, { info() {}, warn() {}, error() {} });
  const port = await listen(service);
  t.after(async () => {
    await closeServer(service);
  });

  const baseUrl = `http://127.0.0.1:${port}`;

  const health = await requestJson({
    method: "GET",
    url: `${baseUrl}/health`,
  });
  assert.equal(health.statusCode, 200);
  assert.equal(health.body.status, "ok");

  const statusJson = await requestJson({
    method: "GET",
    url: `${baseUrl}/ops/status.json`,
  });
  assert.equal(statusJson.statusCode, 200);
  assert.equal(statusJson.body.overall_status, "HEALTHY");

  const statusPage = await request({
    method: "GET",
    url: `${baseUrl}/ops/status`,
  });
  assert.equal(statusPage.statusCode, 200);
  assert.match(String(statusPage.headers["content-type"] || ""), /text\/html/);
  assert.match(statusPage.bodyText, /PLANKA Ops Board/);

  const invalidJson = await requestJson({
    method: "POST",
    url: `${baseUrl}${config.webhookPath}`,
    headers: { "Content-Type": "application/json" },
    body: "{invalid",
  });
  assert.equal(invalidJson.statusCode, 400);
  assert.equal(invalidJson.body.error, "BAD_REQUEST");

  const unsupportedUpdate = await requestJson({
    method: "POST",
    url: `${baseUrl}${config.webhookPath}`,
    headers: { "Content-Type": "application/json" },
    body: "[]",
  });
  assert.equal(unsupportedUpdate.statusCode, 200);
  assert.equal(unsupportedUpdate.body.ok, true);
  assert.equal(unsupportedUpdate.body.command_handled, false);
  assert.equal(unsupportedUpdate.body.ignored_reason, "unsupported_update");

  const noCommand = await requestJson({
    method: "POST",
    url: `${baseUrl}${config.webhookPath}`,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      update_id: 1,
      message: {
        chat: { id: 12345 },
        text: "hello",
      },
    }),
  });
  assert.equal(noCommand.statusCode, 200);
  assert.equal(noCommand.body.ok, true);
  assert.equal(noCommand.body.command_handled, false);
});

test("oversized webhook payload returns 413", async (t) => {
  const config = createConfig(t);
  const service = createServer(config, { info() {}, warn() {}, error() {} });
  const port = await listen(service);
  t.after(async () => {
    await closeServer(service);
  });

  const largePayload = JSON.stringify({
    update_id: 1,
    message: {
      chat: { id: 1 },
      text: "/status",
      pad: "a".repeat(1024 * 1024),
    },
  });

  const response = await requestJson({
    method: "POST",
    url: `http://127.0.0.1:${port}${config.webhookPath}`,
    headers: { "Content-Type": "application/json" },
    body: largePayload,
  });

  assert.equal(response.statusCode, 413);
  assert.equal(response.body.error, "PAYLOAD_TOO_LARGE");
});

test("telegram secret token is enforced when configured", async (t) => {
  const config = createConfig(t, { telegramSecretToken: "top-secret-token" });
  const service = createServer(config, { info() {}, warn() {}, error() {} });
  const port = await listen(service);
  t.after(async () => {
    await closeServer(service);
  });

  const noSecret = await requestJson({
    method: "POST",
    url: `http://127.0.0.1:${port}${config.webhookPath}`,
    headers: { "Content-Type": "application/json" },
    body: "{}",
  });
  assert.equal(noSecret.statusCode, 401);
  assert.equal(noSecret.body.error, "UNAUTHORIZED");

  const withSecret = await requestJson({
    method: "POST",
    url: `http://127.0.0.1:${port}${config.webhookPath}`,
    headers: {
      "Content-Type": "application/json",
      "X-Telegram-Bot-Api-Secret-Token": "top-secret-token",
    },
    body: "{}",
  });
  assert.equal(withSecret.statusCode, 200);
  assert.equal(withSecret.body.ok, true);
  assert.equal(withSecret.body.command_handled, false);
});
