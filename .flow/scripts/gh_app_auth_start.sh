#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=./env/resolve_config.sh
source "${ROOT_DIR}/.flow/scripts/env/resolve_config.sh"
codex_load_flow_env

if ! command -v node >/dev/null 2>&1; then
  echo "node command is required to run gh_app_auth_service.js" >&2
  exit 1
fi

exec node "${ROOT_DIR}/.flow/scripts/gh_app_auth_service.js"
