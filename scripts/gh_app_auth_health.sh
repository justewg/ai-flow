#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
codex_load_flow_env

bind="${GH_APP_BIND:-127.0.0.1}"
port="${GH_APP_PORT:-8787}"
url="http://${bind}:${port}/health"

curl -fsS "$url"
printf '\n'
