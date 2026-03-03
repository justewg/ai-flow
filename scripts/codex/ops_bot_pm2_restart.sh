#!/usr/bin/env bash
set -euo pipefail

PM2_APP_NAME="${OPS_BOT_PM2_APP_NAME:-planka-ops-bot}"

if ! command -v pm2 >/dev/null 2>&1; then
  echo "pm2 command is required (install: npm install -g pm2)" >&2
  exit 1
fi

if ! pm2 describe "${PM2_APP_NAME}" >/dev/null 2>&1; then
  echo "PM2 process '${PM2_APP_NAME}' is not registered; use ops_bot_pm2_start first" >&2
  exit 1
fi

pm2 restart "${PM2_APP_NAME}" --update-env
