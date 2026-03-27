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
CODEX_DIR="$(codex_export_state_dir)"
STATE_TMP_DIR="$(codex_resolve_state_tmp_dir "$CODEX_DIR")"
mkdir -p "$STATE_TMP_DIR"
RUNTIME_LOG_DIR="$(codex_resolve_flow_runtime_log_dir)"

STATE_FILE="${CODEX_DIR}/executor_state.txt"
PID_FILE="${CODEX_DIR}/executor_pid.txt"
TASK_FILE="${CODEX_DIR}/executor_task_id.txt"
ISSUE_FILE="${CODEX_DIR}/executor_issue_number.txt"
EXIT_FILE="${CODEX_DIR}/executor_last_exit_code.txt"
FAIL_NOTIFY_FILE="${CODEX_DIR}/executor_failure_notified_task.txt"
DONE_NOTIFY_FILE="${CODEX_DIR}/executor_done_wait_notified_task.txt"
RETRY_REPLY_FILE="${CODEX_DIR}/executor_last_retry_reply_comment_id.txt"
AUTO_RECOVER_FILE="${CODEX_DIR}/executor_auto_recover_key.txt"

mkdir -p "$CODEX_DIR"

emit_nonempty_lines() {
  local text="$1"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "$line"
  done <<< "$text"
}

latest_executor_log_tail() {
  tail -n 80 "${RUNTIME_LOG_DIR}/executor.log" 2>/dev/null || true
}

last_failure_is_missing_task_worktree() {
  local tail_text="$1"
  printf '%s' "$tail_text" | grep -q '^EXECUTOR_TASK_WORKTREE_MISSING=1'
}

runtime_status_out="$("${CODEX_SHARED_SCRIPTS_DIR}/project_status_runtime.sh" apply 3 2>&1 || true)"
if [[ -n "$runtime_status_out" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == "RUNTIME_PROJECT_STATUS_QUEUE_ABSENT=1" ]] && continue
    echo "$line"
  done <<< "$runtime_status_out"
fi

is_waiting_user="0"
if [[ -s "${CODEX_DIR}/daemon_waiting_issue_number.txt" ]]; then
  is_waiting_user="1"
fi

state="$(cat "$STATE_FILE" 2>/dev/null || true)"
exec_task="$(cat "$TASK_FILE" 2>/dev/null || true)"
exec_issue="$(cat "$ISSUE_FILE" 2>/dev/null || true)"
pid="$(cat "$PID_FILE" 2>/dev/null || true)"
last_rc="$(cat "$EXIT_FILE" 2>/dev/null || true)"
reply_task="$(cat "${CODEX_DIR}/daemon_user_reply_task_id.txt" 2>/dev/null || true)"
reply_issue="$(cat "${CODEX_DIR}/daemon_user_reply_issue_number.txt" 2>/dev/null || true)"
reply_comment_id="$(cat "${CODEX_DIR}/daemon_user_reply_comment_id.txt" 2>/dev/null || true)"
last_retry_reply_id="$(cat "$RETRY_REPLY_FILE" 2>/dev/null || true)"

if [[ -n "$exec_task" && "$exec_task" != "$task_id" ]]; then
  "${CODEX_SHARED_SCRIPTS_DIR}/executor_reset.sh" >/dev/null
  : > "$DONE_NOTIFY_FILE"
  state=""
  exec_task=""
  exec_issue=""
  pid=""
  last_rc=""
fi

if [[ "$state" == "RUNNING" ]]; then
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    echo "EXECUTOR_RUNNING=1"
    echo "EXECUTOR_PID=$pid"
    echo "EXECUTOR_TASK_ID=$task_id"
    exit 0
  fi

  # Процесс уже завершился, но RUNNING не был обновлен.
  if [[ -n "$last_rc" ]]; then
    if [[ "$last_rc" == "0" ]]; then
      state="DONE"
    else
      state="FAILED"
    fi
  else
    state="FAILED"
    last_rc="unknown"
  fi
  printf '%s\n' "$state" > "$STATE_FILE"
  : > "$PID_FILE"
fi

if [[ "$state" == "FAILED" ]]; then
  latest_log_tail="$(latest_executor_log_tail)"
  auto_recover_key="missing-worktree:${task_id}:${issue_number}"
  last_auto_recover_key="$(cat "$AUTO_RECOVER_FILE" 2>/dev/null || true)"

  # После нового ответа пользователя даем executor одну новую попытку.
  if [[ "$is_waiting_user" != "1" && "$reply_task" == "$task_id" && "$reply_issue" == "$issue_number" &&
    -n "$reply_comment_id" && "$reply_comment_id" != "$last_retry_reply_id" ]]; then
    printf '%s\n' "$reply_comment_id" > "$RETRY_REPLY_FILE"
    "${CODEX_SHARED_SCRIPTS_DIR}/executor_reset.sh" >/dev/null
    : > "$DONE_NOTIFY_FILE"
    : > "$FAIL_NOTIFY_FILE"
    echo "EXECUTOR_RETRY_AFTER_USER_REPLY=1"
    echo "EXECUTOR_RETRY_REPLY_COMMENT_ID=$reply_comment_id"
    state=""
  elif [[ "$is_waiting_user" != "1" ]] &&
    last_failure_is_missing_task_worktree "$latest_log_tail" &&
    [[ "$last_auto_recover_key" != "$auto_recover_key" ]]; then
    printf '%s\n' "$auto_recover_key" > "$AUTO_RECOVER_FILE"
    if recover_out="$("${CODEX_SHARED_SCRIPTS_DIR}/task_worktree_materialize.sh" "$task_id" "$issue_number" 2>&1)"; then
      echo "EXECUTOR_AUTO_RECOVERED_MISSING_TASK_WORKTREE=1"
      emit_nonempty_lines "$recover_out"
      "${CODEX_SHARED_SCRIPTS_DIR}/executor_reset.sh" >/dev/null
      printf '%s\n' "$auto_recover_key" > "$AUTO_RECOVER_FILE"
      : > "$DONE_NOTIFY_FILE"
      : > "$FAIL_NOTIFY_FILE"
      start_out="$("${CODEX_SHARED_SCRIPTS_DIR}/executor_start.sh" "$task_id" "$issue_number" 2>&1)"
      emit_nonempty_lines "$start_out"
      exit 0
    else
      rc=$?
      echo "EXECUTOR_AUTO_RECOVER_MISSING_TASK_WORKTREE_FAILED=1"
      echo "EXECUTOR_AUTO_RECOVER_FAILURE_RC=$rc"
      emit_nonempty_lines "$recover_out"
      exit 0
    fi
  else
    echo "EXECUTOR_FAILED=1"
    echo "EXECUTOR_TASK_ID=$task_id"
    echo "EXECUTOR_EXIT_CODE=${last_rc:-unknown}"

    notified_task="$(cat "$FAIL_NOTIFY_FILE" 2>/dev/null || true)"
    if [[ "$notified_task" != "$task_id" && "$is_waiting_user" != "1" ]]; then
      echo "EXECUTOR_FAILURE_USER_REPLY_SUPPRESSED=1"
      echo "EXECUTOR_FAILURE_ACTION=INTERNAL_RECOVERY_OR_MANUAL_INSPECTION"
      printf '%s\n' "$task_id" > "$FAIL_NOTIFY_FILE"
    fi
    exit 0
  fi
fi

if [[ "$state" == "DONE" ]]; then
  if [[ "$is_waiting_user" != "1" && "$reply_task" == "$task_id" && "$reply_issue" == "$issue_number" &&
    -n "$reply_comment_id" && "$reply_comment_id" != "$last_retry_reply_id" ]]; then
    printf '%s\n' "$reply_comment_id" > "$RETRY_REPLY_FILE"
    "${CODEX_SHARED_SCRIPTS_DIR}/executor_reset.sh" >/dev/null
    : > "$DONE_NOTIFY_FILE"
    : > "$FAIL_NOTIFY_FILE"
    echo "EXECUTOR_RETRY_AFTER_USER_REPLY=1"
    echo "EXECUTOR_RETRY_REPLY_COMMENT_ID=$reply_comment_id"
    state=""
  fi

  if [[ "$state" == "DONE" ]]; then
    echo "EXECUTOR_DONE=1"
    echo "EXECUTOR_TASK_ID=$task_id"
    if [[ "$is_waiting_user" == "1" ]]; then
      echo "EXECUTOR_WAIT_USER_REPLY=1"
      exit 0
    fi
    notified_task="$(cat "$DONE_NOTIFY_FILE" 2>/dev/null || true)"
    if [[ "$notified_task" != "$task_id" ]]; then
      echo "EXECUTOR_DONE_USER_REPLY_SUPPRESSED=1"
      echo "EXECUTOR_DONE_ACTION=WAIT_FOR_INTERNAL_FINALIZE_OR_NEXT_RUN"
      printf '%s\n' "$task_id" > "$DONE_NOTIFY_FILE"
    fi
    echo "EXECUTOR_DONE_WAITING_DECISION=0"
    exit 0
  fi
fi

if [[ "$is_waiting_user" == "1" ]]; then
  echo "EXECUTOR_WAIT_USER_REPLY=1"
  exit 0
fi

start_out="$("${CODEX_SHARED_SCRIPTS_DIR}/executor_start.sh" "$task_id" "$issue_number" 2>&1)"
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  echo "$line"
done <<<"$start_out"

exit 0
