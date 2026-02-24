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

bind="${GH_APP_BIND:-127.0.0.1}"
port="${GH_APP_PORT:-8787}"
url="http://${bind}:${port}/health"

curl -fsS "$url"
printf '\n'
