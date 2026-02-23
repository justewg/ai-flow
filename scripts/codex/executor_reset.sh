#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CODEX_DIR="${ROOT_DIR}/.tmp/codex"
PID_FILE="${CODEX_DIR}/executor_pid.txt"

mkdir -p "$CODEX_DIR"

existing_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
if [[ "$existing_pid" =~ ^[0-9]+$ ]] && kill -0 "$existing_pid" 2>/dev/null; then
  kill "$existing_pid" 2>/dev/null || true
  sleep 1
  if kill -0 "$existing_pid" 2>/dev/null; then
    kill -9 "$existing_pid" 2>/dev/null || true
  fi
  echo "EXECUTOR_RESET_KILLED_PID=$existing_pid"
fi

: > "${CODEX_DIR}/executor_state.txt"
: > "$PID_FILE"
: > "${CODEX_DIR}/executor_task_id.txt"
: > "${CODEX_DIR}/executor_issue_number.txt"
: > "${CODEX_DIR}/executor_last_exit_code.txt"
: > "${CODEX_DIR}/executor_last_started_utc.txt"
: > "${CODEX_DIR}/executor_last_finished_utc.txt"
: > "${CODEX_DIR}/executor_last_start_epoch.txt"
: > "${CODEX_DIR}/executor_last_message.txt"
: > "${CODEX_DIR}/executor_prompt.txt"
: > "${CODEX_DIR}/executor_failure_notified_task.txt"

echo "EXECUTOR_RESET=1"
