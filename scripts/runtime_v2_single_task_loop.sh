#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

CODEX_DIR="$(codex_export_state_dir)"
STORE_DIR="${CODEX_DIR}/runtime_v2/store"
REPORT_FILE="${CODEX_DIR}/runtime_v2_single_task_loop_report.json"
repo="${FLOW_GITHUB_REPO:-unknown/repo}"
task_id="${1:-PL-105-LOOP}"
issue_number="${2:-105}"
pr_number="${3:-1050}"
NODE_BIN="${NODE_BIN:-node}"
if [[ $# -ge 1 ]]; then
  shift 1
fi
if [[ $# -ge 1 ]]; then
  shift 1
fi
if [[ $# -ge 1 ]]; then
  shift 1
fi

mkdir -p "$STORE_DIR"

exec "$NODE_BIN" "${SCRIPT_DIR}/../runtime-v2/bin/runtime_v2_single_task_loop.js" \
  --legacy-state-dir "$CODEX_DIR" \
  --store-dir "$STORE_DIR" \
  --repo "$repo" \
  --task-id "$task_id" \
  --issue-number "$issue_number" \
  --pr-number "$pr_number" \
  --output-file "$REPORT_FILE" \
  "$@"
