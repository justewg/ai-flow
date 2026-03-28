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
EXECUTION_ID_FILE="${CODEX_DIR}/executor_active_execution_id.txt"
EXIT_FILE="${CODEX_DIR}/executor_last_exit_code.txt"
FINISH_FILE="${CODEX_DIR}/executor_last_finished_utc.txt"
LAST_MSG_FILE="${CODEX_DIR}/executor_last_message.txt"
HEARTBEAT_FILE="${CODEX_DIR}/executor_heartbeat_utc.txt"
HEARTBEAT_EPOCH_FILE="${CODEX_DIR}/executor_heartbeat_epoch.txt"
HEARTBEAT_PID_FILE="${CODEX_DIR}/executor_heartbeat_pid.txt"
DETACH_FILE="${CODEX_DIR}/executor_detach_requested.txt"
RUN_STARTED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

mkdir -p "$CODEX_DIR" "$RUNTIME_LOG_DIR"
: > "$DETACH_FILE"

record_execution() {
  local rc="$1"
  local termination_reason="$2"
  local provider_error_class="$3"
  local detached="$4"
  /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/execution_record.sh" \
    "$task_id" "$issue_number" "$rc" "$RUN_STARTED_AT" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    "$termination_reason" "$provider_error_class" "$detached" >/dev/null 2>&1 || true
}

emit_runtime_v2_event() {
  local event_type="$1"
  local event_id="$2"
  local dedup_key="$3"
  local payload_json="${4:-{}}"
  local event_out rc

  if event_out="$(
    /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/runtime_v2_apply_event.sh" \
      "$task_id" "$issue_number" "$event_type" "$event_id" "$dedup_key" "$payload_json" 2>&1
  )"; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      echo "RUNTIME_V2_EVENT: $line"
    done <<< "$event_out" >>"$LOG_FILE" 2>&1
  else
    rc=$?
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      echo "RUNTIME_V2_EVENT_ERROR(rc=$rc): $line"
    done <<< "$event_out" >>"$LOG_FILE" 2>&1
  fi
}

task_repo="$(task_worktree_repo_dir "$task_id" "$issue_number")"
if ! task_worktree_repo_present "$task_repo"; then
  {
    echo "EXECUTOR_TASK_WORKTREE_MISSING=1"
    echo "EXECUTOR_TASK_WORKTREE_PATH=${task_repo}"
    echo "=== EXECUTOR_RUN_FINISH task=${task_id} issue=${issue_number} rc=1 at $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
  } >>"$LOG_FILE" 2>&1
  printf '%s\n' "FAILED" > "$STATE_FILE"
  printf '%s\n' "1" > "$EXIT_FILE"
  date -u '+%Y-%m-%dT%H:%M:%SZ' > "$FINISH_FILE"
  : > "${CODEX_DIR}/executor_pid.txt"
  : > "$EXECUTION_ID_FILE"
  /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/incident_append.sh" executor_task_worktree_missing "task=${task_id} issue=${issue_number} path=${task_repo}" >/dev/null 2>&1 || true
  record_execution "1" "task_worktree_missing" "none" "0"
  exit 0
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
  echo "=== EXECUTOR_RUN_START task=${task_id} issue=${issue_number} at ${RUN_STARTED_AT} ==="
  "${CODEX_SHARED_SCRIPTS_DIR}/executor_build_prompt.sh" "$task_id" "$issue_number" "$PROMPT_FILE"
} >>"$LOG_FILE" 2>&1

touch_heartbeat

heartbeat_sec="${EXECUTOR_HEARTBEAT_SEC:-8}"
if ! [[ "$heartbeat_sec" =~ ^[0-9]+$ ]] || (( heartbeat_sec < 3 )); then
  heartbeat_sec=8
fi

run_log_start_line=1
if [[ -f "$LOG_FILE" ]]; then
  run_log_start_line=$(( $(wc -l < "$LOG_FILE") + 1 ))
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
  : > "$EXECUTION_ID_FILE"
  {
    echo "EXECUTOR_RUN_DETACHED=1"
    echo "=== EXECUTOR_RUN_FINISH task=${task_id} issue=${issue_number} rc=${rc} detached=1 at $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
  } >>"$LOG_FILE" 2>&1
  record_execution "$rc" "detached_after_finalize" "none" "1"
  exit 0
fi

provider_error_class="none"
termination_reason="completed"
run_log_slice="$(sed -n "${run_log_start_line},\$p" "$LOG_FILE" 2>/dev/null || true)"
if printf '%s\n' "$run_log_slice" | rg -n "Quota exceeded" >/dev/null 2>&1; then
  provider_error_class="quota_exceeded"
  termination_reason="provider_quota_exceeded"
  budget_payload="$(
    jq -nc \
      --arg reason "provider quota exceeded during executor run" \
      --arg breachReason "provider_quota_exceeded" \
      --arg providerErrorClass "$provider_error_class" \
      --arg triggeredAt "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
      '{reason:$reason, breachReason:$breachReason, providerErrorClass:$providerErrorClass, budgetState:"emergency_stop", triggeredAt:$triggeredAt}'
  )"
  emit_runtime_v2_event \
    "budget.breached" \
    "legacy-v2-budget-breach-${task_id}-${execution_id:-quota}" \
    "legacy.budget.breached:${task_id}:provider_quota_exceeded" \
    "$budget_payload"
  /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/runtime_v2_sync_control_mode.sh" >/dev/null 2>&1 || true
fi

if [[ "$rc" == "0" ]]; then
  printf '%s\n' "DONE" > "$STATE_FILE"
else
  printf '%s\n' "FAILED" > "$STATE_FILE"
  if [[ "$provider_error_class" == "none" ]]; then
    termination_reason="executor_failed"
  fi
fi

printf '%s\n' "$rc" > "$EXIT_FILE"
date -u '+%Y-%m-%dT%H:%M:%SZ' > "$FINISH_FILE"
: > "${CODEX_DIR}/executor_pid.txt"
: > "$HEARTBEAT_PID_FILE"
: > "$DETACH_FILE"

execution_id="$(cat "$EXECUTION_ID_FILE" 2>/dev/null || true)"
if [[ -n "$execution_id" ]]; then
  finish_payload="$(
    jq -nc --arg executionId "$execution_id" '{executionId:$executionId}'
  )"
  emit_runtime_v2_event \
    "execution.finished" \
    "legacy-v2-event-execution-finish-${task_id}-${execution_id}-${rc}" \
    "legacy.execution.finished:${task_id}:${execution_id}:${rc}" \
    "$finish_payload"
fi
: > "$EXECUTION_ID_FILE"

{
  echo "=== EXECUTOR_RUN_FINISH task=${task_id} issue=${issue_number} rc=${rc} at $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
} >>"$LOG_FILE" 2>&1

record_execution "$rc" "$termination_reason" "$provider_error_class" "0"

exit 0
