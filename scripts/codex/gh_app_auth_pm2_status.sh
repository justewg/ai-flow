#!/usr/bin/env bash
set -euo pipefail

PM2_APP_NAME="${GH_APP_PM2_APP_NAME:-planka-gh-app-auth}"
require_online=0

if [[ "${1:-}" == "--require-online" ]]; then
  require_online=1
fi

if ! command -v pm2 >/dev/null 2>&1; then
  echo "pm2 command is required (install: npm install -g pm2)" >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "node command is required to parse pm2 status output" >&2
  exit 1
fi

pm2_json="$(pm2 jlist)"

if [[ -z "${pm2_json}" ]]; then
  echo "PM2 list is empty" >&2
  exit 1
fi

PM2_APP_NAME="${PM2_APP_NAME}" \
PM2_REQUIRE_ONLINE="${require_online}" \
PM2_LIST_JSON="${pm2_json}" \
node -e '
const appName = String(process.env.PM2_APP_NAME || "");
const requireOnline = String(process.env.PM2_REQUIRE_ONLINE || "0") === "1";
let list = [];
try {
  list = JSON.parse(process.env.PM2_LIST_JSON || "[]");
} catch (_error) {
  process.stderr.write("Failed to parse PM2 status JSON\n");
  process.exit(1);
}

const app = list.find((entry) => entry && entry.name === appName);
if (!app) {
  process.stderr.write(`PM2 process "${appName}" not found\n`);
  process.exit(1);
}

const status = app.pm2_env && typeof app.pm2_env.status === "string" ? app.pm2_env.status : "unknown";
const pid = Number.isInteger(app.pid) ? app.pid : 0;
const restarts =
  app.pm2_env && Number.isInteger(app.pm2_env.restart_time) ? app.pm2_env.restart_time : 0;
const uptimeMs =
  app.pm2_env && Number.isInteger(app.pm2_env.pm_uptime)
    ? Math.max(0, Date.now() - app.pm2_env.pm_uptime)
    : 0;
const uptimeSec = Math.floor(uptimeMs / 1000);

if (requireOnline && status !== "online") {
  process.stderr.write(`PM2 process "${appName}" is not online (status=${status})\n`);
  process.exit(1);
}

process.stdout.write(`PM2_APP=${appName}\n`);
process.stdout.write(`PM2_STATUS=${status}\n`);
process.stdout.write(`PM2_PID=${pid}\n`);
process.stdout.write(`PM2_RESTARTS=${restarts}\n`);
process.stdout.write(`PM2_UPTIME_SEC=${uptimeSec}\n`);
'
