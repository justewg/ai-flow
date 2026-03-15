#!/usr/bin/env node
"use strict";

const crypto = require("crypto");
const fs = require("fs");
const http = require("http");
const https = require("https");
const path = require("path");

const DEFAULT_API_BASE_URL = "https://api.github.com";
const DEFAULT_BIND = "127.0.0.1";
const DEFAULT_PORT = 8787;
const DEFAULT_SKEW_SEC = 300;
const DEFAULT_TIMEOUT_MS = 10000;

class ServiceError extends Error {
  constructor(httpStatus, code, message) {
    super(message);
    this.name = "ServiceError";
    this.httpStatus = httpStatus;
    this.code = code;
  }
}

function toBase64Url(input) {
  return Buffer.from(input)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function safeCompare(left, right) {
  const leftBuffer = Buffer.from(String(left ?? ""), "utf8");
  const rightBuffer = Buffer.from(String(right ?? ""), "utf8");
  if (leftBuffer.length !== rightBuffer.length) {
    return false;
  }
  return crypto.timingSafeEqual(leftBuffer, rightBuffer);
}

function parseInteger(value, fallback) {
  const parsed = Number.parseInt(String(value ?? fallback), 10);
  return Number.isNaN(parsed) ? fallback : parsed;
}

function parsePort(value, fallback) {
  const port = parseInteger(value, fallback);
  if (!Number.isInteger(port) || port < 0 || port > 65535) {
    throw new Error("GH_APP_PORT must be an integer in range 0..65535");
  }
  return port;
}

function parseSkewSec(value, fallback) {
  const skew = parseInteger(value, fallback);
  if (!Number.isInteger(skew) || skew < 0 || skew > 3600) {
    throw new Error("GH_APP_TOKEN_SKEW_SEC must be an integer in range 0..3600");
  }
  return skew;
}

function normalizeUrl(rawUrl) {
  const input = String(rawUrl || DEFAULT_API_BASE_URL);
  const url = new URL(input);
  if (url.protocol !== "https:" && url.protocol !== "http:") {
    throw new Error("GH_APP_API_BASE_URL must use http:// or https://");
  }
  if (!url.pathname.endsWith("/")) {
    url.pathname = `${url.pathname}/`;
  }
  return url.toString();
}

function loadConfig(env = process.env) {
  const appId = String(env.GH_APP_ID || "").trim();
  const installationId = String(env.GH_APP_INSTALLATION_ID || "").trim();
  const privateKeyPathRaw = String(env.GH_APP_PRIVATE_KEY_PATH || "").trim();
  const internalSecret = String(env.GH_APP_INTERNAL_SECRET || "");
  const bind = String(env.GH_APP_BIND || DEFAULT_BIND).trim();
  const port = parsePort(env.GH_APP_PORT, DEFAULT_PORT);
  const tokenSkewSec = parseSkewSec(env.GH_APP_TOKEN_SKEW_SEC, DEFAULT_SKEW_SEC);
  const apiBaseUrl = normalizeUrl(env.GH_APP_API_BASE_URL);
  const requestTimeoutMs = parseInteger(env.GH_APP_HTTP_TIMEOUT_MS, DEFAULT_TIMEOUT_MS);

  if (!appId) {
    throw new Error("GH_APP_ID is required");
  }
  if (!installationId) {
    throw new Error("GH_APP_INSTALLATION_ID is required");
  }
  if (!privateKeyPathRaw) {
    throw new Error("GH_APP_PRIVATE_KEY_PATH is required");
  }
  if (!internalSecret) {
    throw new Error("GH_APP_INTERNAL_SECRET is required");
  }
  if (bind !== "127.0.0.1") {
    throw new Error("GH_APP_BIND must be 127.0.0.1");
  }
  if (!Number.isInteger(requestTimeoutMs) || requestTimeoutMs < 1000 || requestTimeoutMs > 120000) {
    throw new Error("GH_APP_HTTP_TIMEOUT_MS must be an integer in range 1000..120000");
  }

  const privateKeyPath = path.resolve(privateKeyPathRaw);
  if (!fs.existsSync(privateKeyPath)) {
    throw new Error(`Private key file not found at GH_APP_PRIVATE_KEY_PATH`);
  }
  const privateKeyPem = fs.readFileSync(privateKeyPath, "utf8");

  return {
    appId,
    installationId,
    privateKeyPem,
    bind,
    port,
    internalSecret,
    tokenSkewSec,
    apiBaseUrl,
    requestTimeoutMs,
  };
}

function buildAppJwt(appId, privateKeyPem, nowMs = Date.now()) {
  const nowSec = Math.floor(nowMs / 1000);
  const payload = {
    iat: nowSec - 60,
    exp: nowSec + 9 * 60,
    iss: appId,
  };
  const headerPart = toBase64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payloadPart = toBase64Url(JSON.stringify(payload));
  const unsignedToken = `${headerPart}.${payloadPart}`;
  const signer = crypto.createSign("RSA-SHA256");
  signer.update(unsignedToken);
  signer.end();
  const signature = signer.sign(privateKeyPem);
  return `${unsignedToken}.${toBase64Url(signature)}`;
}

function requestJson({ method, url, headers, timeoutMs }) {
  const parsedUrl = new URL(url);
  const transport = parsedUrl.protocol === "http:" ? http : https;

  return new Promise((resolve, reject) => {
    const req = transport.request(
      parsedUrl,
      {
        method,
        headers,
      },
      (res) => {
        const chunks = [];
        res.on("data", (chunk) => chunks.push(chunk));
        res.on("end", () => {
          const bodyText = Buffer.concat(chunks).toString("utf8");
          let body = null;
          if (bodyText.trim().length > 0) {
            try {
              body = JSON.parse(bodyText);
            } catch (_error) {
              body = null;
            }
          }
          resolve({
            statusCode: res.statusCode || 0,
            body,
          });
        });
      },
    );

    req.setTimeout(timeoutMs, () => {
      req.destroy(new Error("Request timeout"));
    });
    req.on("error", (error) => reject(error));
    req.end();
  });
}

function createGitHubTokenFetcher(config) {
  return async function fetchInstallationToken() {
    const jwt = buildAppJwt(config.appId, config.privateKeyPem);
    const endpoint = new URL(
      `app/installations/${encodeURIComponent(config.installationId)}/access_tokens`,
      config.apiBaseUrl,
    ).toString();

    let response;
    try {
      response = await requestJson({
        method: "POST",
        url: endpoint,
        timeoutMs: config.requestTimeoutMs,
        headers: {
          Authorization: `Bearer ${jwt}`,
          Accept: "application/vnd.github+json",
          "User-Agent": "ai-flow-gh-app-auth-service",
          "X-GitHub-Api-Version": "2022-11-28",
          "Content-Type": "application/json",
          "Content-Length": "0",
        },
      });
    } catch (_error) {
      throw new ServiceError(503, "GITHUB_UNAVAILABLE", "GitHub API is unavailable");
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw new ServiceError(502, "GITHUB_BAD_STATUS", `GitHub API responded with status ${response.statusCode}`);
    }

    const token = response.body && typeof response.body.token === "string" ? response.body.token : "";
    const expiresAt = response.body && typeof response.body.expires_at === "string" ? response.body.expires_at : "";
    const expiresAtMs = Date.parse(expiresAt);

    if (!token || !expiresAt || Number.isNaN(expiresAtMs)) {
      throw new ServiceError(502, "GITHUB_BAD_PAYLOAD", "GitHub API returned invalid token payload");
    }

    return {
      token,
      expiresAt,
      expiresAtMs,
    };
  };
}

function createTokenProvider(config, options = {}) {
  const fetchInstallationToken = options.fetchInstallationToken || createGitHubTokenFetcher(config);
  const now = options.now || (() => Date.now());
  const logger = options.logger || console;
  const skewMs = config.tokenSkewSec * 1000;

  let cachedToken = null;
  let refreshInFlight = null;

  function getCacheState() {
    if (!cachedToken) {
      return {
        hasToken: false,
        expiresAt: null,
      };
    }
    return {
      hasToken: true,
      expiresAt: cachedToken.expiresAt,
    };
  }

  function isCacheFresh(currentMs) {
    if (!cachedToken) {
      return false;
    }
    return currentMs < cachedToken.refreshAfterMs;
  }

  async function refreshToken() {
    if (refreshInFlight) {
      return refreshInFlight;
    }
    refreshInFlight = (async () => {
      const tokenData = await fetchInstallationToken();
      const refreshAfterMs = tokenData.expiresAtMs - skewMs;
      cachedToken = {
        token: tokenData.token,
        expiresAt: tokenData.expiresAt,
        expiresAtMs: tokenData.expiresAtMs,
        refreshAfterMs: Math.max(refreshAfterMs, now()),
      };
      logger.info(
        `[gh-app-auth] token refreshed; expires_at=${cachedToken.expiresAt}; refresh_skew_sec=${config.tokenSkewSec}`,
      );
      return {
        token: cachedToken.token,
        expiresAt: cachedToken.expiresAt,
        source: "refreshed",
      };
    })()
      .finally(() => {
        refreshInFlight = null;
      });

    return refreshInFlight;
  }

  async function getToken() {
    const currentMs = now();
    if (isCacheFresh(currentMs)) {
      return {
        token: cachedToken.token,
        expiresAt: cachedToken.expiresAt,
        source: "cache",
      };
    }
    return refreshToken();
  }

  return {
    getToken,
    getCacheState,
  };
}

function sendJson(res, statusCode, payload) {
  const body = JSON.stringify(payload);
  res.statusCode = statusCode;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Cache-Control", "no-store");
  res.setHeader("Content-Length", Buffer.byteLength(body));
  res.end(body);
}

function extractSingleHeaderValue(header) {
  if (Array.isArray(header)) {
    return header[0] || "";
  }
  return String(header || "");
}

function createServer(config, options = {}) {
  const logger = options.logger || console;
  const tokenProvider = createTokenProvider(config, {
    fetchInstallationToken: options.fetchInstallationToken,
    now: options.now,
    logger,
  });

  const server = http.createServer(async (req, res) => {
    try {
      if (req.method !== "GET") {
        sendJson(res, 405, {
          error: "METHOD_NOT_ALLOWED",
          message: "Only GET method is supported",
        });
        return;
      }

      const url = new URL(req.url || "/", "http://localhost");
      if (url.pathname === "/health") {
        const cacheState = tokenProvider.getCacheState();
        sendJson(res, 200, {
          status: "ok",
          token_cached: cacheState.hasToken,
          token_expires_at: cacheState.expiresAt,
        });
        return;
      }

      if (url.pathname !== "/token") {
        sendJson(res, 404, {
          error: "NOT_FOUND",
          message: "Endpoint not found",
        });
        return;
      }

      const providedSecret = extractSingleHeaderValue(req.headers["x-internal-secret"]);
      if (!safeCompare(providedSecret, config.internalSecret)) {
        sendJson(res, 401, {
          error: "UNAUTHORIZED",
          message: "Invalid internal secret",
        });
        return;
      }

      const token = await tokenProvider.getToken();
      sendJson(res, 200, {
        token: token.token,
        expires_at: token.expiresAt,
        source: token.source,
      });
    } catch (error) {
      if (error instanceof ServiceError) {
        logger.error(`[gh-app-auth] ${error.code}: ${error.message}`);
        sendJson(res, error.httpStatus, {
          error: error.code,
          message: error.message,
        });
        return;
      }

      logger.error(`[gh-app-auth] INTERNAL_ERROR: ${error && error.message ? error.message : "unknown error"}`);
      sendJson(res, 500, {
        error: "INTERNAL_ERROR",
        message: "Unexpected internal error",
      });
    }
  });

  return server;
}

function createLogger() {
  function format(level, message) {
    const nowIso = new Date().toISOString();
    return `${nowIso} ${level} ${message}`;
  }
  return {
    info(message) {
      process.stdout.write(`${format("INFO", message)}\n`);
    },
    error(message) {
      process.stderr.write(`${format("ERROR", message)}\n`);
    },
  };
}

function main() {
  const logger = createLogger();
  let config;
  try {
    config = loadConfig();
  } catch (error) {
    const message = error && error.message ? error.message : "Configuration error";
    logger.error(`[gh-app-auth] CONFIG_ERROR: ${message}`);
    process.exitCode = 1;
    return;
  }

  const server = createServer(config, { logger });
  server.listen(config.port, config.bind, () => {
    const addressInfo = server.address();
    const listenPort = addressInfo && typeof addressInfo === "object" ? addressInfo.port : config.port;
    logger.info(
      `[gh-app-auth] listening on ${config.bind}:${listenPort}; app_id=${config.appId}; installation_id=${config.installationId}`,
    );
  });

  function shutdown(signalName) {
    logger.info(`[gh-app-auth] received ${signalName}, shutting down`);
    server.close(() => {
      process.exit(0);
    });
    setTimeout(() => process.exit(0), 5000).unref();
  }

  process.on("SIGINT", () => shutdown("SIGINT"));
  process.on("SIGTERM", () => shutdown("SIGTERM"));
}

if (require.main === module) {
  main();
}

module.exports = {
  ServiceError,
  buildAppJwt,
  createGitHubTokenFetcher,
  createServer,
  createTokenProvider,
  loadConfig,
  safeCompare,
};
