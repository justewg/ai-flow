#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=./env/resolve_config.sh
source "${ROOT_DIR}/.flow/scripts/env/resolve_config.sh"
codex_load_flow_env

bind="${GH_APP_BIND:-127.0.0.1}"
port="${GH_APP_PORT:-8787}"
url="http://${bind}:${port}/health"

curl -fsS "$url"
printf '\n'
