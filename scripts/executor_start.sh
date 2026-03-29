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
# shellcheck source=./micro_profile_lib.sh
source "${SCRIPT_DIR}/micro_profile_lib.sh"
CODEX_DIR="$(codex_export_state_dir)"
RUNTIME_LOG_DIR="$(codex_resolve_flow_runtime_log_dir)"
state_dir="$(codex_resolve_state_dir)"
profile_name="$(codex_resolve_project_profile_name 2>/dev/null || printf '%s' "${PROJECT_PROFILE:-default}")"

STATE_FILE="${CODEX_DIR}/executor_state.txt"
PID_FILE="${CODEX_DIR}/executor_pid.txt"
TASK_FILE="${CODEX_DIR}/executor_task_id.txt"
ISSUE_FILE="${CODEX_DIR}/executor_issue_number.txt"
EXECUTION_ID_FILE="${CODEX_DIR}/executor_active_execution_id.txt"
START_FILE="${CODEX_DIR}/executor_last_started_utc.txt"
START_EPOCH_FILE="${CODEX_DIR}/executor_last_start_epoch.txt"
LOG_FILE="${RUNTIME_LOG_DIR}/executor.log"
HEARTBEAT_FILE="${CODEX_DIR}/executor_heartbeat_utc.txt"
HEARTBEAT_EPOCH_FILE="${CODEX_DIR}/executor_heartbeat_epoch.txt"
HEARTBEAT_PID_FILE="${CODEX_DIR}/executor_heartbeat_pid.txt"
PROFILE_FILE="$(task_worktree_execution_profile_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
BUDGET_FILE="$(task_worktree_execution_budget_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"

mkdir -p "$CODEX_DIR" "$RUNTIME_LOG_DIR"
mkdir -p "$(dirname "$PROFILE_FILE")"

control_mode="$(/bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/containment_mode.sh" get --raw 2>/dev/null || printf 'AUTO')"
if [[ "$control_mode" != "AUTO" ]]; then
  control_reason="$(/bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/containment_mode.sh" get | awk -F= '/^CONTROL_REASON=/{print substr($0, index($0, "=")+1)}' 2>/dev/null || true)"
  printf '%s\n' "FAILED" > "$STATE_FILE"
  printf '%s\n' "control_mode_${control_mode}" > "${CODEX_DIR}/executor_last_exit_code.txt"
  echo "EXECUTOR_START_BLOCKED=1"
  echo "CONTROL_MODE=$control_mode"
  [[ -n "$control_reason" ]] && echo "CONTROL_REASON=$control_reason"
  exit 0
fi

if gate_out="$(
  /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/runtime_v2_gate.sh" \
    "$task_id" "$issue_number" "executor_start" "executor_start" 2>&1
)"; then
  :
else
  gate_rc=$?
  printf '%s\n' "FAILED" > "$STATE_FILE"
  printf '%s\n' "gate_${gate_rc}" > "${CODEX_DIR}/executor_last_exit_code.txt"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "EXECUTOR_START_GATE_ERROR(rc=$gate_rc): $line"
  done <<<"$gate_out"
  exit 0
fi
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  echo "$line"
done <<<"$gate_out"
gate_status="$(printf '%s\n' "$gate_out" | sed -n 's/^RUNTIME_V2_GATE_STATUS=//p' | tail -n1)"
gate_reason="$(printf '%s\n' "$gate_out" | sed -n 's/^RUNTIME_V2_GATE_REASON=//p' | tail -n1)"
if [[ "$gate_status" == "blocked" ]]; then
  echo "EXECUTOR_START_BLOCKED_BY_V2_GATE=1"
  [[ -n "$gate_reason" ]] && echo "EXECUTOR_START_BLOCK_REASON=$gate_reason"
  exit 0
fi

if classifier_out="$(
  /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/micro_task_classifier.sh" \
    "$task_id" "$issue_number" "$PROFILE_FILE" 2>&1
)"; then
  :
else
  classifier_rc=$?
  printf '%s\n' "FAILED" > "$STATE_FILE"
  printf '%s\n' "classifier_${classifier_rc}" > "${CODEX_DIR}/executor_last_exit_code.txt"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "EXECUTOR_START_CLASSIFIER_ERROR(rc=$classifier_rc): $line"
  done <<<"$classifier_out"
  exit 0
fi
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  echo "$line"
done <<<"$classifier_out"
execution_profile="$(printf '%s\n' "$classifier_out" | sed -n 's/^EXECUTION_PROFILE=//p' | tail -n1)"
execution_profile_reason="$(printf '%s\n' "$classifier_out" | sed -n 's/^EXECUTION_PROFILE_REASON=//p' | tail -n1)"
execution_profile_target_count="$(printf '%s\n' "$classifier_out" | sed -n 's/^EXECUTION_PROFILE_TARGET_COUNT=//p' | tail -n1)"
echo "EXECUTION_PROFILE=${execution_profile}"
[[ -n "$execution_profile_reason" ]] && echo "EXECUTION_PROFILE_REASON=${execution_profile_reason}"
[[ -n "$execution_profile_target_count" ]] && echo "EXECUTION_PROFILE_TARGET_COUNT=${execution_profile_target_count}"
echo "EXECUTION_PROFILE_FILE=${PROFILE_FILE}"
[[ -f "$PROFILE_FILE" ]] && echo "STANDARDIZED_TASK_SPEC_FILE=$(jq -r '.standardizedTaskSpecFile // empty' "$PROFILE_FILE" 2>/dev/null || true)"
[[ -f "$PROFILE_FILE" ]] && echo "SOURCE_DEFINITION_FILE=$(jq -r '.sourceDefinitionFile // empty' "$PROFILE_FILE" 2>/dev/null || true)"
[[ -f "$PROFILE_FILE" ]] && echo "INTAKE_PROFILE_FILE=$(jq -r '.intakeProfileFile // empty' "$PROFILE_FILE" 2>/dev/null || true)"
if [[ "$execution_profile" == "human_needed" || "$execution_profile" == "blocked" ]]; then
  printf '%s\n' "FAILED" > "$STATE_FILE"
  printf '%s\n' "intake_${execution_profile}" > "${CODEX_DIR}/executor_last_exit_code.txt"
  echo "EXECUTOR_START_BLOCKED_BY_INTAKE=1"
  echo "EXECUTOR_START_BLOCK_REASON=${execution_profile_reason}"
  exit 0
fi
if [[ "$execution_profile" == "micro" ]]; then
  micro_profile_budget_init_json \
    "$task_id" \
    "$issue_number" \
    "${EXECUTOR_MICRO_MAX_TOTAL_TOKENS:-15000}" \
    "${EXECUTOR_MICRO_PROFILE_ENFORCE:-1}" > "$BUDGET_FILE"
  echo "EXECUTION_BUDGET_FILE=${BUDGET_FILE}"
fi

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

execution_id="legacy-v2-exec-${task_id}-$(date +%s)-$$"
execution_payload="$(
  jq -nc --arg executionId "$execution_id" '{executionId:$executionId}'
)"
if execution_event_out="$(
  /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/runtime_v2_apply_event.sh" \
    "$task_id" "$issue_number" "execution.started" \
    "legacy-v2-event-execution-start-${task_id}-${execution_id}" \
    "legacy.execution.started:${task_id}:${execution_id}" \
    "$execution_payload" 2>&1
)"; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "RUNTIME_V2_EVENT: $line"
  done <<<"$execution_event_out"
  execution_event_status="$(printf '%s\n' "$execution_event_out" | sed -n 's/^RUNTIME_V2_EVENT_STATUS=//p' | tail -n1)"
  execution_event_reason="$(printf '%s\n' "$execution_event_out" | sed -n 's/^RUNTIME_V2_EVENT_REASON=//p' | tail -n1)"
  if [[ "$execution_event_status" == "blocked" ]]; then
    echo "EXECUTOR_START_BLOCKED_BY_V2_EVENT=1"
    [[ -n "$execution_event_reason" ]] && echo "EXECUTOR_START_BLOCK_REASON=$execution_event_reason"
    exit 0
  fi
  if [[ "$execution_event_status" == "applied" ]]; then
    printf '%s\n' "$execution_id" > "$EXECUTION_ID_FILE"
  fi
else
  rc=$?
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "RUNTIME_V2_EVENT_ERROR(rc=$rc): $line"
  done <<<"$execution_event_out"
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
