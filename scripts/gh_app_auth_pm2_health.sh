#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

"${CODEX_SHARED_SCRIPTS_DIR}/gh_app_auth_pm2_status.sh" --require-online
"${CODEX_SHARED_SCRIPTS_DIR}/gh_app_auth_health.sh"
