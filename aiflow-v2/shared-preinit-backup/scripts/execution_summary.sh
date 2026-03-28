#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

CODEX_DIR="$(codex_export_state_dir)"
SUMMARY_FILE="${CODEX_DIR}/execution_summary.json"

task_id="${1:-}"

if [[ ! -s "$SUMMARY_FILE" ]]; then
  echo "{}"
  exit 0
fi

if [[ -n "$task_id" ]]; then
  jq --arg task "$task_id" '{($task): (.[$task] // null)}' "$SUMMARY_FILE"
  exit 0
fi

jq '.' "$SUMMARY_FILE"
