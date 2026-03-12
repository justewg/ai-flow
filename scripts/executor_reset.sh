#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
CODEX_DIR="$(codex_export_state_dir)"
PID_FILE="${CODEX_DIR}/executor_pid.txt"
HEARTBEAT_PID_FILE="${CODEX_DIR}/executor_heartbeat_pid.txt"
COMMIT_FILE="${CODEX_DIR}/commit_message.txt"
PR_BODY_FILE="${CODEX_DIR}/pr_body.txt"
PR_NUMBER_FILE="${CODEX_DIR}/pr_number.txt"
PR_TITLE_FILE="${CODEX_DIR}/pr_title.txt"
STAGE_PATHS_FILE="${CODEX_DIR}/stage_paths.txt"

mkdir -p "$CODEX_DIR"

kill_pid_gracefully() {
  local pid="$1"
  [[ -z "$pid" || ! "$pid" =~ ^[0-9]+$ ]] && return 0
  if ! kill -0 "$pid" 2>/dev/null; then
    return 0
  fi
  kill "$pid" 2>/dev/null || true
  sleep 1
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null || true
  fi
}

existing_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
if [[ "$existing_pid" =~ ^[0-9]+$ ]] && kill -0 "$existing_pid" 2>/dev/null; then
  child_pids="$(ps -axo pid=,ppid= 2>/dev/null | awk -v p="$existing_pid" '$2==p { print $1 }' || true)"
  if [[ -n "$child_pids" ]]; then
    while IFS= read -r child_pid; do
      kill_pid_gracefully "$child_pid"
    done <<<"$child_pids"
  fi
  kill_pid_gracefully "$existing_pid"
  echo "EXECUTOR_RESET_KILLED_PID=$existing_pid"
fi

heartbeat_pid="$(cat "$HEARTBEAT_PID_FILE" 2>/dev/null || true)"
kill_pid_gracefully "$heartbeat_pid"

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
: > "${CODEX_DIR}/executor_done_wait_notified_task.txt"
: > "${CODEX_DIR}/executor_heartbeat_utc.txt"
: > "${CODEX_DIR}/executor_heartbeat_epoch.txt"
: > "$HEARTBEAT_PID_FILE"
: > "$COMMIT_FILE"
: > "$PR_BODY_FILE"
: > "$PR_NUMBER_FILE"
: > "$PR_TITLE_FILE"
: > "$STAGE_PATHS_FILE"

echo "EXECUTOR_RESET=1"
