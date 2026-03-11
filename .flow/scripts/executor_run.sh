#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <task-id> <issue-number>"
  exit 1
fi

task_id="$1"
issue_number="$2"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=./env/resolve_config.sh
source "${ROOT_DIR}/.flow/scripts/env/resolve_config.sh"
CODEX_DIR="$(codex_export_state_dir)"
LOG_FILE="${CODEX_DIR}/executor.log"
PROMPT_FILE="${CODEX_DIR}/executor_prompt.txt"
STATE_FILE="${CODEX_DIR}/executor_state.txt"
EXIT_FILE="${CODEX_DIR}/executor_last_exit_code.txt"
FINISH_FILE="${CODEX_DIR}/executor_last_finished_utc.txt"
LAST_MSG_FILE="${CODEX_DIR}/executor_last_message.txt"
HEARTBEAT_FILE="${CODEX_DIR}/executor_heartbeat_utc.txt"
HEARTBEAT_EPOCH_FILE="${CODEX_DIR}/executor_heartbeat_epoch.txt"
HEARTBEAT_PID_FILE="${CODEX_DIR}/executor_heartbeat_pid.txt"

mkdir -p "$CODEX_DIR"

touch_heartbeat() {
  date -u '+%Y-%m-%dT%H:%M:%SZ' > "$HEARTBEAT_FILE"
  date +%s > "$HEARTBEAT_EPOCH_FILE"
}

{
  echo "=== EXECUTOR_RUN_START task=${task_id} issue=${issue_number} at $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
  "${ROOT_DIR}/.flow/scripts/executor_build_prompt.sh" "$task_id" "$issue_number" "$PROMPT_FILE"
} >>"$LOG_FILE" 2>&1

touch_heartbeat

heartbeat_sec="${EXECUTOR_HEARTBEAT_SEC:-8}"
if ! [[ "$heartbeat_sec" =~ ^[0-9]+$ ]] || (( heartbeat_sec < 3 )); then
  heartbeat_sec=8
fi

codex exec --full-auto -C "$ROOT_DIR" --output-last-message "$LAST_MSG_FILE" - < "$PROMPT_FILE" >>"$LOG_FILE" 2>&1 &
codex_pid="$!"

(
  while kill -0 "$codex_pid" 2>/dev/null; do
    touch_heartbeat
    sleep "$heartbeat_sec"
  done
) &
heartbeat_pid="$!"
printf '%s\n' "$heartbeat_pid" > "$HEARTBEAT_PID_FILE"

rc=0
if wait "$codex_pid"; then
  rc=0
  printf '%s\n' "DONE" > "$STATE_FILE"
else
  rc=$?
  printf '%s\n' "FAILED" > "$STATE_FILE"
fi

kill "$heartbeat_pid" 2>/dev/null || true
wait "$heartbeat_pid" 2>/dev/null || true
touch_heartbeat

printf '%s\n' "$rc" > "$EXIT_FILE"
date -u '+%Y-%m-%dT%H:%M:%SZ' > "$FINISH_FILE"
: > "${CODEX_DIR}/executor_pid.txt"
: > "$HEARTBEAT_PID_FILE"

{
  echo "=== EXECUTOR_RUN_FINISH task=${task_id} issue=${issue_number} rc=${rc} at $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
} >>"$LOG_FILE" 2>&1

exit 0
