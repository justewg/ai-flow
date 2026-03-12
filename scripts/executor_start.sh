#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <task-id> <issue-number>"
  exit 1
fi

task_id="$1"
issue_number="$2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
CODEX_DIR="$(codex_export_state_dir)"
RUNTIME_LOG_DIR="$(codex_resolve_flow_runtime_log_dir)"

STATE_FILE="${CODEX_DIR}/executor_state.txt"
PID_FILE="${CODEX_DIR}/executor_pid.txt"
TASK_FILE="${CODEX_DIR}/executor_task_id.txt"
ISSUE_FILE="${CODEX_DIR}/executor_issue_number.txt"
START_FILE="${CODEX_DIR}/executor_last_started_utc.txt"
START_EPOCH_FILE="${CODEX_DIR}/executor_last_start_epoch.txt"
LOG_FILE="${RUNTIME_LOG_DIR}/executor.log"
HEARTBEAT_FILE="${CODEX_DIR}/executor_heartbeat_utc.txt"
HEARTBEAT_EPOCH_FILE="${CODEX_DIR}/executor_heartbeat_epoch.txt"
HEARTBEAT_PID_FILE="${CODEX_DIR}/executor_heartbeat_pid.txt"

mkdir -p "$CODEX_DIR" "$RUNTIME_LOG_DIR"

if ! command -v codex >/dev/null 2>&1; then
  printf '%s\n' "FAILED" > "$STATE_FILE"
  printf '%s\n' "127" > "${CODEX_DIR}/executor_last_exit_code.txt"
  echo "EXECUTOR_START_FAILED=codex_cli_not_found"
  exit 0
fi

current_state="$(cat "$STATE_FILE" 2>/dev/null || true)"
current_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
current_task="$(cat "$TASK_FILE" 2>/dev/null || true)"

case "$current_state" in
  EXECUTOR_RUNNING) current_state="RUNNING" ;;
  EXECUTOR_DONE) current_state="DONE" ;;
  EXECUTOR_FAILED) current_state="FAILED" ;;
esac

if [[ "$current_state" == "RUNNING" && -n "$current_pid" ]] && kill -0 "$current_pid" 2>/dev/null; then
  echo "EXECUTOR_ALREADY_RUNNING=1"
  echo "EXECUTOR_PID=$current_pid"
  echo "EXECUTOR_TASK_ID=$current_task"
  exit 0
fi

printf '%s\n' "RUNNING" > "$STATE_FILE"
printf '%s\n' "$task_id" > "$TASK_FILE"
printf '%s\n' "$issue_number" > "$ISSUE_FILE"
date -u '+%Y-%m-%dT%H:%M:%SZ' > "$START_FILE"
date +%s > "$START_EPOCH_FILE"
date -u '+%Y-%m-%dT%H:%M:%SZ' > "$HEARTBEAT_FILE"
date +%s > "$HEARTBEAT_EPOCH_FILE"
: > "$HEARTBEAT_PID_FILE"

/bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/executor_run.sh" "$task_id" "$issue_number" >>"$LOG_FILE" 2>&1 &
pid="$!"
printf '%s\n' "$pid" > "$PID_FILE"

echo "EXECUTOR_STARTED=1"
echo "EXECUTOR_PID=$pid"
echo "EXECUTOR_TASK_ID=$task_id"
echo "EXECUTOR_ISSUE_NUMBER=$issue_number"
