#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

CODEX_DIR="$(codex_export_state_dir)"
STORE_DIR="${CODEX_DIR}/runtime_v2/store"
REPORT_FILE="${CODEX_DIR}/runtime_v2_validation_report.json"
repo="${FLOW_GITHUB_REPO:-unknown/repo}"
task_id="${1:-PL-104-VALIDATION}"
issue_number="${2:-104}"
NODE_BIN="${NODE_BIN:-node}"
if [[ $# -ge 1 ]]; then
  shift 1
fi
if [[ $# -ge 1 ]]; then
  shift 1
fi

mkdir -p "$STORE_DIR"

exec "$NODE_BIN" "${SCRIPT_DIR}/../runtime-v2/bin/runtime_v2_validate_rollout.js" \
  --legacy-state-dir "$CODEX_DIR" \
  --store-dir "$STORE_DIR" \
  --repo "$repo" \
  --task-id "$task_id" \
  --issue-number "$issue_number" \
  --output-file "$REPORT_FILE" \
  "$@"
