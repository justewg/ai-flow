#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
codex_load_flow_env

if ! command -v node >/dev/null 2>&1; then
  echo "node command is required to run ops_bot_service.js" >&2
  exit 1
fi

exec node "${CODEX_SHARED_SCRIPTS_DIR}/ops_bot_service.js"
