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

bind="${OPS_BOT_BIND:-127.0.0.1}"
port="${OPS_BOT_PORT:-8790}"

curl -fsS "http://${bind}:${port}/health"
printf '\n'
