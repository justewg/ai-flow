#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

"${CODEX_SHARED_SCRIPTS_DIR}/ops_bot_pm2_status.sh" --require-online
"${CODEX_SHARED_SCRIPTS_DIR}/ops_bot_health.sh"
