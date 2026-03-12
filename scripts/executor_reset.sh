#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
CODEX_DIR="$(codex_export_state_dir)"
PID_FILE="${CODEX_DIR}/executor_pid.txt"
HEARTBEAT_PID_FILE="${CODEX_DIR}/executor_heartbeat_pid.txt"
DETACH_FILE="${CODEX_DIR}/executor_detach_requested.txt"
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

is_truthy() {
  local raw_value="${1:-}"
  local value
  value="$(printf '%s' "$raw_value" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    1|true|yes|on)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

pid_is_descendant_of() {
  local ancestor_pid="$1"
  local candidate_pid="$2"
  local parent_pid=""

  [[ "$ancestor_pid" =~ ^[0-9]+$ ]] || return 1
  [[ "$candidate_pid" =~ ^[0-9]+$ ]] || return 1

  while [[ "$candidate_pid" =~ ^[0-9]+$ ]] && [[ "$candidate_pid" != "1" ]]; do
    if [[ "$candidate_pid" == "$ancestor_pid" ]]; then
      return 0
    fi
    parent_pid="$(ps -o ppid= -p "$candidate_pid" 2>/dev/null | tr -d '[:space:]' || true)"
    [[ "$parent_pid" =~ ^[0-9]+$ ]] || return 1
    candidate_pid="$parent_pid"
  done

  return 1
}

existing_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
preserve_pid="${EXECUTOR_RESET_PRESERVE_PID:-}"
preserve_current_tree="0"
if is_truthy "${EXECUTOR_RESET_PRESERVE_CURRENT:-0}" &&
  [[ "$existing_pid" =~ ^[0-9]+$ ]] &&
  kill -0 "$existing_pid" 2>/dev/null &&
  { [[ "$preserve_pid" == "$existing_pid" ]] || pid_is_descendant_of "$existing_pid" "$$"; }; then
  preserve_current_tree="1"
  printf '%s\n' "preserve-current-tree" > "$DETACH_FILE"
  echo "EXECUTOR_RESET_PRESERVED_CURRENT_TREE=1"
  echo "EXECUTOR_RESET_PRESERVED_OWNER_PID=$existing_pid"
fi

if [[ "$preserve_current_tree" != "1" ]] &&
  [[ "$existing_pid" =~ ^[0-9]+$ ]] &&
  kill -0 "$existing_pid" 2>/dev/null; then
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
if [[ "$preserve_current_tree" != "1" ]]; then
  kill_pid_gracefully "$heartbeat_pid"
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
if [[ "$preserve_current_tree" != "1" ]]; then
  : > "$DETACH_FILE"
fi
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
