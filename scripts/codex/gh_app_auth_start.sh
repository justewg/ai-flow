#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

load_env_file() {
  local file_path="$1"
  if [[ -f "$file_path" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$file_path"
    set +a
  fi
}

load_env_file "${ROOT_DIR}/.env"
load_env_file "${ROOT_DIR}/.env.deploy"

if ! command -v node >/dev/null 2>&1; then
  echo "node command is required to run gh_app_auth_service.js" >&2
  exit 1
fi

exec node "${ROOT_DIR}/scripts/codex/gh_app_auth_service.js"
