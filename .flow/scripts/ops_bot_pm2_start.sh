#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=./env/resolve_config.sh
source "${ROOT_DIR}/.flow/scripts/env/resolve_config.sh"
codex_load_flow_env
PM2_LOG_DIR="$(codex_resolve_flow_pm2_log_dir)"
PM2_APP_NAME="${OPS_BOT_PM2_APP_NAME:-planka-ops-bot}"
PM2_ECOSYSTEM_FILE="${ROOT_DIR}/.flow/scripts/ops_bot_pm2_ecosystem.config.cjs"

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

"${ROOT_DIR}/.flow/scripts/ops_bot_pm2_status.sh" --require-online
