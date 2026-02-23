#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <task-id> <issue-number>"
  exit 1
fi

task_id="$1"
issue_number="$2"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CODEX_DIR="${ROOT_DIR}/.tmp/codex"
LOG_FILE="${CODEX_DIR}/executor.log"
PROMPT_FILE="${CODEX_DIR}/executor_prompt.txt"
STATE_FILE="${CODEX_DIR}/executor_state.txt"
EXIT_FILE="${CODEX_DIR}/executor_last_exit_code.txt"
FINISH_FILE="${CODEX_DIR}/executor_last_finished_utc.txt"
LAST_MSG_FILE="${CODEX_DIR}/executor_last_message.txt"

mkdir -p "$CODEX_DIR"

{
  echo "=== EXECUTOR_RUN_START task=${task_id} issue=${issue_number} at $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
  "${ROOT_DIR}/scripts/codex/executor_build_prompt.sh" "$task_id" "$issue_number" "$PROMPT_FILE"
} >>"$LOG_FILE" 2>&1

rc=0
if codex exec --full-auto -C "$ROOT_DIR" --output-last-message "$LAST_MSG_FILE" - < "$PROMPT_FILE" >>"$LOG_FILE" 2>&1; then
  rc=0
  printf '%s\n' "DONE" > "$STATE_FILE"
else
  rc=$?
  printf '%s\n' "FAILED" > "$STATE_FILE"
fi

printf '%s\n' "$rc" > "$EXIT_FILE"
date -u '+%Y-%m-%dT%H:%M:%SZ' > "$FINISH_FILE"
: > "${CODEX_DIR}/executor_pid.txt"

{
  echo "=== EXECUTOR_RUN_FINISH task=${task_id} issue=${issue_number} rc=${rc} at $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
} >>"$LOG_FILE" 2>&1

exit 0
