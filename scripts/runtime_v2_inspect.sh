#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

CODEX_DIR="$(codex_export_state_dir)"
STORE_DIR="${CODEX_DIR}/runtime_v2/store"
NODE_BIN="${NODE_BIN:-node}"

exec "$NODE_BIN" "${SCRIPT_DIR}/../runtime-v2/bin/runtime_v2_inspect.js" \
  --legacy-state-dir "$CODEX_DIR" \
  --store-dir "$STORE_DIR" \
  "$@"
