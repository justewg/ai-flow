#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CODEX_DIR="${ROOT_DIR}/.tmp/codex"

mkdir -p "$CODEX_DIR"

: > "${CODEX_DIR}/executor_state.txt"
: > "${CODEX_DIR}/executor_pid.txt"
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
