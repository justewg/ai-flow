#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

CODEX_DIR="$(codex_export_state_dir)"
V2_STATE_DIR="${CODEX_DIR}/runtime_v2"

rm -rf "${V2_STATE_DIR}/store"
mkdir -p "${V2_STATE_DIR}/store"
printf 'RUNTIME_V2_CLEARED=1\n'
