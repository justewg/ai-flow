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

STATE_FILE="${CODEX_DIR}/executor_state.txt"
PID_FILE="${CODEX_DIR}/executor_pid.txt"
TASK_FILE="${CODEX_DIR}/executor_task_id.txt"
ISSUE_FILE="${CODEX_DIR}/executor_issue_number.txt"
EXIT_FILE="${CODEX_DIR}/executor_last_exit_code.txt"
START_EPOCH_FILE="${CODEX_DIR}/executor_last_start_epoch.txt"
FAIL_NOTIFY_FILE="${CODEX_DIR}/executor_failure_notified_task.txt"
RETRY_REPLY_FILE="${CODEX_DIR}/executor_last_retry_reply_comment_id.txt"

mkdir -p "$CODEX_DIR"

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
  "${ROOT_DIR}/scripts/codex/executor_reset.sh" >/dev/null
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
  # После нового ответа пользователя даем executor одну новую попытку.
  if [[ "$is_waiting_user" != "1" && "$reply_task" == "$task_id" && "$reply_issue" == "$issue_number" &&
    -n "$reply_comment_id" && "$reply_comment_id" != "$last_retry_reply_id" ]]; then
    printf '%s\n' "$reply_comment_id" > "$RETRY_REPLY_FILE"
    "${ROOT_DIR}/scripts/codex/executor_reset.sh" >/dev/null
    echo "EXECUTOR_RETRY_AFTER_USER_REPLY=1"
    echo "EXECUTOR_RETRY_REPLY_COMMENT_ID=$reply_comment_id"
    state=""
  else
  echo "EXECUTOR_FAILED=1"
  echo "EXECUTOR_TASK_ID=$task_id"
  echo "EXECUTOR_EXIT_CODE=${last_rc:-unknown}"

  notified_task="$(cat "$FAIL_NOTIFY_FILE" 2>/dev/null || true)"
  if [[ "$notified_task" != "$task_id" && "$is_waiting_user" != "1" ]]; then
    msg_file="$(mktemp "${CODEX_DIR}/executor_failed.XXXXXX")"
    cat > "$msg_file" <<EOF
Executor не смог продолжить задачу.
Task: ${task_id}
Issue: #${issue_number}
Exit code: ${last_rc:-unknown}

Проверь логи .tmp/codex/executor.log и дай команду как действовать дальше.
EOF
    if ask_out="$("${ROOT_DIR}/scripts/codex/task_ask.sh" blocker "$msg_file" 2>&1)"; then
      echo "EXECUTOR_FAILURE_BLOCKER_POSTED=1"
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "EXECUTOR: $line"
      done <<<"$ask_out"
      printf '%s\n' "$task_id" > "$FAIL_NOTIFY_FILE"
    else
      rc=$?
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "EXECUTOR_BLOCKER_ERROR(rc=$rc): $line"
      done <<<"$ask_out"
    fi
    rm -f "$msg_file"
  fi
    exit 0
  fi
fi

if [[ "$state" == "DONE" ]]; then
  echo "EXECUTOR_DONE=1"
  echo "EXECUTOR_TASK_ID=$task_id"
  if [[ "$is_waiting_user" == "1" ]]; then
    echo "EXECUTOR_WAIT_USER_REPLY=1"
    exit 0
  fi

  # Если задача еще активна и нет waiting-state, перезапускаем executor
  # (например после получения USER_REPLY_RECEIVED).
  now_epoch="$(date +%s)"
  last_start_epoch="$(cat "$START_EPOCH_FILE" 2>/dev/null || echo 0)"
  if ! [[ "$last_start_epoch" =~ ^[0-9]+$ ]]; then
    last_start_epoch=0
  fi
  cooldown_sec="${EXECUTOR_RESTART_COOLDOWN_SEC:-20}"
  if ! [[ "$cooldown_sec" =~ ^[0-9]+$ ]] || (( cooldown_sec < 5 )); then
    cooldown_sec=20
  fi

  if (( now_epoch - last_start_epoch < cooldown_sec )); then
    echo "WAIT_EXECUTOR_RESTART_COOLDOWN=$((cooldown_sec - (now_epoch - last_start_epoch)))"
    exit 0
  fi
fi

if [[ "$is_waiting_user" == "1" ]]; then
  echo "EXECUTOR_WAIT_USER_REPLY=1"
  exit 0
fi

start_out="$("${ROOT_DIR}/scripts/codex/executor_start.sh" "$task_id" "$issue_number" 2>&1)"
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  echo "$line"
done <<<"$start_out"

exit 0
