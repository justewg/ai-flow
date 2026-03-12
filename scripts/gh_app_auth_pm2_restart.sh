#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
codex_load_flow_env
FLOW_LOGS_DIR="$(codex_resolve_flow_logs_dir)"
FLOW_PM2_LOG_DIR="$(codex_resolve_flow_pm2_log_dir)"
export FLOW_LOGS_DIR FLOW_PM2_LOG_DIR
PM2_APP_NAME="${GH_APP_PM2_APP_NAME:-planka-gh-app-auth}"

if ! command -v pm2 >/dev/null 2>&1; then
  echo "pm2 command is required (install: npm install -g pm2)" >&2
  exit 1
fi

if ! pm2 describe "${PM2_APP_NAME}" >/dev/null 2>&1; then
  echo "PM2 process '${PM2_APP_NAME}' is not registered; use gh_app_auth_pm2_start first" >&2
  exit 1
fi

pm2 restart "${PM2_APP_NAME}" --update-env
