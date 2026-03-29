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
REVIEW_HANDOFF_REASON_FILE="${CODEX_DIR}/executor_review_handoff_reason.txt"
RUN_STARTED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
state_dir="$(codex_resolve_state_dir)"
profile_name="$(codex_resolve_project_profile_name 2>/dev/null || printf '%s' "${PROJECT_PROFILE:-default}")"
execution_dir="$(task_worktree_execution_dir "$task_id" "$issue_number" "$state_dir" "$profile_name")"
profile_file="$(task_worktree_execution_profile_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
context_cache_file="$(task_worktree_context_cache_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
canonical_diff_file="$(task_worktree_canonical_diff_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
failed_checks_file="$(task_worktree_failed_checks_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
check_results_file="$(task_worktree_check_results_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
guard_violations_file="${execution_dir}/blocked_commands.jsonl"
micro_noop="0"

mkdir -p "$CODEX_DIR" "$RUNTIME_LOG_DIR" "$execution_dir"
: > "$DETACH_FILE"
: > "$LAST_MSG_FILE"
: > "$failed_checks_file"
: > "$REVIEW_HANDOFF_REASON_FILE"

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

task_repo="$(task_worktree_repo_dir "$task_id" "$issue_number" "$state_dir" "$profile_name")"
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

if ! task_worktree_ensure_toolkit_materialized "$task_repo"; then
  {
    echo "EXECUTOR_TASK_WORKTREE_TOOLKIT_MISSING=1"
    echo "EXECUTOR_TASK_WORKTREE_PATH=${task_repo}"
    echo "EXECUTOR_TASK_WORKTREE_TOOLKIT_PATH=${task_repo}/.flow/shared"
    echo "=== EXECUTOR_RUN_FINISH task=${task_id} issue=${issue_number} rc=1 at $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
  } >>"$LOG_FILE" 2>&1
  printf '%s\n' "FAILED" > "$STATE_FILE"
  printf '%s\n' "1" > "$EXIT_FILE"
  date -u '+%Y-%m-%dT%H:%M:%SZ' > "$FINISH_FILE"
  : > "${CODEX_DIR}/executor_pid.txt"
  : > "$EXECUTION_ID_FILE"
  /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/incident_append.sh" executor_task_worktree_toolkit_missing "task=${task_id} issue=${issue_number} path=${task_repo}/.flow/shared" >/dev/null 2>&1 || true
  record_execution "1" "task_worktree_toolkit_missing" "none" "0"
  exit 0
fi

execution_profile="standard"
if [[ -f "$profile_file" ]]; then
  execution_profile="$(jq -r '.profile // "standard"' "$profile_file" 2>/dev/null || printf '%s' "standard")"
fi

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

codex_base_args=(codex exec -C "$task_repo")
executor_mode="full-auto"
if is_truthy "${EXECUTOR_CODEX_BYPASS_SANDBOX:-0}"; then
  codex_base_args+=(--dangerously-bypass-approvals-and-sandbox)
  executor_mode="danger-full-access"
else
  codex_base_args+=(--full-auto)
fi

{
  echo "EXECUTOR_CODEX_MODE=${executor_mode}"
  echo "EXECUTOR_CODEX_BYPASS_SANDBOX=${EXECUTOR_CODEX_BYPASS_SANDBOX:-0}"
  echo "EXECUTOR_TASK_WORKTREE_PATH=${task_repo}"
  echo "EXECUTION_PROFILE=${execution_profile}"
} >>"$LOG_FILE" 2>&1

run_codex_call() {
  local phase="$1"
  local prompt_file="$2"
  local response_file="$3"
  local call_index="$4"
  local call_log_file="${execution_dir}/llm-call-${call_index}-${phase}.log"
  local rc=0
  local codex_pid heartbeat_pid
  local guard_rc=0
  local guard_out=""
  local guard_bin_dir=""
  local -a call_args=("${codex_base_args[@]}" --output-last-message "$response_file")

  : > "$response_file"
  : > "$call_log_file"

  if [[ "$execution_profile" == "micro" ]]; then
    guard_out="$(
      /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/micro_prepare_guard_bin.sh" "$task_id" "$issue_number" 2>&1
    )"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      echo "$line"
    done <<<"$guard_out" >>"$LOG_FILE" 2>&1
    guard_bin_dir="$(printf '%s\n' "$guard_out" | sed -n 's/^MICRO_GUARD_BIN_DIR=//p' | tail -n1)"
  fi

  (
    set -o pipefail
    if [[ -n "$guard_bin_dir" ]]; then
      PATH="${guard_bin_dir}:$PATH" "${call_args[@]}" - < "$prompt_file" 2>&1 | tee -a "$call_log_file" >>"$LOG_FILE"
    else
      "${call_args[@]}" - < "$prompt_file" 2>&1 | tee -a "$call_log_file" >>"$LOG_FILE"
    fi
  ) &
  codex_pid="$!"

  (
    while kill -0 "$codex_pid" 2>/dev/null; do
      touch_heartbeat
      sleep "$heartbeat_sec"
    done
  ) &
  heartbeat_pid="$!"
  printf '%s\n' "$heartbeat_pid" > "$HEARTBEAT_PID_FILE"

  if wait "$codex_pid"; then
    rc=0
  else
    rc=$?
  fi

  kill "$heartbeat_pid" 2>/dev/null || true
  wait "$heartbeat_pid" 2>/dev/null || true
  touch_heartbeat

  [[ -f "$response_file" ]] && cp "$response_file" "$LAST_MSG_FILE"

  /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/llm_call_telemetry.sh" \
    "$task_id" "$issue_number" "$phase" "$call_index" "$prompt_file" "$response_file" "$call_log_file" >>"$LOG_FILE" 2>&1 || true
  guard_rc=0
  if ! /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/micro_profile_guard.sh" \
    "$task_id" "$issue_number" >>"$LOG_FILE" 2>&1; then
    guard_rc=$?
  fi
  if [[ "$guard_rc" -eq 42 ]]; then
    echo "FAILED_PROFILE_BREACH=1" >>"$LOG_FILE" 2>&1
    /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/incident_append.sh" profile_breach "task=${task_id} issue=${issue_number} phase=${phase}" >/dev/null 2>&1 || true
    return 42
  fi

  return "$rc"
}

micro_profile_breach_active() {
  local budget_file
  budget_file="$(task_worktree_execution_budget_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
  [[ -f "$budget_file" ]] || return 1
  [[ "$(jq -r '.profileBreach // false' "$budget_file" 2>/dev/null || printf 'false')" == "true" ]]
}

micro_profile_noop_detected() {
  [[ -f "$canonical_diff_file" ]] || return 1
  /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/canonical_diff.sh" "$task_id" "$issue_number" >>"$LOG_FILE" 2>&1 || return 1
  [[ -f "${execution_dir}/changed_files.json" ]] || return 1
  [[ "$(jq 'length' "${execution_dir}/changed_files.json" 2>/dev/null || printf '1')" == "0" ]]
}

run_micro_checks() {
  local results_tmp
  local failed=0
  local cmd rc out status

  results_tmp="$(mktemp "${execution_dir}/micro_checks.XXXXXX")"
  : > "$failed_checks_file"

  if [[ ! -f "$context_cache_file" ]]; then
    jq -nc '{results:[]}' > "$check_results_file"
    rm -f "$results_tmp"
    return 0
  fi

  while IFS= read -r cmd; do
    [[ -z "$cmd" ]] && continue
    rc=0
    out=""

    if ! micro_profile_allowlist_verification_command "$cmd"; then
      status="blocked_not_in_whitelist"
      rc=126
      out="Command is not allowed by micro-profile verification whitelist."
      failed=1
    elif out="$(cd "$task_repo" && /bin/bash -lc "$cmd" 2>&1)"; then
      status="passed"
      rc=0
    else
      rc=$?
      status="failed"
      failed=1
    fi

    jq -nc \
      --arg command "$cmd" \
      --arg status "$status" \
      --arg output "$out" \
      --argjson rc "$rc" \
      '{command:$command, status:$status, rc:$rc, output:$output}' >> "$results_tmp"

    if [[ "$status" != "passed" ]]; then
      {
        printf 'COMMAND: %s\n' "$cmd"
        printf 'STATUS: %s\n' "$status"
        printf 'RC: %s\n' "$rc"
        printf '%s\n\n' "$out"
      } >> "$failed_checks_file"
    fi
  done < <(jq -r '.checkCommands[]? // empty' "$context_cache_file")

  jq -s '{results:.}' "$results_tmp" > "$check_results_file"
  rm -f "$results_tmp"
  return "$failed"
}

build_micro_repair_prompt() {
  local repair_prompt_file="$1"
  local diff_text=""
  local failed_text=""
  local issue_summary=""

  [[ -f "$canonical_diff_file" ]] && diff_text="$(cat "$canonical_diff_file")"
  [[ -f "$failed_checks_file" ]] && failed_text="$(cat "$failed_checks_file")"
  if [[ -f "$context_cache_file" ]]; then
    issue_summary="$(jq -r '.issueSummary // ""' "$context_cache_file")"
  fi

  {
    printf '%s\n' 'Ты продолжаешь micro-task для репозитория PLANKA.'
    printf '%s\n' 'Discovery и повторные чтения файлов запрещены. Используй только canonical diff и failed checks ниже.'
    printf '\n'
    printf '%s\n' "Task ID: ${task_id}"
    printf '%s\n' "Issue: #${issue_number}"
    printf '\n'
    printf '%s\n' 'Issue summary:'
    printf '%s\n' "$issue_summary"
    printf '\n'
    printf '%s\n' 'Canonical diff:'
    printf '%s\n' "$diff_text"
    printf '\n'
    printf '%s\n' 'Failed checks:'
    printf '%s\n' "$failed_text"
    printf '\n'
    printf '%s\n' 'Исправь только причины падения проверок, затем выполни проверки и остановись. Не трогай finalize/PR metadata.'
  } > "$repair_prompt_file"
}

rc=0
if run_codex_call "implementation" "$PROMPT_FILE" "${execution_dir}/llm-response-1.txt" 1; then
  rc=0
else
  rc=$?
fi

if [[ "$execution_profile" == "micro" && "$rc" -eq 0 ]] && micro_profile_breach_active; then
  rc=42
fi

if [[ "$execution_profile" == "micro" && "$rc" -eq 0 ]]; then
  if run_micro_checks; then
    if micro_profile_noop_detected; then
      micro_noop="1"
      {
        echo "MICRO_NOOP_ALREADY_SATISFIED=1"
        echo "MICRO_NOOP_REASON=empty_canonical_diff_after_successful_checks"
      } >>"$LOG_FILE" 2>&1
    fi
  else
    if micro_profile_breach_active; then
      rc=42
    else
    /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/canonical_diff.sh" "$task_id" "$issue_number" >>"$LOG_FILE" 2>&1 || true
    build_micro_repair_prompt "${execution_dir}/micro_repair_prompt.txt"
    if run_codex_call "repair" "${execution_dir}/micro_repair_prompt.txt" "${execution_dir}/llm-response-2.txt" 2; then
      rc=0
    else
      rc=$?
    fi
    if [[ "$rc" -eq 0 ]] && micro_profile_breach_active; then
      rc=42
    fi
    if [[ "$rc" -eq 0 ]]; then
      if run_micro_checks; then
        if micro_profile_noop_detected; then
          micro_noop="1"
          {
            echo "MICRO_NOOP_ALREADY_SATISFIED=1"
            echo "MICRO_NOOP_REASON=empty_canonical_diff_after_successful_checks"
          } >>"$LOG_FILE" 2>&1
        fi
      else
        rc=1
      fi
    fi
    fi
  fi

  if [[ "$rc" -eq 0 && "$micro_noop" != "1" ]]; then
    if is_truthy "${EXECUTOR_MICRO_SKIP_FINALIZE:-0}"; then
      /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/canonical_diff.sh" "$task_id" "$issue_number" >>"$LOG_FILE" 2>&1 || rc=$?
      /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/metadata_builder.sh" "$task_id" "$issue_number" >>"$LOG_FILE" 2>&1 || rc=$?
      {
        echo "EXECUTOR_MICRO_SKIP_FINALIZE=1"
        echo "EXECUTOR_MICRO_FINALIZE_SKIPPED=1"
      } >>"$LOG_FILE" 2>&1
    else
      /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/micro_finalize.sh" "$task_id" "$issue_number" >>"$LOG_FILE" 2>&1 || rc=$?
    fi
  fi
fi

detach_requested="0"
if [[ -s "$DETACH_FILE" ]]; then
  detach_requested="1"
fi

if [[ "$detach_requested" == "1" ]]; then
  waiting_issue_number="$(cat "${CODEX_DIR}/daemon_waiting_issue_number.txt" 2>/dev/null || true)"
  waiting_kind="$(cat "${CODEX_DIR}/daemon_waiting_kind.txt" 2>/dev/null || true)"
  if [[ -n "$waiting_issue_number" ]]; then
    printf '%s\n' "REVIEW_NEEDED" > "$STATE_FILE"
    if [[ "$waiting_kind" == "REVIEW_FEEDBACK" ]]; then
      printf '%s\n' "review_feedback_wait" > "$REVIEW_HANDOFF_REASON_FILE"
    else
      printf '%s\n' "waiting_user_reply" > "$REVIEW_HANDOFF_REASON_FILE"
    fi
  elif [[ "$rc" == "0" ]]; then
    printf '%s\n' "DONE" > "$STATE_FILE"
    : > "$REVIEW_HANDOFF_REASON_FILE"
  else
    printf '%s\n' "FAILED" > "$STATE_FILE"
  fi
  printf '%s\n' "$rc" > "$EXIT_FILE"
  date -u '+%Y-%m-%dT%H:%M:%SZ' > "$FINISH_FILE"
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
if [[ "$rc" -eq 42 ]]; then
  termination_reason="failed_profile_breach"
elif [[ "$micro_noop" == "1" ]]; then
  termination_reason="noop_already_satisfied"
fi
if printf '%s\n' "$run_log_slice" | rg -n "Quota exceeded" >/dev/null 2>&1; then
  provider_error_class="quota_exceeded"
  termination_reason="provider_quota_exceeded"
  execution_id_for_budget="$(cat "$EXECUTION_ID_FILE" 2>/dev/null || true)"
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
    "legacy-v2-budget-breach-${task_id}-${execution_id_for_budget:-quota}" \
    "legacy.budget.breached:${task_id}:provider_quota_exceeded" \
    "$budget_payload"
  /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/runtime_v2_sync_control_mode.sh" >/dev/null 2>&1 || true
fi

if [[ "$rc" == "0" ]]; then
  printf '%s\n' "DONE" > "$STATE_FILE"
else
  review_handoff_reason=""
  if [[ "$rc" -eq 42 ]]; then
    review_handoff_reason="profile_breach"
  elif [[ "$provider_error_class" == "quota_exceeded" ]]; then
    review_handoff_reason="provider_quota_exceeded"
  fi

  if [[ -n "$review_handoff_reason" ]]; then
    printf '%s\n' "REVIEW_NEEDED" > "$STATE_FILE"
    printf '%s\n' "$review_handoff_reason" > "$REVIEW_HANDOFF_REASON_FILE"
  else
    printf '%s\n' "FAILED" > "$STATE_FILE"
    : > "$REVIEW_HANDOFF_REASON_FILE"
  fi

  if [[ "$provider_error_class" == "none" && -z "$review_handoff_reason" ]]; then
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
