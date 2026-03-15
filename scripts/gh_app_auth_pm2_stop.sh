#!/usr/bin/env bash
set -euo pipefail

PM2_APP_NAME="${GH_APP_PM2_APP_NAME:-ai-flow-gh-app-auth}"

if ! command -v pm2 >/dev/null 2>&1; then
  echo "pm2 command is required (install: npm install -g pm2)" >&2
  exit 1
fi

if ! pm2 describe "${PM2_APP_NAME}" >/dev/null 2>&1; then
  echo "PM2 process '${PM2_APP_NAME}' is not registered"
  exit 0
fi

pm2 delete "${PM2_APP_NAME}"
pm2 save --force >/dev/null 2>&1 || true

echo "PM2 process '${PM2_APP_NAME}' stopped and removed"
