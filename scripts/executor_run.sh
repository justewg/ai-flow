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
# shellcheck source=./task_worktree_lib.sh
source "${SCRIPT_DIR}/task_worktree_lib.sh"
codex_load_flow_env
CODEX_DIR="$(codex_export_state_dir)"
RUNTIME_LOG_DIR="$(codex_resolve_flow_runtime_log_dir)"
LOG_FILE="${RUNTIME_LOG_DIR}/executor.log"
PROMPT_FILE="${CODEX_DIR}/executor_prompt.txt"
STATE_FILE="${CODEX_DIR}/executor_state.txt"
EXIT_FILE="${CODEX_DIR}/executor_last_exit_code.txt"
FINISH_FILE="${CODEX_DIR}/executor_last_finished_utc.txt"
LAST_MSG_FILE="${CODEX_DIR}/executor_last_message.txt"
HEARTBEAT_FILE="${CODEX_DIR}/executor_heartbeat_utc.txt"
HEARTBEAT_EPOCH_FILE="${CODEX_DIR}/executor_heartbeat_epoch.txt"
HEARTBEAT_PID_FILE="${CODEX_DIR}/executor_heartbeat_pid.txt"
DETACH_FILE="${CODEX_DIR}/executor_detach_requested.txt"

mkdir -p "$CODEX_DIR" "$RUNTIME_LOG_DIR"
: > "$DETACH_FILE"

task_repo="$(task_worktree_repo_dir "$task_id" "$issue_number")"
emit_log_lines() {
  local text="$1"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "$line"
  done <<< "$text"
}

recover_task_worktree_if_missing() {
  local out=""

  if task_worktree_repo_ready "$task_repo"; then
    return 0
  fi

  {
    echo "EXECUTOR_TASK_WORKTREE_MISSING=1"
    echo "EXECUTOR_TASK_WORKTREE_PATH=${task_repo}"
  } >>"$LOG_FILE" 2>&1

  if out="$("${CODEX_SHARED_SCRIPTS_DIR}/task_worktree_materialize.sh" "$task_id" "$issue_number" 2>&1)"; then
    emit_log_lines "$out" >>"$LOG_FILE" 2>&1
    if task_worktree_repo_ready "$task_repo"; then
      {
        echo "EXECUTOR_TASK_WORKTREE_RECOVERED=1"
        echo "EXECUTOR_TASK_WORKTREE_PATH=${task_repo}"
      } >>"$LOG_FILE" 2>&1
      return 0
    fi
  else
    emit_log_lines "$out" >>"$LOG_FILE" 2>&1
  fi

  {
    echo "EXECUTOR_TASK_WORKTREE_RECOVER_FAILED=1"
    echo "EXECUTOR_TASK_WORKTREE_PATH=${task_repo}"
    echo "=== EXECUTOR_RUN_FINISH task=${task_id} issue=${issue_number} rc=1 at $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
  } >>"$LOG_FILE" 2>&1
  printf '%s\n' "FAILED" > "$STATE_FILE"
  printf '%s\n' "1" > "$EXIT_FILE"
  date -u '+%Y-%m-%dT%H:%M:%SZ' > "$FINISH_FILE"
  : > "${CODEX_DIR}/executor_pid.txt"
  exit 0
}

if ! task_worktree_repo_ready "$task_repo"; then
  recover_task_worktree_if_missing
fi

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

touch_heartbeat() {
  date -u '+%Y-%m-%dT%H:%M:%SZ' > "$HEARTBEAT_FILE"
  date +%s > "$HEARTBEAT_EPOCH_FILE"
}

{
  echo "=== EXECUTOR_RUN_START task=${task_id} issue=${issue_number} at $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
  "${CODEX_SHARED_SCRIPTS_DIR}/executor_build_prompt.sh" "$task_id" "$issue_number" "$PROMPT_FILE"
} >>"$LOG_FILE" 2>&1

touch_heartbeat

heartbeat_sec="${EXECUTOR_HEARTBEAT_SEC:-8}"
if ! [[ "$heartbeat_sec" =~ ^[0-9]+$ ]] || (( heartbeat_sec < 3 )); then
  heartbeat_sec=8
fi

codex_args=(codex exec -C "$task_repo" --output-last-message "$LAST_MSG_FILE")
executor_mode="full-auto"
if is_truthy "${EXECUTOR_CODEX_BYPASS_SANDBOX:-0}"; then
  codex_args+=(--dangerously-bypass-approvals-and-sandbox)
  executor_mode="danger-full-access"
else
  codex_args+=(--full-auto)
fi

{
  echo "EXECUTOR_CODEX_MODE=${executor_mode}"
  echo "EXECUTOR_CODEX_BYPASS_SANDBOX=${EXECUTOR_CODEX_BYPASS_SANDBOX:-0}"
  echo "EXECUTOR_TASK_WORKTREE_PATH=${task_repo}"
} >>"$LOG_FILE" 2>&1

"${codex_args[@]}" - < "$PROMPT_FILE" >>"$LOG_FILE" 2>&1 &
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
else
  rc=$?
fi

kill "$heartbeat_pid" 2>/dev/null || true
wait "$heartbeat_pid" 2>/dev/null || true
touch_heartbeat

detach_requested="0"
if [[ -s "$DETACH_FILE" ]]; then
  detach_requested="1"
fi

if [[ "$detach_requested" == "1" ]]; then
  : > "${CODEX_DIR}/executor_pid.txt"
  : > "$HEARTBEAT_PID_FILE"
  : > "$DETACH_FILE"
  {
    echo "EXECUTOR_RUN_DETACHED=1"
    echo "=== EXECUTOR_RUN_FINISH task=${task_id} issue=${issue_number} rc=${rc} detached=1 at $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
  } >>"$LOG_FILE" 2>&1
  exit 0
fi

if [[ "$rc" == "0" ]]; then
  printf '%s\n' "DONE" > "$STATE_FILE"
else
  printf '%s\n' "FAILED" > "$STATE_FILE"
fi

printf '%s\n' "$rc" > "$EXIT_FILE"
date -u '+%Y-%m-%dT%H:%M:%SZ' > "$FINISH_FILE"
: > "${CODEX_DIR}/executor_pid.txt"
: > "$HEARTBEAT_PID_FILE"
: > "$DETACH_FILE"

{
  echo "=== EXECUTOR_RUN_FINISH task=${task_id} issue=${issue_number} rc=${rc} at $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
} >>"$LOG_FILE" 2>&1

exit 0
