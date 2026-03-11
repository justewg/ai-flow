#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=./env/resolve_config.sh
source "${ROOT_DIR}/.flow/scripts/env/resolve_config.sh"
codex_load_flow_env

bind="${OPS_BOT_BIND:-127.0.0.1}"
port="${OPS_BOT_PORT:-8790}"

curl -fsS "http://${bind}:${port}/health"
printf '\n'
