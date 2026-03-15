#!/usr/bin/env node
"use strict";

const fs = require("fs");
const http = require("http");
const https = require("https");
const path = require("path");
const { execFile } = require("child_process");

const ROOT_DIR = path.resolve(__dirname, "../../..");
const FLOW_ROOT_DIR = path.join(ROOT_DIR, ".flow");
const FLOW_SHARED_SCRIPTS_DIR = path.join(FLOW_ROOT_DIR, "shared", "scripts");
const DEFAULT_CODEX_DIR = path.join(FLOW_ROOT_DIR, "state", "codex", "default");
const DEFAULT_BIND = "127.0.0.1";
const DEFAULT_PORT = 8790;
const DEFAULT_WEBHOOK_PATH = "/telegram/webhook";
const DEFAULT_INGEST_PATH = "/ops/ingest/status";
const DEFAULT_SUMMARY_INGEST_PATH = "/ops/ingest/log-summary";
const DEFAULT_REFRESH_SEC = 5;
const DEFAULT_CMD_TIMEOUT_MS = 10000;
const DEFAULT_SUMMARY_HOURS = 6;
const DEFAULT_REMOTE_SNAPSHOT_TTL_SEC = 600;
const DEFAULT_REMOTE_SUMMARY_TTL_SEC = 1200;
const DEFAULT_DEBUG_DEFAULT_LINES = 120;
const DEFAULT_DEBUG_MAX_LINES = 400;
const DEFAULT_DEBUG_MAX_BYTES = 256 * 1024;
const DEBUG_LOG_NAMES = ["daemon", "watchdog", "executor", "graphql-rate"];

function parseInteger(value, fallback) {
  const parsed = Number.parseInt(String(value ?? fallback), 10);
  return Number.isNaN(parsed) ? fallback : parsed;
}

function parsePort(value, fallback) {
  const port = parseInteger(value, fallback);
  if (!Number.isInteger(port) || port < 0 || port > 65535) {
    throw new Error("OPS_BOT_PORT must be integer 0..65535");
  }
  return port;
}

function parseBoolean(value, fallback = false) {
  if (value === undefined || value === null || String(value).trim() === "") {
    return fallback;
  }
  const normalized = String(value).trim().toLowerCase();
  return ["1", "true", "yes", "on"].includes(normalized);
}

function parsePositiveInteger(value, fallback, { min = 1, max = Number.MAX_SAFE_INTEGER } = {}) {
  const parsed = parseInteger(value, fallback);
  if (!Number.isInteger(parsed) || parsed < min) {
    return fallback;
  }
  return Math.min(parsed, max);
}

function normalizePath(value, fallback) {
  const pathValue = String(value || fallback).trim();
  if (!pathValue.startsWith("/")) {
    throw new Error("OPS_BOT_WEBHOOK_PATH must start with '/'");
  }
  return pathValue.replace(/\/+$/, "") || "/";
}

function splitCsv(value) {
  return String(value || "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

function slugifySegment(value, fallback = "unknown") {
  const normalized = String(value || "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-+|-+$/g, "");
  return normalized || fallback;
}

function htmlEscape(input) {
  return String(input ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/\"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function truncateText(value, maxChars) {
  const text = String(value || "");
  if (text.length <= maxChars) {
    return text;
  }
  return `${text.slice(0, Math.max(0, maxChars - 14))}\n...[truncated]`;
}

function readJsonFile(filePath) {
  try {
    if (!fs.existsSync(filePath)) {
      return null;
    }
    const raw = fs.readFileSync(filePath, "utf8");
    if (!raw.trim()) {
      return null;
    }
    return JSON.parse(raw);
  } catch (_error) {
    return null;
  }
}

function readEnvKey(filePath, key) {
  try {
    if (!fs.existsSync(filePath)) {
      return "";
    }
    const lines = fs.readFileSync(filePath, "utf8").split(/\r?\n/);
    for (const line of lines) {
      if (!line.startsWith(`${key}=`)) {
        continue;
      }
      return line
        .slice(key.length + 1)
        .trim()
        .replace(/^['"]|['"]$/g, "");
    }
  } catch (_error) {
    return "";
  }
  return "";
}

function defaultAiFlowRootDir(env = process.env) {
  const fromEnv = String(env.AI_FLOW_ROOT_DIR || "").trim();
  if (fromEnv) {
    return path.resolve(fromEnv);
  }
  const flowEnvFile = path.join(ROOT_DIR, ".flow", "config", "flow.env");
  const fromFlowEnv = readEnvKey(flowEnvFile, "AI_FLOW_ROOT_DIR");
  if (fromFlowEnv) {
    return path.resolve(fromFlowEnv);
  }
  return ROOT_DIR;
}

function execFileAsync(file, args = [], options = {}) {
  return new Promise((resolve, reject) => {
    execFile(file, args, options, (error, stdout, stderr) => {
      if (error) {
        const err = new Error(error.message || "command failed");
        err.code = error.code;
        err.stdout = stdout;
        err.stderr = stderr;
        reject(err);
        return;
      }
      resolve({ stdout: stdout || "", stderr: stderr || "" });
    });
  });
}

function requestJson({ method, url, timeoutMs, headers, body }) {
  const parsed = new URL(url);
  const transport = parsed.protocol === "http:" ? http : https;

  return new Promise((resolve, reject) => {
    const req = transport.request(
      parsed,
      {
        method,
        timeout: timeoutMs,
        headers,
      },
      (res) => {
        const chunks = [];
        res.on("data", (chunk) => chunks.push(chunk));
        res.on("end", () => {
          const bodyText = Buffer.concat(chunks).toString("utf8");
          let payload = null;
          if (bodyText.trim()) {
            try {
              payload = JSON.parse(bodyText);
            } catch (_error) {
              payload = null;
            }
          }
          resolve({
            statusCode: res.statusCode || 0,
            payload,
            raw: bodyText,
          });
        });
      },
    );

    req.on("error", (error) => reject(error));
    req.on("timeout", () => req.destroy(new Error("request timeout")));

    if (body && body.length > 0) {
      req.write(body);
    }
    req.end();
  });
}

function sendJson(res, statusCode, payload) {
  const body = JSON.stringify(payload);
  res.statusCode = statusCode;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Cache-Control", "no-store");
  res.setHeader("Content-Length", Buffer.byteLength(body));
  res.end(body);
}

function sendHtml(res, statusCode, html) {
  const body = String(html || "");
  res.statusCode = statusCode;
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.setHeader("Cache-Control", "no-store");
  res.setHeader("Content-Length", Buffer.byteLength(body));
  res.end(body);
}

function sendText(res, statusCode, text) {
  const body = String(text || "");
  res.statusCode = statusCode;
  res.setHeader("Content-Type", "text/plain; charset=utf-8");
  res.setHeader("Cache-Control", "no-store");
  res.setHeader("Content-Length", Buffer.byteLength(body));
  res.end(body);
}

function extractHeader(req, key) {
  const value = req.headers[key.toLowerCase()];
  if (Array.isArray(value)) {
    return value[0] || "";
  }
  return String(value || "");
}

function collectRequestBody(req, maxBytes = 1024 * 1024) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let total = 0;
    let overflow = false;
    req.on("data", (chunk) => {
      if (overflow) {
        return;
      }
      total += chunk.length;
      if (total > maxBytes) {
        overflow = true;
        reject(new Error("request body too large"));
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => {
      resolve(Buffer.concat(chunks).toString("utf8"));
    });
    req.on("error", (error) => reject(error));
  });
}

function createLogger() {
  const entries = [];
  const MAX_ENTRIES = 400;

  function line(level, message) {
    const stamp = new Date().toISOString();
    return `${stamp} ${level} ${message}`;
  }

  function push(level, message) {
    entries.push(line(level, message));
    if (entries.length > MAX_ENTRIES) {
      entries.splice(0, entries.length - MAX_ENTRIES);
    }
  }

  return {
    info(message) {
      push("INFO", message);
      process.stdout.write(`${line("INFO", message)}\n`);
    },
    warn(message) {
      push("WARN", message);
      process.stdout.write(`${line("WARN", message)}\n`);
    },
    error(message) {
      push("ERROR", message);
      process.stderr.write(`${line("ERROR", message)}\n`);
    },
    tail(limit = DEFAULT_DEBUG_DEFAULT_LINES) {
      const safeLimit = Math.max(1, Math.min(MAX_ENTRIES, parsePositiveInteger(limit, DEFAULT_DEBUG_DEFAULT_LINES)));
      return entries.slice(-safeLimit);
    },
  };
}

function loadConfig(env = process.env) {
  const bind = String(env.OPS_BOT_BIND || DEFAULT_BIND).trim() || DEFAULT_BIND;
  const port = parsePort(env.OPS_BOT_PORT, DEFAULT_PORT);
  const webhookPathBase = normalizePath(env.OPS_BOT_WEBHOOK_PATH, DEFAULT_WEBHOOK_PATH);
  const ingestPath = normalizePath(env.OPS_BOT_INGEST_PATH, DEFAULT_INGEST_PATH);
  const summaryIngestPath = normalizePath(env.OPS_BOT_SUMMARY_INGEST_PATH, DEFAULT_SUMMARY_INGEST_PATH);
  const webhookSecret = String(env.OPS_BOT_WEBHOOK_SECRET || "").trim();
  const telegramSecretToken = String(env.OPS_BOT_TG_SECRET_TOKEN || "").trim();
  const ingestSecret = String(env.OPS_BOT_INGEST_SECRET || "").trim();
  const summaryIngestSecret = String(env.OPS_BOT_SUMMARY_INGEST_SECRET || ingestSecret).trim();
  const ingestEnabled = parseBoolean(env.OPS_BOT_INGEST_ENABLED, false);
  const allowedChatIds = new Set(splitCsv(env.OPS_BOT_ALLOWED_CHAT_IDS));
  const debugBearerToken = String(env.OPS_BOT_DEBUG_BEARER_TOKEN || "").trim();
  const debugEnabled = parseBoolean(env.OPS_BOT_DEBUG_ENABLED, debugBearerToken.length > 0);
  const debugDefaultLines = parsePositiveInteger(env.OPS_BOT_DEBUG_DEFAULT_LINES, DEFAULT_DEBUG_DEFAULT_LINES, {
    min: 10,
    max: DEFAULT_DEBUG_MAX_LINES,
  });
  const debugMaxLines = parsePositiveInteger(env.OPS_BOT_DEBUG_MAX_LINES, DEFAULT_DEBUG_MAX_LINES, {
    min: debugDefaultLines,
    max: 2000,
  });
  const debugMaxBytes = parsePositiveInteger(env.OPS_BOT_DEBUG_MAX_BYTES, DEFAULT_DEBUG_MAX_BYTES, {
    min: 16 * 1024,
    max: 2 * 1024 * 1024,
  });

  const snapshotScript = path.resolve(
    env.OPS_BOT_STATUS_SNAPSHOT_SCRIPT || path.join(FLOW_SHARED_SCRIPTS_DIR, "status_snapshot.sh"),
  );
  const logSummaryScript = path.resolve(
    env.OPS_BOT_LOG_SUMMARY_SCRIPT || path.join(FLOW_SHARED_SCRIPTS_DIR, "log_summary.sh"),
  );
  const envAuditScript = path.resolve(
    env.OPS_BOT_ENV_AUDIT_SCRIPT || path.join(FLOW_SHARED_SCRIPTS_DIR, "env_audit.sh"),
  );

  const refreshSec = Math.max(2, parseInteger(env.OPS_BOT_REFRESH_SEC, DEFAULT_REFRESH_SEC));
  const cmdTimeoutMs = Math.max(2000, parseInteger(env.OPS_BOT_CMD_TIMEOUT_MS, DEFAULT_CMD_TIMEOUT_MS));

  const tgBotToken = String(env.OPS_BOT_TG_BOT_TOKEN || env.DAEMON_TG_BOT_TOKEN || env.TG_BOT_TOKEN || "").trim();
  const publicBaseUrl = String(env.OPS_BOT_PUBLIC_BASE_URL || "").trim();
  const flowEnvFile = path.join(ROOT_DIR, ".flow", "config", "flow.env");
  const projectProfile = String(env.PROJECT_PROFILE || readEnvKey(flowEnvFile, "PROJECT_PROFILE") || "").trim();
  const aiFlowRootDir = defaultAiFlowRootDir(env);
  const profileConfigDir = path.join(ROOT_DIR, ".flow", "config", "profiles");
  const localStateRootDir = path.join(ROOT_DIR, ".flow", "state", "codex");
  const codexStateDir = path.resolve(env.CODEX_STATE_DIR || env.FLOW_STATE_DIR || DEFAULT_CODEX_DIR);
  const runtimeLogDir = path.resolve(
    env.FLOW_RUNTIME_LOG_DIR || readEnvKey(flowEnvFile, "FLOW_RUNTIME_LOG_DIR") || path.join(ROOT_DIR, ".flow", "logs", "runtime"),
  );
  const pm2LogDir = path.resolve(
    env.FLOW_PM2_LOG_DIR || readEnvKey(flowEnvFile, "FLOW_PM2_LOG_DIR") || path.join(path.dirname(runtimeLogDir), "pm2"),
  );
  const remoteStateDir = path.resolve(
    env.OPS_BOT_REMOTE_STATE_DIR || path.join(aiFlowRootDir, "state", "ops-bot", "remote"),
  );
  const remoteSnapshotFile = path.resolve(
    env.OPS_BOT_REMOTE_SNAPSHOT_FILE || path.join(remoteStateDir, "_legacy", "snapshot.json"),
  );
  const remoteSnapshotTtlSec = Math.max(
    1,
    parseInteger(env.OPS_BOT_REMOTE_SNAPSHOT_TTL_SEC, DEFAULT_REMOTE_SNAPSHOT_TTL_SEC),
  );
  const remoteSummaryFile = path.resolve(
    env.OPS_BOT_REMOTE_SUMMARY_FILE || path.join(remoteStateDir, "_legacy", "summary.json"),
  );
  const remoteSummaryTtlSec = Math.max(
    1,
    parseInteger(env.OPS_BOT_REMOTE_SUMMARY_TTL_SEC, DEFAULT_REMOTE_SUMMARY_TTL_SEC),
  );

  const webhookPath = webhookSecret
    ? `${webhookPathBase}/${encodeURIComponent(webhookSecret)}`
    : webhookPathBase;

  if (!fs.existsSync(snapshotScript)) {
    throw new Error(`status snapshot script not found: ${snapshotScript}`);
  }
  if (!fs.existsSync(logSummaryScript)) {
    throw new Error(`log summary script not found: ${logSummaryScript}`);
  }

  return {
    bind,
    port,
    webhookPath,
    webhookPathBase,
    ingestPath,
    summaryIngestPath,
    webhookSecret,
    telegramSecretToken,
    ingestSecret,
    summaryIngestSecret,
    ingestEnabled,
    allowedChatIds,
    snapshotScript,
    logSummaryScript,
    envAuditScript,
    refreshSec,
    cmdTimeoutMs,
    tgBotToken,
    publicBaseUrl,
    projectProfile,
    aiFlowRootDir,
    flowEnvFile,
    profileConfigDir,
    localStateRootDir,
    codexStateDir,
    runtimeLogDir,
    pm2LogDir,
    remoteStateDir,
    remoteSnapshotFile,
    remoteSnapshotTtlSec,
    remoteSummaryFile,
    remoteSummaryTtlSec,
    debugEnabled,
    debugBearerToken,
    debugDefaultLines,
    debugMaxLines,
    debugMaxBytes,
    envAuditCache: {
      promise: null,
      value: null,
      loadedAtMs: 0,
    },
  };
}

function buildDebugLogMap(config) {
  return {
    daemon: path.join(config.runtimeLogDir, "daemon.log"),
    watchdog: path.join(config.runtimeLogDir, "watchdog.log"),
    executor: path.join(config.runtimeLogDir, "executor.log"),
    "graphql-rate": path.join(config.runtimeLogDir, "graphql_rate_stats.log"),
  };
}

function buildSecretRedactions(config) {
  const envSecretKeys = [
    "OPS_BOT_DEBUG_BEARER_TOKEN",
    "OPS_BOT_INGEST_SECRET",
    "OPS_BOT_SUMMARY_INGEST_SECRET",
    "OPS_BOT_TG_SECRET_TOKEN",
    "OPS_BOT_WEBHOOK_SECRET",
    "OPS_REMOTE_STATUS_PUSH_SECRET",
    "OPS_REMOTE_SUMMARY_PUSH_SECRET",
    "TG_BOT_TOKEN",
    "OPS_BOT_TG_BOT_TOKEN",
    "DAEMON_TG_BOT_TOKEN",
    "DAEMON_GH_PROJECT_TOKEN",
    "DAEMON_GH_TOKEN",
    "CODEX_GH_PROJECT_TOKEN",
    "CODEX_GH_TOKEN",
    "GH_APP_INTERNAL_SECRET",
    "OPENAI_API_KEY",
  ];
  const replacements = new Map();
  const candidates = [
    ["OPS_BOT_DEBUG_BEARER_TOKEN", config.debugBearerToken],
    ["OPS_BOT_INGEST_SECRET", config.ingestSecret],
    ["OPS_BOT_SUMMARY_INGEST_SECRET", config.summaryIngestSecret],
    ["OPS_BOT_TG_SECRET_TOKEN", config.telegramSecretToken],
    ["OPS_BOT_WEBHOOK_SECRET", config.webhookSecret],
    ["OPS_BOT_TG_BOT_TOKEN", config.tgBotToken],
  ];
  for (const key of envSecretKeys) {
    candidates.push([key, process.env[key] || ""]);
  }
  for (const [key, value] of candidates) {
    const normalized = String(value || "").trim();
    if (normalized.length < 6) {
      continue;
    }
    if (!replacements.has(normalized)) {
      replacements.set(normalized, `<redacted:${key}>`);
    }
  }
  return Array.from(replacements.entries());
}

function redactSensitiveText(input, config) {
  let text = String(input || "");
  for (const [rawValue, replacement] of buildSecretRedactions(config)) {
    text = text.split(rawValue).join(replacement);
  }
  text = text.replace(/\bBearer\s+[A-Za-z0-9._~+/=-]{12,}\b/g, "Bearer <redacted:bearer>");
  text = text.replace(/\b(sk-[A-Za-z0-9_-]{12,})\b/g, "<redacted:openai-key>");
  return text;
}

function readTailText(filePath, maxBytes) {
  const stats = fs.statSync(filePath);
  const safeBytes = Math.max(4096, maxBytes);
  const start = Math.max(0, stats.size - safeBytes);
  const length = stats.size - start;
  const fd = fs.openSync(filePath, "r");
  try {
    const buffer = Buffer.alloc(length);
    fs.readSync(fd, buffer, 0, length, start);
    return {
      text: buffer.toString("utf8"),
      truncated: start > 0,
      fileSize: stats.size,
    };
  } finally {
    fs.closeSync(fd);
  }
}

function extractTailLines(text, lines, truncatedByBytes) {
  const normalized = String(text || "").replace(/\r\n/g, "\n");
  const allLines = normalized.split("\n");
  if (allLines.length > 0 && allLines[allLines.length - 1] === "") {
    allLines.pop();
  }
  const safeLines = Math.max(1, lines);
  const tailLines = allLines.slice(-safeLines);
  return {
    text: tailLines.join("\n"),
    lineCount: tailLines.length,
    truncated: truncatedByBytes || allLines.length > safeLines,
  };
}

function loadDebugLogTail(config, logName, requestedLines) {
  const logMap = buildDebugLogMap(config);
  if (!Object.prototype.hasOwnProperty.call(logMap, logName)) {
    const error = new Error(`unknown debug log: ${logName}`);
    error.code = "UNKNOWN_LOG";
    throw error;
  }
  const filePath = logMap[logName];
  const safeLines = Math.max(1, Math.min(config.debugMaxLines, requestedLines || config.debugDefaultLines));
  if (!fs.existsSync(filePath)) {
    return {
      name: logName,
      path: filePath,
      exists: false,
      lines_requested: safeLines,
      lines_returned: 0,
      truncated: false,
      text: "",
    };
  }
  const tailChunk = readTailText(filePath, config.debugMaxBytes);
  const tailLines = extractTailLines(tailChunk.text, safeLines, tailChunk.truncated);
  return {
    name: logName,
    path: filePath,
    exists: true,
    lines_requested: safeLines,
    lines_returned: tailLines.lineCount,
    truncated: tailLines.truncated,
    file_size_bytes: tailChunk.fileSize,
    text: redactSensitiveText(tailLines.text, config),
  };
}

function requireDebugAuth(req, res, config) {
  if (!config.debugEnabled || !config.debugBearerToken) {
    sendJson(res, 404, { error: "NOT_FOUND", message: "debug surface disabled" });
    return false;
  }
  const headerValue = extractHeader(req, "authorization");
  const expected = `Bearer ${config.debugBearerToken}`;
  if (headerValue !== expected) {
    res.setHeader("WWW-Authenticate", 'Bearer realm="ops-debug"');
    sendJson(res, 401, { error: "UNAUTHORIZED", message: "invalid debug bearer token" });
    return false;
  }
  return true;
}

async function buildDebugRuntimePayload(config) {
  const snapshot = await loadEffectiveSnapshot(config);
  const envAudit = await loadEffectiveEnvAudit(config);
  return {
    generated_at: new Date().toISOString(),
    debug_surface: "ops-bot",
    snapshot,
    env_audit: envAudit,
    log_summary_hint: "/ops/debug/log-summary.json?hours=6",
    available_logs: DEBUG_LOG_NAMES,
    paths: {
      root_dir: ROOT_DIR,
      ai_flow_root_dir: config.aiFlowRootDir,
      runtime_log_dir: config.runtimeLogDir,
      codex_state_dir: config.codexStateDir,
      remote_state_dir: config.remoteStateDir,
    },
  };
}

function parseEnvAuditOutput(output) {
  const text = String(output || "").replace(/\r\n/g, "\n");
  const lines = text.split("\n").filter(Boolean);
  const result = {
    ready: false,
    status: "unknown",
    summary: "",
    ok: 0,
    warn: 0,
    fail: 0,
    action: 0,
    warnings: [],
    failures: [],
    actions: [],
    output: text.trim(),
  };
  for (const line of lines) {
    let match = /^⚠️ CHECK_WARN ([A-Z0-9_]+)=(.*)$/.exec(line);
    if (match) {
      result.warnings.push({ key: match[1], value: match[2] });
      continue;
    }
    match = /^❌ CHECK_FAIL ([A-Z0-9_]+)=(.*)$/.exec(line);
    if (match) {
      result.failures.push({ key: match[1], value: match[2] });
      continue;
    }
    match = /^👉 ACTION ([A-Z0-9_]+)=(.*)$/.exec(line);
    if (match) {
      result.actions.push({ key: match[1], value: match[2] });
      continue;
    }
    match = /^SUMMARY ok=(\d+) warn=(\d+) fail=(\d+) action=(\d+)$/.exec(line);
    if (match) {
      result.ok = Number.parseInt(match[1], 10) || 0;
      result.warn = Number.parseInt(match[2], 10) || 0;
      result.fail = Number.parseInt(match[3], 10) || 0;
      result.action = Number.parseInt(match[4], 10) || 0;
      result.summary = line;
      continue;
    }
    match = /^ENV_AUDIT_READY=(\d+)$/.exec(line);
    if (match) {
      result.ready = match[1] === "1";
    }
  }
  if (result.fail > 0) {
    result.status = "fail";
  } else if (result.warn > 0) {
    result.status = "warn";
  } else if (result.ready) {
    result.status = "ok";
  } else {
    result.status = "not_ready";
  }
  return result;
}

async function loadEnvAudit(config) {
  const auditArgs = ["--profile", config.projectProfile];
  const legacyProjectEnvFile = String(process.env.DAEMON_GH_LEGACY_ENV_FILE || process.env.HOST_ENV_FILE || "").trim();
  const legacyPlatformEnvFile = String(
    process.env.AI_FLOW_PLATFORM_LEGACY_ENV_FILE || process.env.PLATFORM_ENV_FILE || "",
  ).trim();

  if (legacyProjectEnvFile) {
    auditArgs.push("--project-env-file", legacyProjectEnvFile);
  }
  if (legacyPlatformEnvFile) {
    auditArgs.push("--platform-env-file", legacyPlatformEnvFile);
  }

  if (!config.projectProfile) {
    return {
      ready: false,
      status: "skipped",
      summary: "project profile is not configured",
      ok: 0,
      warn: 0,
      fail: 0,
      action: 0,
      warnings: [],
      failures: [],
      actions: [],
      profile: "",
    };
  }
  if (!fs.existsSync(config.envAuditScript)) {
    return {
      ready: false,
      status: "missing_script",
      summary: `env audit script not found: ${config.envAuditScript}`,
      ok: 0,
      warn: 0,
      fail: 1,
      action: 0,
      warnings: [],
      failures: [{ key: "ENV_AUDIT_SCRIPT", value: config.envAuditScript }],
      actions: [],
      profile: config.projectProfile,
    };
  }
  try {
    const { stdout, stderr } = await execFileAsync(config.envAuditScript, auditArgs, {
      cwd: ROOT_DIR,
      timeout: Math.max(config.cmdTimeoutMs, 15000),
      maxBuffer: 1024 * 1024,
      env: {
        ...process.env,
        PROJECT_PROFILE: config.projectProfile,
      },
    });
    const parsed = parseEnvAuditOutput(`${stdout}${stderr ? `\n${stderr}` : ""}`);
    return {
      ...parsed,
      profile: config.projectProfile,
    };
  } catch (error) {
    return {
      ready: false,
      status: "error",
      summary: error && error.message ? error.message : "env audit failed",
      ok: 0,
      warn: 0,
      fail: 1,
      action: 0,
      warnings: [],
      failures: [{ key: "ENV_AUDIT_ERROR", value: error && error.message ? error.message : "unknown error" }],
      actions: [],
      profile: config.projectProfile,
      output: [error && error.stdout ? error.stdout : "", error && error.stderr ? error.stderr : ""]
        .filter(Boolean)
        .join("\n")
        .trim(),
    };
  }
}

async function loadEffectiveEnvAudit(config) {
  const refreshMs = Math.max(2000, config.refreshSec * 1000);
  const cache = config.envAuditCache || {
    promise: null,
    value: null,
    loadedAtMs: 0,
  };
  if (cache.value && Date.now() - cache.loadedAtMs < refreshMs) {
    return cache.value;
  }
  if (!cache.promise) {
    cache.promise = loadEnvAudit(config)
      .then((value) => {
        cache.value = value;
        cache.loadedAtMs = Date.now();
        return value;
      })
      .finally(() => {
        cache.promise = null;
      });
  }
  return cache.promise;
}

async function loadSnapshot(config) {
  return loadSnapshotForEnv(config, {});
}

async function loadSnapshotForEnv(config, envOverrides) {
  try {
    const { stdout } = await execFileAsync(config.snapshotScript, [], {
      cwd: ROOT_DIR,
      env: {
        ...process.env,
        ...envOverrides,
      },
      timeout: config.cmdTimeoutMs,
      maxBuffer: 1024 * 1024,
    });
    const parsed = JSON.parse(stdout);
    return parsed;
  } catch (error) {
    return {
      generated_at: new Date().toISOString(),
      overall_status: "ERROR",
      headline: "Failed to load status snapshot",
      action_required: "inspect_snapshot_script",
      snapshot_error: {
        message: error && error.message ? error.message : "unknown error",
        stdout: error && error.stdout ? truncateText(error.stdout, 800) : "",
        stderr: error && error.stderr ? truncateText(error.stderr, 800) : "",
      },
    };
  }
}

function resolveProfileStateDir(config, envFile, profileName) {
  const fromCodex = readEnvKey(envFile, "CODEX_STATE_DIR");
  if (fromCodex) {
    return path.resolve(ROOT_DIR, fromCodex);
  }
  const fromFlow = readEnvKey(envFile, "FLOW_STATE_DIR");
  if (fromFlow) {
    return path.resolve(ROOT_DIR, fromFlow);
  }
  return path.join(config.localStateRootDir, profileName);
}

async function loadSummary(config, hours) {
  const safeHours = Number.isInteger(hours) && hours > 0 && hours <= 168 ? hours : DEFAULT_SUMMARY_HOURS;
  const { stdout, stderr } = await execFileAsync(config.logSummaryScript, ["--hours", String(safeHours)], {
    cwd: ROOT_DIR,
    timeout: Math.max(config.cmdTimeoutMs, 25000),
    maxBuffer: 1024 * 1024,
  });
  return {
    hours: safeHours,
    text: `${stdout}${stderr ? `\n${stderr}` : ""}`.trim(),
  };
}

function remoteSourceDir(config, source) {
  return path.join(config.remoteStateDir, slugifySegment(source));
}

function remoteSnapshotPath(config, source) {
  return path.join(remoteSourceDir(config, source), "snapshot.json");
}

function remoteSummaryPath(config, source) {
  return path.join(remoteSourceDir(config, source), "summary.json");
}

function listRemoteRecords(config, fileName, shapeKey) {
  const records = [];
  if (fs.existsSync(config.remoteStateDir)) {
    for (const entry of fs.readdirSync(config.remoteStateDir, { withFileTypes: true })) {
      if (!entry.isDirectory()) {
        continue;
      }
      const parsed = readJsonFile(path.join(config.remoteStateDir, entry.name, fileName));
      if (isObjectLike(parsed) && isObjectLike(parsed[shapeKey])) {
        records.push(parsed);
      }
    }
  }
  return records.sort((left, right) => {
    const leftMs = Date.parse(String(left.received_at || left.pushed_at || "")) || 0;
    const rightMs = Date.parse(String(right.received_at || right.pushed_at || "")) || 0;
    return rightMs - leftMs;
  });
}

function loadRemoteSummaries(config) {
  const records = listRemoteRecords(config, "summary.json", "summaries");
  const legacy = readJsonFile(config.remoteSummaryFile);
  if (isObjectLike(legacy) && isObjectLike(legacy.summaries)) {
    records.push(legacy);
  }
  return dedupeRemoteRecords(records).sort((left, right) => {
    const leftMs = Date.parse(String(left.received_at || left.pushed_at || "")) || 0;
    const rightMs = Date.parse(String(right.received_at || right.pushed_at || "")) || 0;
    return rightMs - leftMs;
  });
}

function writeRemoteSummary(config, payload) {
  const dirPath = remoteSourceDir(config, payload.source || "unknown");
  fs.mkdirSync(dirPath, { recursive: true });
  const filePath = remoteSummaryPath(config, payload.source || "unknown");
  const tempPath = `${filePath}.${process.pid}.${Date.now()}.tmp`;
  fs.writeFileSync(tempPath, `${JSON.stringify(payload)}\n`, "utf8");
  fs.renameSync(tempPath, filePath);
  if (config.remoteSummaryFile) {
    const legacyDir = path.dirname(config.remoteSummaryFile);
    fs.mkdirSync(legacyDir, { recursive: true });
    const legacyTempPath = `${config.remoteSummaryFile}.${process.pid}.${Date.now()}.tmp`;
    fs.writeFileSync(legacyTempPath, `${JSON.stringify(payload)}\n`, "utf8");
    fs.renameSync(legacyTempPath, config.remoteSummaryFile);
  }
}

function pickSummaryEntry(summaries, requestedHours) {
  if (!isObjectLike(summaries)) {
    return null;
  }
  const exactKey = String(requestedHours);
  if (typeof summaries[exactKey] === "string") {
    return { hours: requestedHours, text: summaries[exactKey], exact: true };
  }
  const candidates = Object.keys(summaries)
    .map((key) => Number.parseInt(key, 10))
    .filter((value) => Number.isInteger(value) && value > 0 && value <= 168)
    .sort((a, b) => {
      const da = Math.abs(a - requestedHours);
      const db = Math.abs(b - requestedHours);
      if (da !== db) {
        return da - db;
      }
      return a - b;
    });
  if (candidates.length === 0) {
    return null;
  }
  const picked = candidates[0];
  const pickedKey = String(picked);
  const text = typeof summaries[pickedKey] === "string" ? summaries[pickedKey] : "";
  return { hours: picked, text, exact: picked === requestedHours };
}

function collectRemoteSummarySources(config) {
  return loadRemoteSummaries(config).map((record) => {
    const receivedAtMs = Date.parse(String(record.received_at || ""));
    const ageSec = Number.isFinite(receivedAtMs)
      ? Math.max(0, Math.floor((Date.now() - receivedAtMs) / 1000))
      : Number.POSITIVE_INFINITY;
    return {
      source: String(record.source || "unknown"),
      profile: String(record.profile || ""),
      repo: String(record.repo || ""),
      label: String(record.label || record.repo || record.source || "unknown"),
      received_at: String(record.received_at || ""),
      pushed_at: String(record.pushed_at || ""),
      generated_at: String(record.generated_at || ""),
      age_sec: ageSec,
      stale: !(ageSec <= config.remoteSummaryTtlSec),
      windows: Object.keys(record.summaries || {})
        .map((key) => Number.parseInt(key, 10))
        .filter((value) => Number.isInteger(value) && value > 0)
        .sort((a, b) => a - b),
    };
  });
}

async function loadEffectiveSummary(config, hours) {
  const safeHours = Number.isInteger(hours) && hours > 0 && hours <= 168 ? hours : DEFAULT_SUMMARY_HOURS;
  const remoteSources = collectRemoteSummarySources(config);
  for (const remote of loadRemoteSummaries(config)) {
    const picked = pickSummaryEntry(remote.summaries, safeHours);
    if (picked && picked.text.trim()) {
      const receivedAtMs = Date.parse(String(remote.received_at || ""));
      const ageSec = Number.isFinite(receivedAtMs)
        ? Math.max(0, Math.floor((Date.now() - receivedAtMs) / 1000))
        : Number.POSITIVE_INFINITY;
      const stale = !(ageSec <= config.remoteSummaryTtlSec);
      return {
        hours: safeHours,
        text: picked.text,
        usedHours: picked.hours,
        source: "remote_ingest",
        remoteSource: String(remote.source || "unknown"),
        remoteProfile: String(remote.profile || ""),
        remoteRepo: String(remote.repo || ""),
        remoteLabel: String(remote.label || remote.repo || remote.source || "unknown"),
        remoteReceivedAt: String(remote.received_at || ""),
        remoteAgeSec: ageSec,
        remoteStale: stale,
        exactWindow: picked.exact,
        remoteSources,
      };
    }
  }

  const localSummary = await loadSummary(config, safeHours);
  return {
    ...localSummary,
    usedHours: localSummary.hours,
    source: "local",
    remoteSource: "",
    remoteProfile: "",
    remoteRepo: "",
    remoteLabel: "",
    remoteReceivedAt: "",
    remoteAgeSec: 0,
    remoteStale: false,
    exactWindow: true,
    remoteSources,
  };
}

function loadRemoteSnapshots(config) {
  const records = listRemoteRecords(config, "snapshot.json", "snapshot");
  const legacy = readJsonFile(config.remoteSnapshotFile);
  if (isObjectLike(legacy) && isObjectLike(legacy.snapshot)) {
    records.push(legacy);
  }
  return dedupeRemoteRecords(records).sort((left, right) => {
    const leftMs = Date.parse(String(left.received_at || left.pushed_at || "")) || 0;
    const rightMs = Date.parse(String(right.received_at || right.pushed_at || "")) || 0;
    return rightMs - leftMs;
  });
}

function dedupeRemoteRecords(records) {
  const seen = new Set();
  const result = [];
  for (const record of records) {
    const snapshot = isObjectLike(record.snapshot) ? record.snapshot : {};
    const project = isObjectLike(snapshot.project) ? snapshot.project : {};
    const key = [
      String(record.source || ""),
      String(record.profile || project.profile || ""),
      String(record.repo || project.repo || ""),
      String(record.received_at || ""),
      String(record.pushed_at || ""),
      String(snapshot.generated_at || record.generated_at || ""),
    ].join("|");
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    result.push(record);
  }
  return result;
}

function writeRemoteSnapshot(config, payload) {
  const dirPath = remoteSourceDir(config, payload.source || "unknown");
  fs.mkdirSync(dirPath, { recursive: true });
  const filePath = remoteSnapshotPath(config, payload.source || "unknown");
  const tempPath = `${filePath}.${process.pid}.${Date.now()}.tmp`;
  fs.writeFileSync(tempPath, `${JSON.stringify(payload)}\n`, "utf8");
  fs.renameSync(tempPath, filePath);
  if (config.remoteSnapshotFile) {
    const legacyDir = path.dirname(config.remoteSnapshotFile);
    fs.mkdirSync(legacyDir, { recursive: true });
    const legacyTempPath = `${config.remoteSnapshotFile}.${process.pid}.${Date.now()}.tmp`;
    fs.writeFileSync(legacyTempPath, `${JSON.stringify(payload)}\n`, "utf8");
    fs.renameSync(legacyTempPath, config.remoteSnapshotFile);
  }
}

function hasLocalRuntimeSignal(snapshot) {
  const daemonState = String(snapshot && snapshot.daemon && snapshot.daemon.state ? snapshot.daemon.state : "")
    .trim()
    .toUpperCase();
  const watchdogState = String(snapshot && snapshot.watchdog && snapshot.watchdog.state ? snapshot.watchdog.state : "")
    .trim()
    .toUpperCase();
  const executorState = String(snapshot && snapshot.executor && snapshot.executor.state ? snapshot.executor.state : "")
    .trim()
    .toUpperCase();

  if (daemonState && daemonState !== "UNKNOWN") {
    return true;
  }
  if (watchdogState && watchdogState !== "UNKNOWN") {
    return true;
  }
  if (executorState && executorState !== "UNKNOWN") {
    return true;
  }
  return false;
}

function collectRemoteSnapshotSources(config) {
  return loadRemoteSnapshots(config).map((record) => {
    const receivedAtMs = Date.parse(String(record.received_at || ""));
    const ageSec = Number.isFinite(receivedAtMs)
      ? Math.max(0, Math.floor((Date.now() - receivedAtMs) / 1000))
      : Number.POSITIVE_INFINITY;
    const snapshot = isObjectLike(record.snapshot) ? record.snapshot : {};
    const project = isObjectLike(snapshot.project) ? snapshot.project : {};
    return {
      source: String(record.source || "unknown"),
      profile: String(record.profile || project.profile || ""),
      repo: String(record.repo || project.repo || ""),
      label: String(record.label || project.label || record.repo || record.source || "unknown"),
      received_at: String(record.received_at || ""),
      pushed_at: String(record.pushed_at || ""),
      generated_at: String(snapshot.generated_at || ""),
      age_sec: ageSec,
      stale: !(ageSec <= config.remoteSnapshotTtlSec),
      overall_status: String(snapshot.overall_status || "UNKNOWN"),
      headline: String(snapshot.headline || ""),
    };
  });
}

async function loadEffectiveSnapshot(config) {
  const localSnapshot = await loadSnapshot(config);
  const remoteSources = collectRemoteSnapshotSources(config);
  const remotes = loadRemoteSnapshots(config);
  const remote = remotes.length > 0 ? remotes[0] : null;
  if (!remote) {
    return {
      ...localSnapshot,
      remote_sources: remoteSources,
    };
  }

  const localHasSignal = hasLocalRuntimeSignal(localSnapshot);
  const receivedAtMs = Date.parse(String(remote.received_at || ""));
  const ageSec = Number.isFinite(receivedAtMs)
    ? Math.max(0, Math.floor((Date.now() - receivedAtMs) / 1000))
    : Number.POSITIVE_INFINITY;
  const remoteFresh = ageSec <= config.remoteSnapshotTtlSec;

  if (!localHasSignal) {
    const remoteSnapshot = { ...remote.snapshot };
    remoteSnapshot.snapshot_source = "remote_ingest";
    remoteSnapshot.remote_source = String(remote.source || "unknown");
    remoteSnapshot.remote_profile = String(remote.profile || remoteSnapshot?.project?.profile || "");
    remoteSnapshot.remote_repo = String(remote.repo || remoteSnapshot?.project?.repo || "");
    remoteSnapshot.remote_label = String(
      remote.label || remoteSnapshot?.project?.label || remote.repo || remote.source || "unknown",
    );
    remoteSnapshot.remote_received_at = String(remote.received_at || "");
    remoteSnapshot.remote_age_sec = ageSec;
    remoteSnapshot.remote_stale = !remoteFresh;
    remoteSnapshot.remote_sources = remoteSources;
    if (!remoteFresh) {
      const staleAgeText = Number.isFinite(ageSec) ? `${ageSec}s` : "unknown";
      const baseHeadline = String(remoteSnapshot.headline || "Remote snapshot");
      if (!/\[stale /i.test(baseHeadline)) {
        remoteSnapshot.headline = `${baseHeadline} [stale ${staleAgeText}]`;
      }
      const action = String(remoteSnapshot.action_required || "").trim().toLowerCase();
      if (!action || action === "none") {
        remoteSnapshot.action_required = "check_remote_status_push";
      }
      const status = String(remoteSnapshot.overall_status || "").trim().toUpperCase();
      if (!status || status === "HEALTHY") {
        remoteSnapshot.overall_status = "WAITING_SYSTEM";
      }
    }
    return remoteSnapshot;
  }

  return {
    ...localSnapshot,
    remote_sources: remoteSources,
  };
}

async function loadLocalProjectSnapshots(config) {
  const envFiles = [];
  const seen = new Set();

  if (fs.existsSync(config.flowEnvFile)) {
    envFiles.push(config.flowEnvFile);
    seen.add(path.resolve(config.flowEnvFile));
  }

  if (fs.existsSync(config.profileConfigDir)) {
    for (const entry of fs.readdirSync(config.profileConfigDir, { withFileTypes: true })) {
      if (!entry.isFile() || !entry.name.endsWith(".env")) {
        continue;
      }
      const envFile = path.join(config.profileConfigDir, entry.name);
      const resolvedPath = path.resolve(envFile);
      if (seen.has(resolvedPath)) {
        continue;
      }
      seen.add(resolvedPath);
      envFiles.push(envFile);
    }
  }

  if (envFiles.length === 0) {
    return [];
  }
  envFiles.sort((left, right) => left.localeCompare(right));

  const snapshots = [];
  for (const envFile of envFiles) {
    const profileName = path.basename(envFile, ".env");
    const stateDir = resolveProfileStateDir(config, envFile, profileName);
    const snapshot = await loadSnapshotForEnv(config, {
      DAEMON_GH_ENV_FILE: envFile,
      CODEX_STATE_DIR: stateDir,
      FLOW_STATE_DIR: stateDir,
    });
    snapshot.project = isObjectLike(snapshot.project) ? snapshot.project : {};
    if (!snapshot.project.profile) {
      snapshot.project.profile = profileName;
    }
    if (!snapshot.project.state_dir) {
      snapshot.project.state_dir = stateDir;
    }
    snapshot.snapshot_transport = "local";
    snapshots.push(snapshot);
  }
  return snapshots;
}

function loadRemoteProjectSnapshots(config) {
  return loadRemoteSnapshots(config).map((record) => {
    const snapshot = isObjectLike(record.snapshot) ? { ...record.snapshot } : {};
    snapshot.project = isObjectLike(snapshot.project) ? snapshot.project : {};
    if (!snapshot.project.profile && record.profile) {
      snapshot.project.profile = String(record.profile);
    }
    if (!snapshot.project.repo && record.repo) {
      snapshot.project.repo = String(record.repo);
    }
    if (!snapshot.project.label) {
      snapshot.project.label = String(record.label || record.repo || record.source || "unknown");
    }
    snapshot.snapshot_source = "remote_ingest";
    snapshot.remote_source = String(record.source || "unknown");
    snapshot.remote_label = String(record.label || record.repo || record.source || "unknown");
    snapshot.remote_received_at = String(record.received_at || "");
    snapshot.snapshot_transport = "remote";
    return snapshot;
  });
}

function dedupeProjectSnapshots(snapshots) {
  const seen = new Set();
  const result = [];
  for (const snapshot of snapshots) {
    const project = isObjectLike(snapshot.project) ? snapshot.project : {};
    const key = `${project.label || project.repo || "unknown"}|${snapshot.snapshot_transport || "unknown"}|${snapshot.remote_source || ""}`;
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    result.push(snapshot);
  }
  return result;
}

function statusRank(status) {
  switch (String(status || "").toUpperCase()) {
    case "ERROR":
      return 60;
    case "BLOCKED":
      return 50;
    case "DEGRADED":
      return 40;
    case "WAITING_USER":
      return 30;
    case "WAITING_SYSTEM":
      return 20;
    case "WORKING":
      return 10;
    case "HEALTHY":
      return 0;
    default:
      return -1;
  }
}

async function loadProjectSnapshotsOverview(config) {
  const localSnapshots = await loadLocalProjectSnapshots(config);
  const remoteSnapshots = loadRemoteProjectSnapshots(config).filter((remoteSnapshot) => {
    const remoteLabel = String(remoteSnapshot?.project?.label || remoteSnapshot?.project?.repo || "");
    return !localSnapshots.some((localSnapshot) => {
      const localLabel = String(localSnapshot?.project?.label || localSnapshot?.project?.repo || "");
      return localLabel && remoteLabel && localLabel === remoteLabel;
    });
  });

  return dedupeProjectSnapshots([...localSnapshots, ...remoteSnapshots]).sort((left, right) => {
    const leftRank = statusRank(left.overall_status);
    const rightRank = statusRank(right.overall_status);
    if (leftRank !== rightRank) {
      return rightRank - leftRank;
    }
    const leftLabel = String(left?.project?.label || left?.project?.repo || "");
    const rightLabel = String(right?.project?.label || right?.project?.repo || "");
    return leftLabel.localeCompare(rightLabel);
  });
}

function statusBadgeClass(status) {
  switch (String(status || "").toUpperCase()) {
    case "HEALTHY":
      return "ok";
    case "WORKING":
      return "work";
    case "WAITING_USER":
    case "WAITING_SYSTEM":
      return "wait";
    case "DEGRADED":
      return "warn";
    case "BLOCKED":
    case "ERROR":
      return "bad";
    default:
      return "neutral";
  }
}

function renderStatusPage(config) {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Automation Ops</title>
  <style>
    :root {
      --bg-0: #f4f7f2;
      --bg-1: #e6efe2;
      --ink: #1a2b1f;
      --muted: #516157;
      --card: #ffffffcc;
      --line: #ccdac9;
      --ok: #1d7b45;
      --work: #356f9b;
      --wait: #9b6a2c;
      --warn: #b14f1f;
      --bad: #a32626;
      --neutral: #5c6d60;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: "Avenir Next", "Segoe UI", "Helvetica Neue", sans-serif;
      color: var(--ink);
      background:
        radial-gradient(1200px 520px at 8% -10%, #d5e7ce 0%, transparent 70%),
        radial-gradient(1100px 560px at 100% -20%, #d7e6ef 0%, transparent 72%),
        linear-gradient(180deg, var(--bg-0), var(--bg-1));
      min-height: 100vh;
      padding: 22px;
    }
    .wrap { max-width: 1100px; margin: 0 auto; }
    .top {
      display: grid;
      grid-template-columns: 1fr auto;
      gap: 14px;
      align-items: end;
      margin-bottom: 16px;
    }
    h1 {
      margin: 0;
      font-size: clamp(24px, 4.2vw, 38px);
      letter-spacing: 0.02em;
      text-transform: uppercase;
    }
    .stamp {
      color: var(--muted);
      font-size: 13px;
      font-family: "SFMono-Regular", Menlo, Monaco, Consolas, monospace;
    }
    .grid {
      display: grid;
      gap: 12px;
      grid-template-columns: repeat(12, 1fr);
    }
    .card {
      background: var(--card);
      backdrop-filter: blur(4px);
      border: 1px solid var(--line);
      border-radius: 14px;
      padding: 14px;
      min-height: 120px;
    }
    .card h2 {
      margin: 0 0 10px 0;
      font-size: 13px;
      letter-spacing: .06em;
      text-transform: uppercase;
      color: var(--muted);
    }
    .hero { grid-column: span 12; }
    .a { grid-column: span 4; }
    .b { grid-column: span 4; }
    .c { grid-column: span 4; }
    .mono {
      font-family: "SFMono-Regular", Menlo, Monaco, Consolas, monospace;
      font-size: 13px;
      white-space: pre-wrap;
      overflow-wrap: anywhere;
      line-height: 1.35;
      height: 132px;
      overflow-y: auto;
      overflow-x: hidden;
    }
    .line { margin: 0 0 8px 0; }
    .k { color: var(--muted); margin-right: 8px; }
    .v { font-family: "SFMono-Regular", Menlo, Monaco, Consolas, monospace; }
    .status {
      display: inline-block;
      padding: 6px 10px;
      border-radius: 999px;
      font-size: 12px;
      letter-spacing: .05em;
      text-transform: uppercase;
      color: #fff;
      font-weight: 600;
    }
    .status.ok { background: var(--ok); }
    .status.work { background: var(--work); }
    .status.wait { background: var(--wait); }
    .status.warn { background: var(--warn); }
    .status.bad { background: var(--bad); }
    .status.neutral { background: var(--neutral); }

    @media (max-width: 900px) {
      .a, .b, .c { grid-column: span 12; }
      .top { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="top">
      <div>
        <h1>Automation Ops Board</h1>
        <div class="stamp" id="stamp">loading...</div>
      </div>
      <div id="mainStatus" class="status neutral">loading</div>
    </div>

    <div class="grid">
      <section class="card hero">
        <h2>Current Decision</h2>
        <p class="line"><span class="k">Project</span><span id="project" class="v">-</span></p>
        <p class="line"><span class="k">Source</span><span id="source" class="v">-</span></p>
        <p class="line"><span class="k">Headline</span><span id="headline" class="v">-</span></p>
        <p class="line"><span class="k">Action</span><span id="action" class="v">-</span></p>
      </section>

      <section class="card hero">
        <h2>Remote Sources</h2>
        <div class="mono" id="remoteSources">-</div>
      </section>

      <section class="card a">
        <h2>Daemon</h2>
        <div class="mono" id="daemon">-</div>
      </section>

      <section class="card b">
        <h2>Executor</h2>
        <div class="mono" id="executor">-</div>
      </section>

      <section class="card c">
        <h2>Watchdog</h2>
        <div class="mono" id="watchdog">-</div>
      </section>

      <section class="card a">
        <h2>Queues</h2>
        <div class="mono" id="queues">-</div>
      </section>

      <section class="card b">
        <h2>Blockers</h2>
        <div class="mono" id="blockers">-</div>
      </section>

      <section class="card c">
        <h2>Backlog Seed</h2>
        <div class="mono" id="backlog">-</div>
      </section>
    </div>
  </div>

  <script>
    const refreshMs = ${Math.max(2, config.refreshSec) * 1000};

    function badgeClass(status) {
      const s = String(status || "").toUpperCase();
      if (s === "HEALTHY") return "ok";
      if (s === "WORKING") return "work";
      if (s === "WAITING_USER" || s === "WAITING_SYSTEM") return "wait";
      if (s === "DEGRADED") return "warn";
      if (s === "BLOCKED" || s === "ERROR") return "bad";
      return "neutral";
    }

    function setText(id, value) {
      const node = document.getElementById(id);
      if (!node) return;
      node.textContent = value;
    }

    function line(label, value) {
      return String(label) + ": " + String(value);
    }

    function valueOr(value, fallbackValue) {
      return value === null || value === undefined ? fallbackValue : value;
    }

    function formatDetail(value) {
      return String(value || "-").replace(/;\\s*/g, ";\\n");
    }

    function render(snapshot) {
      setText("stamp", "updated " + (snapshot.generated_at || "-"));
      const project = snapshot.project || {};
      const remoteSources = Array.isArray(snapshot.remote_sources) ? snapshot.remote_sources : [];
      const remoteSourceLabel = snapshot.remote_label || snapshot.remote_source || "local";
      setText("project", project.label || project.repo || "-");
      setText("source", remoteSourceLabel);
      setText("headline", snapshot.headline || "-");
      setText("action", snapshot.action_required || "none");

      const main = document.getElementById("mainStatus");
      const status = snapshot.overall_status || "UNKNOWN";
      main.textContent = status;
      main.className = "status " + badgeClass(status);

      const daemon = snapshot.daemon || {};
      const executor = snapshot.executor || {};
      const watchdog = snapshot.watchdog || {};
      const queues = snapshot.queues || {};
      const blockers = snapshot.blockers || {};
      const dirty = blockers.dirty_worktree || {};
      const deps = blockers.dependencies || {};
      const seed = snapshot.backlog_seed || {};

      setText("daemon", [
        line("state", daemon.state || "-"),
        line("state_age_sec", valueOr(daemon.state_age_sec, "-")),
        line("github", daemon.github_status || "-"),
        line("telegram", daemon.telegram_status || "-"),
        line("detail", formatDetail(daemon.detail))
      ].join("\\n"));

      setText("executor", [
        line("state", executor.state || "-"),
        line("pid", executor.pid || "-"),
        line("pid_alive", valueOr(executor.pid_alive, "-")),
        line("heartbeat_age_sec", valueOr(executor.heartbeat_age_sec, "-"))
      ].join("\\n"));

      setText("watchdog", [
        line("state", watchdog.state || "-"),
        line("state_age_sec", valueOr(watchdog.state_age_sec, "-")),
        line("last_action", watchdog.last_action || "-"),
        line("detail", formatDetail(watchdog.detail))
      ].join("\\n"));

      setText("queues", [
        line("outbox_pending", valueOr(queues.outbox_pending, 0)),
        line("runtime_status_pending", valueOr(queues.runtime_status_pending, 0)),
        line("rate_window", (snapshot.rate_limit || {}).window_state || "-"),
        line("rate_requests", valueOr((snapshot.rate_limit || {}).window_requests, 0))
      ].join("\\n"));

      setText("blockers", [
        line("dirty_blocking_todo", valueOr(dirty.blocking_todo, false)),
        line("dirty_tracked_count", valueOr(dirty.tracked_count, 0)),
        line("open_pr_count", valueOr(blockers.open_pr_count, 0)),
        line("dependency_blockers", deps.blockers || "-")
      ].join("\\n"));

      setText("backlog", [
        line("plan_present", valueOr(seed.plan_present, false)),
        line("remaining", valueOr(seed.remaining, 0)),
        line("next_code", seed.next_code || "-")
      ].join("\\n"));

      setText("remoteSources", remoteSources.length > 0
        ? remoteSources.map((item) => [
            line("label", item.label || item.repo || item.source || "-"),
            line("status", item.overall_status || "-"),
            line("age_sec", valueOr(item.age_sec, "-")),
            line("stale", valueOr(item.stale, false)),
            line("headline", item.headline || "-")
          ].join("\\n")).join("\\n\\n")
        : "none");
    }

    async function tick() {
      try {
        const response = await fetch("/ops/status.json", { cache: "no-store" });
        if (!response.ok) {
          throw new Error("HTTP " + response.status);
        }
        const payload = await response.json();
        render(payload);
      } catch (error) {
        setText("headline", "status fetch failed: " + error.message);
      }
    }

    tick();
    setInterval(tick, refreshMs);
  </script>
</body>
</html>`;
}

function formatStatusMessage(snapshotList) {
  const items = Array.isArray(snapshotList) ? snapshotList : [snapshotList];
  const sections = ["<b>Automation Status</b>"];

  for (const snapshot of items) {
    const daemon = snapshot.daemon || {};
    const executor = snapshot.executor || {};
    const queues = snapshot.queues || {};
    const blockers = snapshot.blockers || {};
    const seed = snapshot.backlog_seed || {};
    const project = snapshot.project || {};
    const sourceLabel = snapshot.remote_label || snapshot.remote_source || snapshot.snapshot_transport || "local";

    const blockLines = [];
    blockLines.push(`State=${snapshot.overall_status || "UNKNOWN"}`);
    blockLines.push(`Headline=${snapshot.headline || "-"}`);
    blockLines.push(`Action=${snapshot.action_required || "none"}`);
    blockLines.push(`Source=${sourceLabel}`);
    blockLines.push(`Daemon=${daemon.state || "-"} · GitHub=${daemon.github_status || "-"}`);
    blockLines.push(`Executor=${executor.state || "-"} · pid_alive=${String(executor.pid_alive ?? false)}`);
    blockLines.push(`Queues=outbox=${String(queues.outbox_pending ?? 0)}, runtime=${String(queues.runtime_status_pending ?? 0)}`);
    blockLines.push(`Blockers=open_pr=${String(blockers.open_pr_count ?? 0)}`);
    if (blockers.dependencies && blockers.dependencies.blockers) {
      blockLines.push(`Depends=${blockers.dependencies.blockers}`);
    }
    if (blockers.dirty_worktree) {
      blockLines.push(
        `Dirty=blocking_todo=${String(blockers.dirty_worktree.blocking_todo ?? false)} count=${String(blockers.dirty_worktree.tracked_count ?? 0)}`,
      );
    }
    blockLines.push(
      `Backlog-seed=plan=${String(seed.plan_present ?? false)} remaining=${String(seed.remaining ?? 0)} next=${seed.next_code || "-"}`,
    );
    blockLines.push(`Generated=${snapshot.generated_at || "-"}`);

    sections.push("");
    sections.push(`<b>${htmlEscape(project.label || project.repo || "unknown project")}</b>`);
    sections.push(`<blockquote><code>${htmlEscape(blockLines.join("\n"))}</code></blockquote>`);
  }

  return sections.join("\n");
}

function formatHelpMessage(config) {
  const lines = [];
  lines.push("<b>Automation Ops Bot</b>");
  lines.push("Available commands:");
  lines.push("<code>/status</code> - automation snapshot for all known projects");
  lines.push("<code>/summary [hours]</code> - log summary, default 6h");
  lines.push("<code>/help</code> - this help");
  if (config.publicBaseUrl) {
    lines.push(`<code>/status_page</code> - open dashboard: ${htmlEscape(config.publicBaseUrl.replace(/\/$/, ""))}/ops/status`);
  }
  return lines.join("\n");
}

async function sendTelegramMessage(config, chatId, text) {
  if (!config.tgBotToken) {
    throw new Error("TG_BOT_TOKEN is not configured");
  }
  const endpoint = `https://api.telegram.org/bot${config.tgBotToken}/sendMessage`;
  const payload = JSON.stringify({
    chat_id: chatId,
    text,
    parse_mode: "HTML",
    disable_web_page_preview: true,
  });

  const result = await requestJson({
    method: "POST",
    url: endpoint,
    timeoutMs: 15000,
    headers: {
      "Content-Type": "application/json",
      "Content-Length": Buffer.byteLength(payload),
    },
    body: payload,
  });

  if (result.statusCode < 200 || result.statusCode >= 300) {
    throw new Error(`Telegram API status=${result.statusCode}`);
  }
}

function resolveIncomingMessage(update) {
  if (update && update.message && typeof update.message.text === "string") {
    return update.message;
  }
  if (update && update.edited_message && typeof update.edited_message.text === "string") {
    return update.edited_message;
  }
  return null;
}

function normalizeCommand(text) {
  const trimmed = String(text || "").trim();
  if (!trimmed.startsWith("/")) {
    return { name: "", args: [] };
  }
  const parts = trimmed.split(/\s+/).filter(Boolean);
  const rawCommand = parts[0].toLowerCase();
  const command = rawCommand.includes("@") ? rawCommand.split("@")[0] : rawCommand;
  return { name: command, args: parts.slice(1) };
}

function isObjectLike(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

async function handleTelegramCommand(config, logger, update) {
  if (!isObjectLike(update)) {
    return false;
  }

  const message = resolveIncomingMessage(update);
  if (!message) {
    return false;
  }

  const rawChatId = message && message.chat ? message.chat.id : "";
  const chatId = rawChatId === undefined || rawChatId === null ? "" : String(rawChatId);
  if (!chatId) {
    return false;
  }

  if (config.allowedChatIds.size > 0 && !config.allowedChatIds.has(chatId)) {
    logger.warn(`[ops-bot] ignored command from unauthorized chat_id=${chatId}`);
    return false;
  }

  const { name, args } = normalizeCommand(message.text || "");
  if (!name) {
    return false;
  }

  let responseText = "";
  try {
    if (name === "/start" || name === "/help") {
      responseText = formatHelpMessage(config);
    } else if (name === "/status") {
      const snapshots = await loadProjectSnapshotsOverview(config);
      responseText = formatStatusMessage(snapshots);
    } else if (name === "/summary") {
      const hours = args.length > 0 ? parseInteger(args[0], DEFAULT_SUMMARY_HOURS) : DEFAULT_SUMMARY_HOURS;
      const summary = await loadEffectiveSummary(config, hours);
      const sourceTag =
        summary.source === "remote_ingest"
          ? `remote_ingest:${summary.remoteLabel || summary.remoteRepo || summary.remoteSource || "unknown"}`
          : "local";
      const staleTag = summary.remoteStale ? " (stale)" : "";
      const usedWindowTag = summary.exactWindow ? "" : `, nearest=${summary.usedHours}h`;
      const ageTag = summary.source === "remote_ingest" ? `, age=${summary.remoteAgeSec}s${staleTag}` : "";
      responseText =
        `<b>log_summary --hours ${summary.hours}</b>\n` +
        `<b>Source:</b> <code>${htmlEscape(sourceTag)}</code>${htmlEscape(ageTag + usedWindowTag)}\n` +
        `<pre>${htmlEscape(truncateText(summary.text || "no data", 3600))}</pre>`;
    } else if (name === "/status_page") {
      if (config.publicBaseUrl) {
        const url = `${config.publicBaseUrl.replace(/\/$/, "")}/ops/status`;
        responseText = `<b>Ops dashboard</b>\n${htmlEscape(url)}`;
      } else {
        responseText = "OPS_BOT_PUBLIC_BASE_URL is not configured.";
      }
    } else {
      responseText = "Unknown command. Use /help.";
    }
  } catch (error) {
    responseText = `Command failed: <code>${htmlEscape(error && error.message ? error.message : "unknown")}</code>`;
  }

  responseText = truncateText(responseText, 3900);
  await sendTelegramMessage(config, chatId, responseText);
  return true;
}

function createServer(config, logger) {
  const statusHtml = renderStatusPage(config);

  const server = http.createServer(async (req, res) => {
    try {
      const url = new URL(req.url || "/", "http://localhost");

      if (req.method === "GET" && url.pathname === "/health") {
        const envAudit = await loadEffectiveEnvAudit(config);
        sendJson(res, 200, {
          status: "ok",
          service: "ops-bot",
          webhook_path: config.webhookPath,
          ingest_path: config.ingestPath,
          summary_ingest_path: config.summaryIngestPath,
          ingest_enabled: config.ingestEnabled,
          telegram_enabled: Boolean(config.tgBotToken),
          env_audit_ready: envAudit.ready,
          env_audit_status: envAudit.status,
          env_audit_summary: envAudit.summary,
        });
        return;
      }

      if (req.method === "GET" && url.pathname === "/ops/status.json") {
        const snapshot = await loadEffectiveSnapshot(config);
        sendJson(res, 200, snapshot);
        return;
      }

      if (req.method === "GET" && url.pathname === "/ops/status") {
        sendHtml(res, 200, statusHtml);
        return;
      }

      if (req.method === "GET" && url.pathname === "/ops/debug/runtime.json") {
        if (!requireDebugAuth(req, res, config)) {
          return;
        }
        const payload = await buildDebugRuntimePayload(config);
        sendJson(res, 200, payload);
        return;
      }

      if (req.method === "GET" && url.pathname === "/ops/debug/log-summary.json") {
        if (!requireDebugAuth(req, res, config)) {
          return;
        }
        const hours = parsePositiveInteger(url.searchParams.get("hours"), DEFAULT_SUMMARY_HOURS, {
          min: 1,
          max: 168,
        });
        const summary = await loadEffectiveSummary(config, hours);
        sendJson(res, 200, {
          ...summary,
          text: redactSensitiveText(summary.text, config),
        });
        return;
      }

      const debugLogMatch = /^\/ops\/debug\/logs\/([a-z0-9._-]+)$/.exec(url.pathname);
      if (req.method === "GET" && debugLogMatch) {
        if (!requireDebugAuth(req, res, config)) {
          return;
        }
        const lines = parsePositiveInteger(url.searchParams.get("lines"), config.debugDefaultLines, {
          min: 1,
          max: config.debugMaxLines,
        });
        try {
          const payload = loadDebugLogTail(config, debugLogMatch[1], lines);
          sendJson(res, 200, payload);
        } catch (error) {
          if (error && error.code === "UNKNOWN_LOG") {
            sendJson(res, 404, {
              error: "UNKNOWN_LOG",
              message: error.message,
              available_logs: DEBUG_LOG_NAMES,
            });
            return;
          }
          throw error;
        }
        return;
      }

      if (req.method === "GET" && url.pathname === "/") {
        sendText(
          res,
          200,
          `Automation ops-bot service\nGET /health\nGET /ops/status\nGET /ops/status.json\nGET /ops/debug/runtime.json\nGET /ops/debug/log-summary.json?hours=6\nGET /ops/debug/logs/{daemon|watchdog|executor|graphql-rate}?lines=120\nPOST ${config.ingestPath}\nPOST ${config.summaryIngestPath}\n`,
        );
        return;
      }

      if (req.method === "POST" && config.ingestEnabled && url.pathname === config.ingestPath) {
        if (config.ingestSecret) {
          const providedSecret = extractHeader(req, "x-ops-status-secret");
          if (providedSecret !== config.ingestSecret) {
            sendJson(res, 401, { error: "UNAUTHORIZED", message: "invalid ingest secret" });
            return;
          }
        }

        let body = "";
        try {
          body = await collectRequestBody(req, 2 * 1024 * 1024);
        } catch (error) {
          if (error && error.message === "request body too large") {
            sendJson(res, 413, { error: "PAYLOAD_TOO_LARGE", message: "ingest payload exceeds limit" });
            return;
          }
          throw error;
        }

        let payload;
        try {
          payload = JSON.parse(body || "{}");
        } catch (_error) {
          sendJson(res, 400, { error: "BAD_REQUEST", message: "invalid json payload" });
          return;
        }

        if (!isObjectLike(payload) || !isObjectLike(payload.snapshot)) {
          sendJson(res, 400, { error: "BAD_REQUEST", message: "snapshot payload is required" });
          return;
        }

        const record = {
          received_at: new Date().toISOString(),
          source: String(payload.source || "unknown"),
          profile: String(payload.profile || payload.snapshot?.project?.profile || ""),
          repo: String(payload.repo || payload.snapshot?.project?.repo || ""),
          label: String(payload.label || payload.snapshot?.project?.label || payload.repo || payload.source || "unknown"),
          pushed_at: String(payload.pushed_at || ""),
          snapshot: payload.snapshot,
        };
        writeRemoteSnapshot(config, record);
        sendJson(res, 200, { ok: true, stored: true, source: record.source, received_at: record.received_at });
        return;
      }

      if (req.method === "POST" && config.ingestEnabled && url.pathname === config.summaryIngestPath) {
        if (config.summaryIngestSecret) {
          const providedSecret = extractHeader(req, "x-ops-status-secret");
          if (providedSecret !== config.summaryIngestSecret) {
            sendJson(res, 401, { error: "UNAUTHORIZED", message: "invalid summary ingest secret" });
            return;
          }
        }

        let body = "";
        try {
          body = await collectRequestBody(req, 4 * 1024 * 1024);
        } catch (error) {
          if (error && error.message === "request body too large") {
            sendJson(res, 413, { error: "PAYLOAD_TOO_LARGE", message: "summary payload exceeds limit" });
            return;
          }
          throw error;
        }

        let payload;
        try {
          payload = JSON.parse(body || "{}");
        } catch (_error) {
          sendJson(res, 400, { error: "BAD_REQUEST", message: "invalid json payload" });
          return;
        }

        if (!isObjectLike(payload) || !isObjectLike(payload.summaries)) {
          sendJson(res, 400, { error: "BAD_REQUEST", message: "summaries payload is required" });
          return;
        }

        const summaries = {};
        for (const [key, value] of Object.entries(payload.summaries)) {
          const parsedHours = Number.parseInt(String(key), 10);
          if (!Number.isInteger(parsedHours) || parsedHours < 1 || parsedHours > 168) {
            continue;
          }
          if (typeof value !== "string" || !value.trim()) {
            continue;
          }
          summaries[String(parsedHours)] = value;
        }
        if (Object.keys(summaries).length === 0) {
          sendJson(res, 400, { error: "BAD_REQUEST", message: "at least one summary window is required" });
          return;
        }

        const record = {
          received_at: new Date().toISOString(),
          source: String(payload.source || "unknown"),
          profile: String(payload.profile || ""),
          repo: String(payload.repo || ""),
          label: String(payload.label || payload.repo || payload.source || "unknown"),
          pushed_at: String(payload.pushed_at || ""),
          generated_at: String(payload.generated_at || ""),
          summaries,
        };
        writeRemoteSummary(config, record);
        sendJson(res, 200, { ok: true, stored: true, source: record.source, received_at: record.received_at });
        return;
      }

      if (req.method === "POST" && url.pathname === config.webhookPath) {
        if (config.telegramSecretToken) {
          const providedSecret = extractHeader(req, "x-telegram-bot-api-secret-token");
          if (providedSecret !== config.telegramSecretToken) {
            sendJson(res, 401, { error: "UNAUTHORIZED", message: "invalid telegram secret token" });
            return;
          }
        }

        let body = "";
        try {
          body = await collectRequestBody(req, 1024 * 1024);
        } catch (error) {
          if (error && error.message === "request body too large") {
            sendJson(res, 413, { error: "PAYLOAD_TOO_LARGE", message: "telegram update exceeds limit" });
            return;
          }
          throw error;
        }

        let update;
        try {
          update = JSON.parse(body || "{}");
        } catch (_error) {
          sendJson(res, 400, { error: "BAD_REQUEST", message: "invalid json payload" });
          return;
        }

        if (!isObjectLike(update)) {
          sendJson(res, 200, { ok: true, command_handled: false, ignored_reason: "unsupported_update" });
          return;
        }

        let commandHandled = false;
        try {
          commandHandled = await handleTelegramCommand(config, logger, update);
        } catch (error) {
          logger.warn(
            `[ops-bot] TELEGRAM_COMMAND_ERROR: ${error && error.message ? error.message : "unknown"}`,
          );
        }

        sendJson(res, 200, { ok: true, command_handled: commandHandled });
        return;
      }

      sendJson(res, 404, { error: "NOT_FOUND", message: "endpoint not found" });
    } catch (error) {
      logger.error(`[ops-bot] INTERNAL_ERROR: ${error && error.message ? error.message : "unknown"}`);
      sendJson(res, 500, { error: "INTERNAL_ERROR", message: "unexpected internal error" });
    }
  });

  return server;
}

function main() {
  const logger = createLogger();

  let config;
  try {
    config = loadConfig(process.env);
  } catch (error) {
    logger.error(`[ops-bot] CONFIG_ERROR: ${error && error.message ? error.message : "unknown"}`);
    process.exitCode = 1;
    return;
  }

  const server = createServer(config, logger);
  server.on("error", (error) => {
    logger.error(`[ops-bot] LISTEN_ERROR: ${error && error.message ? error.message : "unknown"}`);
    process.exit(1);
  });
  server.listen(config.port, config.bind, () => {
    logger.info(
      `[ops-bot] listening on ${config.bind}:${config.port}; webhook_path=${config.webhookPath}; ingest_path=${config.ingestPath}; summary_ingest_path=${config.summaryIngestPath}; ingest_enabled=${config.ingestEnabled}; telegram_enabled=${Boolean(config.tgBotToken)}`,
    );
  });

  function shutdown(signalName) {
    logger.info(`[ops-bot] received ${signalName}, shutting down`);
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 5000).unref();
  }

  process.on("SIGINT", () => shutdown("SIGINT"));
  process.on("SIGTERM", () => shutdown("SIGTERM"));
}

if (require.main === module) {
  main();
}

module.exports = {
  createServer,
  handleTelegramCommand,
  isObjectLike,
  loadConfig,
  loadEffectiveEnvAudit,
  loadEffectiveSummary,
  loadProjectSnapshotsOverview,
  normalizeCommand,
  parseEnvAuditOutput,
  resolveIncomingMessage,
};
