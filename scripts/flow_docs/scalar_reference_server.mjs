#!/usr/bin/env node

import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { statSync } from "node:fs";
import path from "node:path";
import process from "node:process";

const DEFAULT_BIND = process.env.FLOW_DOCS_SCALAR_BIND || "127.0.0.1";
const DEFAULT_PORT = Number.parseInt(process.env.FLOW_DOCS_SCALAR_PORT || "4310", 10);
const DEFAULT_ROOT = process.env.FLOW_DOCS_SCALAR_ROOT || path.dirname(new URL(import.meta.url).pathname);
const HIDDEN_FILES = new Set(["server.mjs"]);
const MIME_TYPES = {
  ".css": "text/css; charset=utf-8",
  ".html": "text/html; charset=utf-8",
  ".ico": "image/x-icon",
  ".js": "application/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".map": "application/json; charset=utf-8",
  ".png": "image/png",
  ".svg": "image/svg+xml; charset=utf-8",
  ".txt": "text/plain; charset=utf-8",
};

function parseArgs(argv) {
  const options = {
    bind: DEFAULT_BIND,
    port: Number.isInteger(DEFAULT_PORT) && DEFAULT_PORT > 0 ? DEFAULT_PORT : 4310,
    root: path.resolve(DEFAULT_ROOT),
  };

  for (let index = 2; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--bind") {
      options.bind = argv[index + 1] || options.bind;
      index += 1;
      continue;
    }
    if (arg === "--port") {
      const parsed = Number.parseInt(argv[index + 1] || "", 10);
      if (!Number.isInteger(parsed) || parsed < 1 || parsed > 65535) {
        throw new Error(`Invalid --port value: ${argv[index + 1] || ""}`);
      }
      options.port = parsed;
      index += 1;
      continue;
    }
    if (arg === "--root") {
      options.root = path.resolve(argv[index + 1] || options.root);
      index += 1;
      continue;
    }
    if (arg === "--help" || arg === "-h") {
      printHelp();
      process.exit(0);
    }
    throw new Error(`Unknown argument: ${arg}`);
  }

  return options;
}

function printHelp() {
  process.stdout.write(
    [
      "Usage: node server.mjs [--bind 127.0.0.1] [--port 4310] [--root /path/to/site]",
      "",
      "Environment variables:",
      "  FLOW_DOCS_SCALAR_BIND",
      "  FLOW_DOCS_SCALAR_PORT",
      "  FLOW_DOCS_SCALAR_ROOT",
      "",
    ].join("\n"),
  );
}

function resolveFile(rootDir, requestPath) {
  const relativePath = requestPath === "/" ? "index.html" : requestPath.replace(/^\/+/, "");
  const normalized = path.normalize(relativePath);

  if (normalized.startsWith("..") || path.isAbsolute(normalized)) {
    return null;
  }
  if (HIDDEN_FILES.has(path.basename(normalized))) {
    return null;
  }

  return path.join(rootDir, normalized);
}

function cacheHeader(filePath) {
  if (filePath.endsWith(".html") || filePath.endsWith(".json")) {
    return "no-store";
  }
  return "public, max-age=3600";
}

function sendJson(res, statusCode, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
  });
  res.end(body);
}

async function serveFile(res, filePath) {
  const extension = path.extname(filePath).toLowerCase();
  const contentType = MIME_TYPES[extension] || "application/octet-stream";
  const body = await readFile(filePath);
  res.writeHead(200, {
    "Content-Type": contentType,
    "Cache-Control": cacheHeader(filePath),
  });
  res.end(body);
}

async function main() {
  const options = parseArgs(process.argv);

  try {
    const stats = statSync(options.root);
    if (!stats.isDirectory()) {
      throw new Error(`Scalar site root is not a directory: ${options.root}`);
    }
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exit(1);
  }

  const server = createServer(async (req, res) => {
    const method = req.method || "GET";
    const url = new URL(req.url || "/", "http://127.0.0.1");

    if (method === "GET" && url.pathname === "/health") {
      sendJson(res, 200, {
        status: "ok",
        service: "flow-docs-scalar",
        root: options.root,
        bind: options.bind,
        port: options.port,
      });
      return;
    }

    if (method !== "GET" && method !== "HEAD") {
      sendJson(res, 405, {
        error: "METHOD_NOT_ALLOWED",
        message: "Only GET and HEAD methods are supported",
      });
      return;
    }

    const filePath = resolveFile(options.root, url.pathname);
    if (!filePath) {
      sendJson(res, 404, { error: "NOT_FOUND", message: "file not found" });
      return;
    }

    try {
      const stats = statSync(filePath);
      if (!stats.isFile()) {
        sendJson(res, 404, { error: "NOT_FOUND", message: "file not found" });
        return;
      }

      if (method === "HEAD") {
        res.writeHead(200, {
          "Content-Type": MIME_TYPES[path.extname(filePath).toLowerCase()] || "application/octet-stream",
          "Cache-Control": cacheHeader(filePath),
        });
        res.end();
        return;
      }

      await serveFile(res, filePath);
    } catch (_error) {
      sendJson(res, 404, { error: "NOT_FOUND", message: "file not found" });
    }
  });

  server.listen(options.port, options.bind, () => {
    process.stdout.write(
      `FLOW_DOCS_SCALAR_SERVER_OK bind=${options.bind} port=${options.port} root=${options.root}\n`,
    );
  });
}

main().catch((error) => {
  process.stderr.write(`${error && error.message ? error.message : "Unknown error"}\n`);
  process.exit(1);
});
