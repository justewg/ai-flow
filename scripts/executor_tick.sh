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
STATE_TMP_DIR="$(codex_resolve_state_tmp_dir "$CODEX_DIR")"
mkdir -p "$STATE_TMP_DIR"
RUNTIME_LOG_DIR="$(codex_resolve_flow_runtime_log_dir)"

control_mode="$(/bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/containment_mode.sh" get --raw 2>/dev/null || printf 'AUTO')"
if [[ "$control_mode" != "AUTO" ]]; then
  control_reason="$(/bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/containment_mode.sh" get | awk -F= '/^CONTROL_REASON=/{print substr($0, index($0, "=")+1)}' 2>/dev/null || true)"
  echo "EXECUTOR_BLOCKED_BY_CONTROL_MODE=1"
  echo "EXECUTOR_TASK_ID=$task_id"
  echo "CONTROL_MODE=$control_mode"
  [[ -n "$control_reason" ]] && echo "CONTROL_REASON=$control_reason"
  exit 0
fi

STATE_FILE="${CODEX_DIR}/executor_state.txt"
PID_FILE="${CODEX_DIR}/executor_pid.txt"
TASK_FILE="${CODEX_DIR}/executor_task_id.txt"
ISSUE_FILE="${CODEX_DIR}/executor_issue_number.txt"
EXIT_FILE="${CODEX_DIR}/executor_last_exit_code.txt"
FAIL_NOTIFY_FILE="${CODEX_DIR}/executor_failure_notified_task.txt"
DONE_NOTIFY_FILE="${CODEX_DIR}/executor_done_wait_notified_task.txt"
RETRY_REPLY_FILE="${CODEX_DIR}/executor_last_retry_reply_comment_id.txt"
LAST_MSG_FILE="${CODEX_DIR}/executor_last_message.txt"
AUTO_RETRY_TASK_FILE="${CODEX_DIR}/executor_auto_retry_task_id.txt"
AUTO_RETRY_COUNT_FILE="${CODEX_DIR}/executor_auto_retry_count.txt"

mkdir -p "$CODEX_DIR"
auto_retry_triggered="0"

reset_auto_retry_state() {
  : > "$AUTO_RETRY_TASK_FILE"
  : > "$AUTO_RETRY_COUNT_FILE"
}

current_auto_retry_count() {
  local stored_task stored_count
  stored_task="$(cat "$AUTO_RETRY_TASK_FILE" 2>/dev/null || true)"
  stored_count="$(cat "$AUTO_RETRY_COUNT_FILE" 2>/dev/null || true)"
  if [[ "$stored_task" != "$task_id" ]] || ! [[ "$stored_count" =~ ^[0-9]+$ ]]; then
    printf '0'
    return 0
  fi
  printf '%s' "$stored_count"
}

record_auto_retry_count() {
  local count="$1"
  printf '%s\n' "$task_id" > "$AUTO_RETRY_TASK_FILE"
  printf '%s\n' "$count" > "$AUTO_RETRY_COUNT_FILE"
}

executor_explicit_user_reply_requested() {
  local text=""
  [[ -s "$LAST_MSG_FILE" ]] || return 1
  text="$(<"$LAST_MSG_FILE")"
  printf '%s\n' "$text" \
    | grep -Eiq '^(ASK_QUESTION|ASK_REASON|ASK_KIND)=|^CODEX_EXPECT:[[:space:]]*USER_REPLY$|^Вопрос executor:|^QUESTION:'
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
  /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/executor_reset.sh" >/dev/null
  reset_auto_retry_state
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
  # После нового ответа пользователя даем executor одну новую попытку.
  if [[ "$is_waiting_user" != "1" && "$reply_task" == "$task_id" && "$reply_issue" == "$issue_number" &&
    -n "$reply_comment_id" && "$reply_comment_id" != "$last_retry_reply_id" ]]; then
    printf '%s\n' "$reply_comment_id" > "$RETRY_REPLY_FILE"
    /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/executor_reset.sh" >/dev/null
    reset_auto_retry_state
    : > "$DONE_NOTIFY_FILE"
    : > "$FAIL_NOTIFY_FILE"
    echo "EXECUTOR_RETRY_AFTER_USER_REPLY=1"
    echo "EXECUTOR_RETRY_REPLY_COMMENT_ID=$reply_comment_id"
    state=""
  else
    if [[ "$is_waiting_user" == "1" ]]; then
      echo "EXECUTOR_WAIT_USER_REPLY=1"
      echo "EXECUTOR_TASK_ID=$task_id"
      exit 0
    fi

    echo "EXECUTOR_FAILED=1"
    echo "EXECUTOR_TASK_ID=$task_id"
    echo "EXECUTOR_EXIT_CODE=${last_rc:-unknown}"

    notified_task="$(cat "$FAIL_NOTIFY_FILE" 2>/dev/null || true)"
    if [[ "$notified_task" != "$task_id" && "$is_waiting_user" != "1" ]]; then
      auto_retry_limit="${EXECUTOR_FAILED_AUTO_RETRY_LIMIT:-2}"
      if ! [[ "$auto_retry_limit" =~ ^[0-9]+$ ]] || (( auto_retry_limit < 0 )); then
        auto_retry_limit=2
      fi

      auto_retry_count="$(current_auto_retry_count)"
      if [[ "$auto_retry_count" -lt "$auto_retry_limit" ]] && ! executor_explicit_user_reply_requested; then
        next_retry_count=$((auto_retry_count + 1))
        record_auto_retry_count "$next_retry_count"
        /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/executor_reset.sh" >/dev/null
        : > "$DONE_NOTIFY_FILE"
        : > "$FAIL_NOTIFY_FILE"
        echo "EXECUTOR_AUTO_RETRY=1"
        echo "EXECUTOR_AUTO_RETRY_REASON=FAILED_WITHOUT_EXPLICIT_USER_REPLY"
        echo "EXECUTOR_AUTO_RETRY_COUNT=$next_retry_count"
        auto_retry_triggered="1"
        state=""
      else
        msg_file="$(mktemp "${STATE_TMP_DIR}/executor_failed.XXXXXX")"
        cat > "$msg_file" <<EOF
Executor не смог продолжить задачу.
Task: ${task_id}
Issue: #${issue_number}
Exit code: ${last_rc:-unknown}

Проверь логи ${RUNTIME_LOG_DIR}/executor.log и дай команду как действовать дальше.
EOF
        if ask_out="$("${CODEX_SHARED_SCRIPTS_DIR}/task_ask.sh" blocker "$msg_file" 2>&1)"; then
          echo "EXECUTOR_FAILURE_BLOCKER_POSTED=1"
          while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            echo "EXECUTOR: $line"
          done <<<"$ask_out"
          printf '%s\n' "$task_id" > "$FAIL_NOTIFY_FILE"
          echo "EXECUTOR_WAIT_USER_REPLY=1"
          rm -f "$msg_file"
          exit 0
        else
          rc=$?
          if [[ "$rc" -eq 42 && "$auto_retry_count" -lt "$auto_retry_limit" ]]; then
            next_retry_count=$((auto_retry_count + 1))
            record_auto_retry_count "$next_retry_count"
            /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/executor_reset.sh" >/dev/null
            : > "$DONE_NOTIFY_FILE"
            : > "$FAIL_NOTIFY_FILE"
            echo "EXECUTOR_AUTO_RETRY=1"
            echo "EXECUTOR_AUTO_RETRY_REASON=MALFORMED_BLOCKER_REJECTED"
            echo "EXECUTOR_AUTO_RETRY_COUNT=$next_retry_count"
            auto_retry_triggered="1"
            state=""
          else
            while IFS= read -r line; do
              [[ -z "$line" ]] && continue
              echo "EXECUTOR_BLOCKER_ERROR(rc=$rc): $line"
            done <<<"$ask_out"
          fi
        fi
        rm -f "$msg_file"
      fi
    fi
    if [[ "$state" == "FAILED" ]]; then
      exit 0
    fi
  fi
fi

if [[ "$state" == "DONE" ]]; then
  if [[ "$is_waiting_user" != "1" && "$reply_task" == "$task_id" && "$reply_issue" == "$issue_number" &&
    -n "$reply_comment_id" && "$reply_comment_id" != "$last_retry_reply_id" ]]; then
    printf '%s\n' "$reply_comment_id" > "$RETRY_REPLY_FILE"
    /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/executor_reset.sh" >/dev/null
    reset_auto_retry_state
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
      msg_file="$(mktemp "${STATE_TMP_DIR}/executor_done_wait.XXXXXX")"
      cat > "$msg_file" <<EOF
Executor завершил текущий прогон без финализации задачи.
Task: ${task_id}
Issue: #${issue_number}

Сейчас он ждет твоего решения:
- "продолжай" — запустить следующий прогон;
- "финализируй" — переходить к завершению PR.
EOF
      if ask_out="$("${CODEX_SHARED_SCRIPTS_DIR}/task_ask.sh" blocker "$msg_file" 2>&1)"; then
        echo "EXECUTOR_DONE_BLOCKER_POSTED=1"
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          echo "EXECUTOR: $line"
        done <<<"$ask_out"
        printf '%s\n' "$task_id" > "$DONE_NOTIFY_FILE"
        echo "EXECUTOR_WAIT_USER_REPLY=1"
        rm -f "$msg_file"
        exit 0
      else
        rc=$?
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          echo "EXECUTOR_DONE_BLOCKER_ERROR(rc=$rc): $line"
        done <<<"$ask_out"
      fi
      rm -f "$msg_file"
    fi
    echo "EXECUTOR_DONE_WAITING_DECISION=1"
    exit 0
  fi
fi

if [[ "$is_waiting_user" == "1" ]]; then
  echo "EXECUTOR_WAIT_USER_REPLY=1"
  exit 0
fi

if [[ "$auto_retry_triggered" != "1" ]]; then
  reset_auto_retry_state
fi

if start_out="$("${CODEX_SHARED_SCRIPTS_DIR}/executor_start.sh" "$task_id" "$issue_number" 2>&1)"; then
  :
else
  start_rc=$?
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "EXECUTOR_START_ERROR(rc=$start_rc): $line"
  done <<<"$start_out"
  exit 0
fi
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  echo "$line"
done <<<"$start_out"

exit 0
