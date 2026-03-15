#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
codex_load_flow_env
FLOW_LOGS_DIR="$(codex_resolve_flow_logs_dir)"
PM2_LOG_DIR="$(codex_resolve_flow_pm2_log_dir)"
FLOW_PM2_LOG_DIR="${PM2_LOG_DIR}"
export FLOW_LOGS_DIR FLOW_PM2_LOG_DIR
PM2_APP_NAME="${GH_APP_PM2_APP_NAME:-ai-flow-gh-app-auth}"
PM2_ECOSYSTEM_FILE="${CODEX_SHARED_SCRIPTS_DIR}/gh_app_auth_pm2_ecosystem.config.cjs"

if ! command -v pm2 >/dev/null 2>&1; then
  echo "pm2 command is required (install: npm install -g pm2)" >&2
  exit 1
fi

mkdir -p "${PM2_LOG_DIR}"

if pm2 describe "${PM2_APP_NAME}" >/dev/null 2>&1; then
  pm2 restart "${PM2_APP_NAME}" --update-env
else
  pm2 start "${PM2_ECOSYSTEM_FILE}" --only "${PM2_APP_NAME}" --update-env
fi

pm2 save --force >/dev/null 2>&1 || true

"${CODEX_SHARED_SCRIPTS_DIR}/gh_app_auth_pm2_status.sh" --require-online
