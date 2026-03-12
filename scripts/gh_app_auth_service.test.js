"use strict";

const assert = require("assert");
const crypto = require("crypto");
const fs = require("fs");
const http = require("http");
const os = require("os");
const path = require("path");
const test = require("node:test");

const { createServer, loadConfig } = require("./gh_app_auth_service");

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

function getJson(url, headers = {}) {
  return new Promise((resolve, reject) => {
    const req = http.get(
      url,
      {
        headers,
      },
      (res) => {
        const chunks = [];
        res.on("data", (chunk) => chunks.push(chunk));
        res.on("end", () => {
          const bodyText = Buffer.concat(chunks).toString("utf8");
          resolve({
            statusCode: res.statusCode || 0,
            body: JSON.parse(bodyText),
          });
        });
      },
    );
    req.on("error", reject);
  });
}

function createTempPrivateKeyFile(t) {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "planka-gh-app-auth-"));
  t.after(() => {
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  const { privateKey } = crypto.generateKeyPairSync("rsa", { modulusLength: 2048 });
  const privateKeyPath = path.join(tempDir, "gh-app.private-key.pem");
  fs.writeFileSync(privateKeyPath, privateKey.export({ type: "pkcs1", format: "pem" }), "utf8");
  return privateKeyPath;
}

function createConfig(overrides) {
  return loadConfig({
    GH_APP_ID: "123456",
    GH_APP_INSTALLATION_ID: "654321",
    GH_APP_PRIVATE_KEY_PATH: overrides.privateKeyPath,
    GH_APP_INTERNAL_SECRET: "internal-secret",
    GH_APP_BIND: "127.0.0.1",
    GH_APP_PORT: "0",
    GH_APP_TOKEN_SKEW_SEC: String(overrides.skewSec || 300),
    GH_APP_API_BASE_URL: overrides.apiBaseUrl,
    GH_APP_HTTP_TIMEOUT_MS: "5000",
  });
}

test("GET /health and GET /token use cache and do not leak token into logs", async (t) => {
  const privateKeyPath = createTempPrivateKeyFile(t);
  let upstreamCalls = 0;
  const mockGitHub = http.createServer((req, res) => {
    if (req.method !== "POST" || req.url !== "/app/installations/654321/access_tokens") {
      res.statusCode = 404;
      res.end("{}");
      return;
    }
    upstreamCalls += 1;
    assert.match(String(req.headers.authorization || ""), /^Bearer .+\..+\..+/);
    const payload = {
      token: "mock-installation-token-1",
      expires_at: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
    };
    res.setHeader("Content-Type", "application/json");
    res.end(JSON.stringify(payload));
  });
  const githubPort = await listen(mockGitHub);
  t.after(async () => {
    await closeServer(mockGitHub);
  });

  const logs = [];
  const logger = {
    info(message) {
      logs.push(String(message));
    },
    error(message) {
      logs.push(String(message));
    },
  };

  const config = createConfig({
    privateKeyPath,
    apiBaseUrl: `http://127.0.0.1:${githubPort}`,
  });
  const service = createServer(config, { logger });
  const servicePort = await listen(service);
  t.after(async () => {
    await closeServer(service);
  });

  const baseUrl = `http://127.0.0.1:${servicePort}`;

  const health = await getJson(`${baseUrl}/health`);
  assert.equal(health.statusCode, 200);
  assert.equal(health.body.status, "ok");
  assert.equal(health.body.token_cached, false);

  const unauthorized = await getJson(`${baseUrl}/token`);
  assert.equal(unauthorized.statusCode, 401);
  assert.equal(unauthorized.body.error, "UNAUTHORIZED");

  const tokenResponseFirst = await getJson(`${baseUrl}/token`, {
    "X-Internal-Secret": "internal-secret",
  });
  assert.equal(tokenResponseFirst.statusCode, 200);
  assert.equal(tokenResponseFirst.body.token, "mock-installation-token-1");
  assert.equal(tokenResponseFirst.body.source, "refreshed");

  const tokenResponseSecond = await getJson(`${baseUrl}/token`, {
    "X-Internal-Secret": "internal-secret",
  });
  assert.equal(tokenResponseSecond.statusCode, 200);
  assert.equal(tokenResponseSecond.body.token, "mock-installation-token-1");
  assert.equal(tokenResponseSecond.body.source, "cache");
  assert.equal(upstreamCalls, 1);

  assert.equal(logs.join("\n").includes("mock-installation-token-1"), false);
});

test("token refresh happens before token expiry using skew window", async (t) => {
  const privateKeyPath = createTempPrivateKeyFile(t);
  let upstreamCalls = 0;
  const mockGitHub = http.createServer((req, res) => {
    if (req.method !== "POST" || req.url !== "/app/installations/654321/access_tokens") {
      res.statusCode = 404;
      res.end("{}");
      return;
    }
    upstreamCalls += 1;
    const payload =
      upstreamCalls === 1
        ? {
            token: "short-lived-token",
            expires_at: new Date(Date.now() + 3000).toISOString(),
          }
        : {
            token: "refreshed-token",
            expires_at: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
          };
    res.setHeader("Content-Type", "application/json");
    res.end(JSON.stringify(payload));
  });
  const githubPort = await listen(mockGitHub);
  t.after(async () => {
    await closeServer(mockGitHub);
  });

  const config = createConfig({
    privateKeyPath,
    apiBaseUrl: `http://127.0.0.1:${githubPort}`,
    skewSec: 5,
  });
  const service = createServer(config, {
    logger: { info() {}, error() {} },
  });
  const servicePort = await listen(service);
  t.after(async () => {
    await closeServer(service);
  });

  const baseUrl = `http://127.0.0.1:${servicePort}`;
  const first = await getJson(`${baseUrl}/token`, {
    "X-Internal-Secret": "internal-secret",
  });
  assert.equal(first.statusCode, 200);
  assert.equal(first.body.token, "short-lived-token");
  assert.equal(first.body.source, "refreshed");

  const second = await getJson(`${baseUrl}/token`, {
    "X-Internal-Secret": "internal-secret",
  });
  assert.equal(second.statusCode, 200);
  assert.equal(second.body.token, "refreshed-token");
  assert.equal(second.body.source, "refreshed");
  assert.equal(upstreamCalls, 2);
});
