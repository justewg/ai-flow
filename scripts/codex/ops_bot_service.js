#!/usr/bin/env node
"use strict";

const fs = require("fs");
const http = require("http");
const https = require("https");
const path = require("path");
const { execFile } = require("child_process");

const ROOT_DIR = path.resolve(__dirname, "../..");
const CODEX_DIR = path.join(ROOT_DIR, ".tmp", "codex");
const DEFAULT_BIND = "127.0.0.1";
const DEFAULT_PORT = 8790;
const DEFAULT_WEBHOOK_PATH = "/telegram/webhook";
const DEFAULT_INGEST_PATH = "/ops/ingest/status";
const DEFAULT_REFRESH_SEC = 5;
const DEFAULT_CMD_TIMEOUT_MS = 10000;
const DEFAULT_SUMMARY_HOURS = 6;
const DEFAULT_REMOTE_SNAPSHOT_TTL_SEC = 600;

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
    req.on("data", (chunk) => {
      total += chunk.length;
      if (total > maxBytes) {
        reject(new Error("request body too large"));
        req.destroy();
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
  function line(level, message) {
    const stamp = new Date().toISOString();
    return `${stamp} ${level} ${message}`;
  }

  return {
    info(message) {
      process.stdout.write(`${line("INFO", message)}\n`);
    },
    warn(message) {
      process.stdout.write(`${line("WARN", message)}\n`);
    },
    error(message) {
      process.stderr.write(`${line("ERROR", message)}\n`);
    },
  };
}

function loadConfig(env = process.env) {
  const bind = String(env.OPS_BOT_BIND || DEFAULT_BIND).trim() || DEFAULT_BIND;
  const port = parsePort(env.OPS_BOT_PORT, DEFAULT_PORT);
  const webhookPathBase = normalizePath(env.OPS_BOT_WEBHOOK_PATH, DEFAULT_WEBHOOK_PATH);
  const ingestPath = normalizePath(env.OPS_BOT_INGEST_PATH, DEFAULT_INGEST_PATH);
  const webhookSecret = String(env.OPS_BOT_WEBHOOK_SECRET || "").trim();
  const telegramSecretToken = String(env.OPS_BOT_TG_SECRET_TOKEN || "").trim();
  const ingestSecret = String(env.OPS_BOT_INGEST_SECRET || "").trim();
  const ingestEnabled = parseBoolean(env.OPS_BOT_INGEST_ENABLED, false);
  const allowedChatIds = new Set(splitCsv(env.OPS_BOT_ALLOWED_CHAT_IDS));

  const snapshotScript = path.resolve(
    env.OPS_BOT_STATUS_SNAPSHOT_SCRIPT || path.join(ROOT_DIR, "scripts", "codex", "status_snapshot.sh"),
  );
  const logSummaryScript = path.resolve(
    env.OPS_BOT_LOG_SUMMARY_SCRIPT || path.join(ROOT_DIR, "scripts", "codex", "log_summary.sh"),
  );

  const refreshSec = Math.max(2, parseInteger(env.OPS_BOT_REFRESH_SEC, DEFAULT_REFRESH_SEC));
  const cmdTimeoutMs = Math.max(2000, parseInteger(env.OPS_BOT_CMD_TIMEOUT_MS, DEFAULT_CMD_TIMEOUT_MS));

  const tgBotToken = String(env.OPS_BOT_TG_BOT_TOKEN || env.DAEMON_TG_BOT_TOKEN || env.TG_BOT_TOKEN || "").trim();
  const publicBaseUrl = String(env.OPS_BOT_PUBLIC_BASE_URL || "").trim();
  const remoteSnapshotFile = path.resolve(
    env.OPS_BOT_REMOTE_SNAPSHOT_FILE || path.join(CODEX_DIR, "ops_remote_snapshot.json"),
  );
  const remoteSnapshotTtlSec = Math.max(
    30,
    parseInteger(env.OPS_BOT_REMOTE_SNAPSHOT_TTL_SEC, DEFAULT_REMOTE_SNAPSHOT_TTL_SEC),
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
    webhookSecret,
    telegramSecretToken,
    ingestSecret,
    ingestEnabled,
    allowedChatIds,
    snapshotScript,
    logSummaryScript,
    refreshSec,
    cmdTimeoutMs,
    tgBotToken,
    publicBaseUrl,
    remoteSnapshotFile,
    remoteSnapshotTtlSec,
  };
}

async function loadSnapshot(config) {
  try {
    const { stdout } = await execFileAsync(config.snapshotScript, [], {
      cwd: ROOT_DIR,
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

function loadRemoteSnapshot(config) {
  try {
    if (!fs.existsSync(config.remoteSnapshotFile)) {
      return null;
    }
    const raw = fs.readFileSync(config.remoteSnapshotFile, "utf8");
    if (!raw.trim()) {
      return null;
    }
    const parsed = JSON.parse(raw);
    if (!isObjectLike(parsed) || !isObjectLike(parsed.snapshot)) {
      return null;
    }
    return parsed;
  } catch (_error) {
    return null;
  }
}

function writeRemoteSnapshot(config, payload) {
  const dirPath = path.dirname(config.remoteSnapshotFile);
  fs.mkdirSync(dirPath, { recursive: true });
  const tempPath = `${config.remoteSnapshotFile}.${process.pid}.${Date.now()}.tmp`;
  fs.writeFileSync(tempPath, `${JSON.stringify(payload)}\n`, "utf8");
  fs.renameSync(tempPath, config.remoteSnapshotFile);
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

async function loadEffectiveSnapshot(config) {
  const localSnapshot = await loadSnapshot(config);
  const remote = loadRemoteSnapshot(config);
  if (!remote) {
    return localSnapshot;
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
    remoteSnapshot.remote_received_at = String(remote.received_at || "");
    remoteSnapshot.remote_age_sec = ageSec;
    remoteSnapshot.remote_stale = !remoteFresh;
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

  return localSnapshot;
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
  <title>PLANKA Automation Ops</title>
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
        <h1>PLANKA Ops Board</h1>
        <div class="stamp" id="stamp">loading...</div>
      </div>
      <div id="mainStatus" class="status neutral">loading</div>
    </div>

    <div class="grid">
      <section class="card hero">
        <h2>Current Decision</h2>
        <p class="line"><span class="k">Headline</span><span id="headline" class="v">-</span></p>
        <p class="line"><span class="k">Action</span><span id="action" class="v">-</span></p>
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

function formatStatusMessage(snapshot) {
  const daemon = snapshot.daemon || {};
  const executor = snapshot.executor || {};
  const queues = snapshot.queues || {};
  const blockers = snapshot.blockers || {};
  const seed = snapshot.backlog_seed || {};

  const lines = [];
  lines.push("<b>PLANKA Automation Status</b>");
  lines.push(`<b>State:</b> <code>${htmlEscape(snapshot.overall_status || "UNKNOWN")}</code>`);
  lines.push(`<b>Headline:</b> ${htmlEscape(snapshot.headline || "-")}`);
  lines.push(`<b>Action:</b> <code>${htmlEscape(snapshot.action_required || "none")}</code>`);
  lines.push("");
  lines.push(`<b>Daemon:</b> <code>${htmlEscape(daemon.state || "-")}</code> · GitHub=<code>${htmlEscape(daemon.github_status || "-")}</code>`);
  lines.push(`<b>Executor:</b> <code>${htmlEscape(executor.state || "-")}</code> · pid_alive=<code>${htmlEscape(String(executor.pid_alive ?? false))}</code>`);
  lines.push(`<b>Queues:</b> outbox=<code>${htmlEscape(String(queues.outbox_pending ?? 0))}</code>, runtime=<code>${htmlEscape(String(queues.runtime_status_pending ?? 0))}</code>`);
  lines.push(`<b>Blockers:</b> open_pr=<code>${htmlEscape(String(blockers.open_pr_count ?? 0))}</code>`);
  if (blockers.dependencies && blockers.dependencies.blockers) {
    lines.push(`<b>Depends:</b> <code>${htmlEscape(blockers.dependencies.blockers)}</code>`);
  }
  if (blockers.dirty_worktree) {
    lines.push(`<b>Dirty:</b> blocking_todo=<code>${htmlEscape(String(blockers.dirty_worktree.blocking_todo ?? false))}</code> count=<code>${htmlEscape(String(blockers.dirty_worktree.tracked_count ?? 0))}</code>`);
  }
  lines.push(`<b>Backlog-seed:</b> plan=<code>${htmlEscape(String(seed.plan_present ?? false))}</code> remaining=<code>${htmlEscape(String(seed.remaining ?? 0))}</code> next=<code>${htmlEscape(seed.next_code || "-")}</code>`);
  lines.push(`<b>Generated:</b> <code>${htmlEscape(snapshot.generated_at || "-")}</code>`);

  return lines.join("\n");
}

function formatHelpMessage(config) {
  const lines = [];
  lines.push("<b>PLANKA Ops Bot</b>");
  lines.push("Available commands:");
  lines.push("<code>/status</code> - current automation snapshot");
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
      const snapshot = await loadEffectiveSnapshot(config);
      responseText = formatStatusMessage(snapshot);
    } else if (name === "/summary") {
      const hours = args.length > 0 ? parseInteger(args[0], DEFAULT_SUMMARY_HOURS) : DEFAULT_SUMMARY_HOURS;
      const summary = await loadSummary(config, hours);
      responseText = `<b>log_summary --hours ${summary.hours}</b>\n<pre>${htmlEscape(truncateText(summary.text || "no data", 3600))}</pre>`;
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
        sendJson(res, 200, {
          status: "ok",
          service: "ops-bot",
          webhook_path: config.webhookPath,
          ingest_path: config.ingestPath,
          ingest_enabled: config.ingestEnabled,
          telegram_enabled: Boolean(config.tgBotToken),
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

      if (req.method === "GET" && url.pathname === "/") {
        sendText(
          res,
          200,
          "PLANKA ops-bot service\nGET /health\nGET /ops/status\nGET /ops/status.json\nPOST /ops/ingest/status\n",
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
          pushed_at: String(payload.pushed_at || ""),
          snapshot: payload.snapshot,
        };
        writeRemoteSnapshot(config, record);
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
      `[ops-bot] listening on ${config.bind}:${config.port}; webhook_path=${config.webhookPath}; ingest_path=${config.ingestPath}; ingest_enabled=${config.ingestEnabled}; telegram_enabled=${Boolean(config.tgBotToken)}`,
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
  normalizeCommand,
  resolveIncomingMessage,
};
