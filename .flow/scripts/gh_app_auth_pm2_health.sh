#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

"${ROOT_DIR}/.flow/scripts/gh_app_auth_pm2_status.sh" --require-online
"${ROOT_DIR}/.flow/scripts/gh_app_auth_health.sh"
