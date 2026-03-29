#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

CODEX_DIR="$(codex_export_state_dir)"
V2_STATE_DIR="${CODEX_DIR}/runtime_v2"
V2_STORE_DIR="${V2_STATE_DIR}/store"
mkdir -p "$V2_STORE_DIR"

if [[ $# -ge 1 ]]; then
  node "${SCRIPT_DIR}/../runtime-v2/bin/runtime_v2_snapshot.js" --store-dir "$V2_STORE_DIR" --task-id "$1"
else
  node "${SCRIPT_DIR}/../runtime-v2/bin/runtime_v2_snapshot.js" --store-dir "$V2_STORE_DIR"
fi
