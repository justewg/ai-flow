#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
CODEX_DIR="$(codex_export_state_dir)"
RUNTIME_LOG_DIR="$(codex_resolve_flow_runtime_log_dir)"
FLOW_LOGS_DIR="$(codex_resolve_flow_logs_dir)"
project_profile="$(codex_resolve_project_profile_name)"
project_repo="$(codex_resolve_project_repo_slug)"
project_label="$(codex_resolve_project_display_label)"
runtime_role="$(codex_resolve_flow_automation_runtime_role)"
runtime_instance_id="$(codex_resolve_flow_runtime_instance_id)"
authoritative_runtime_id="$(codex_resolve_flow_authoritative_runtime_id)"

now_epoch="$(date +%s)"
now_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

read_file_or_default() {
  local file_path="$1"
  local default_value="$2"
  if [[ -f "$file_path" ]]; then
    local value
    value="$(<"$file_path")"
    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return 0
    fi
  fi
  printf '%s' "$default_value"
}

read_int_file_or_default() {
  local file_path="$1"
  local default_value="$2"
  local raw
  raw="$(read_file_or_default "$file_path" "$default_value")"
  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    printf '%s' "$raw"
  else
    printf '%s' "$default_value"
  fi
}

trim_spaces() {
  local value="$1"
  value="$(printf '%s' "$value" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  printf '%s' "$value"
}

file_mtime_epoch() {
  local file_path="$1"
  if [[ ! -f "$file_path" ]]; then
    printf '0'
    return 0
  fi
  if stat -f %m "$file_path" >/dev/null 2>&1; then
    stat -f %m "$file_path"
  elif stat -c %Y "$file_path" >/dev/null 2>&1; then
    stat -c %Y "$file_path"
  else
    printf '0'
  fi
}

age_from_epoch() {
  local ts="$1"
  if ! [[ "$ts" =~ ^[0-9]+$ ]]; then
    printf '0'
    return 0
  fi
  if (( ts <= 0 || now_epoch < ts )); then
    printf '0'
    return 0
  fi
  printf '%s' "$(( now_epoch - ts ))"
}

format_duration_human() {
  local total_sec="${1:-0}"
  local hours minutes seconds

  if ! [[ "$total_sec" =~ ^-?[0-9]+$ ]]; then
    total_sec=0
  fi
  if (( total_sec < 0 )); then
    total_sec=0
  fi

  hours=$(( total_sec / 3600 ))
  minutes=$(( (total_sec % 3600) / 60 ))
  seconds=$(( total_sec % 60 ))

  if (( hours > 0 )); then
    printf '%sh %sm %ss' "$hours" "$minutes" "$seconds"
  elif (( minutes > 0 )); then
    printf '%sm %ss' "$minutes" "$seconds"
  else
    printf '%ss' "$seconds"
  fi
}

detail_value() {
  local detail="$1"
  local key="$2"
  local line value
  while IFS= read -r line; do
    line="$(trim_spaces "$line")"
    [[ -z "$line" ]] && continue
    if [[ "$line" == "${key}="* ]]; then
      value="${line#*=}"
      printf '%s' "$value"
      return 0
    fi
  done < <(printf '%s' "$detail" | tr '|' ';' | tr ';' '\n')
  printf ''
}

count_pending_outbox() {
  local outbox_dir
  outbox_dir="$(codex_resolve_state_outbox_dir "$CODEX_DIR")"
  if [[ ! -d "$outbox_dir" ]]; then
    printf '0'
    return 0
  fi
  find "$outbox_dir" -maxdepth 1 -type f -name '*.json' -size +0c 2>/dev/null | wc -l | tr -d ' '
}

runtime_queue_pending() {
  local queue_file="${CODEX_DIR}/project_status_runtime_queue.json"
  if [[ ! -f "$queue_file" ]]; then
    printf '0'
    return 0
  fi
  jq -r '((.items // []) | length)' "$queue_file" 2>/dev/null || printf '0'
}

backlog_seed_remaining() {
  local plan_file="${CODEX_DIR}/backlog_seed_plan.json"
  if [[ ! -f "$plan_file" ]]; then
    printf '0'
    return 0
  fi
  jq -r '((.tasks // []) | length)' "$plan_file" 2>/dev/null || printf '0'
}

backlog_seed_next_code() {
  local plan_file="${CODEX_DIR}/backlog_seed_plan.json"
  if [[ ! -f "$plan_file" ]]; then
    printf ''
    return 0
  fi
  jq -r '((.tasks // [])[0].code // "")' "$plan_file" 2>/dev/null || printf ''
}

severity_rank() {
  local value="$1"
  case "$value" in
    ERROR) echo 60 ;;
    BLOCKED) echo 50 ;;
    DEGRADED) echo 40 ;;
    WAITING_USER) echo 30 ;;
    WAITING_SYSTEM) echo 20 ;;
    WORKING) echo 10 ;;
    HEALTHY) echo 0 ;;
    *) echo 0 ;;
  esac
}

daemon_state_file="${CODEX_DIR}/daemon_state.txt"
daemon_detail_file="${CODEX_DIR}/daemon_state_detail.txt"
watchdog_state_file="${CODEX_DIR}/watchdog_state.txt"
watchdog_detail_file="${CODEX_DIR}/watchdog_state_detail.txt"
watchdog_action_file="${CODEX_DIR}/watchdog_last_action.txt"
watchdog_action_epoch_file="${CODEX_DIR}/watchdog_last_action_epoch.txt"

executor_state_file="${CODEX_DIR}/executor_state.txt"
executor_pid_file="${CODEX_DIR}/executor_pid.txt"
executor_hb_epoch_file="${CODEX_DIR}/executor_heartbeat_epoch.txt"
executor_hb_utc_file="${CODEX_DIR}/executor_heartbeat_utc.txt"

rate_window_state_file="${CODEX_DIR}/graphql_rate_window_state.txt"
rate_window_requests_file="${CODEX_DIR}/graphql_rate_window_requests.txt"
rate_window_start_utc_file="${CODEX_DIR}/graphql_rate_window_start_utc.txt"
rate_last_success_file="${CODEX_DIR}/graphql_rate_last_success_utc.txt"
rate_last_limit_file="${CODEX_DIR}/graphql_rate_last_limit_utc.txt"

daemon_log_file="${CODEX_DIR}/daemon.log"
daemon_log_file="${RUNTIME_LOG_DIR}/daemon.log"
watchdog_log_file="${RUNTIME_LOG_DIR}/watchdog.log"

daemon_state="$(read_file_or_default "$daemon_state_file" "UNKNOWN")"
daemon_detail="$(read_file_or_default "$daemon_detail_file" "")"
watchdog_state="$(read_file_or_default "$watchdog_state_file" "UNKNOWN")"
watchdog_detail="$(read_file_or_default "$watchdog_detail_file" "")"
watchdog_last_action="$(read_file_or_default "$watchdog_action_file" "")"
watchdog_last_action_epoch="$(read_int_file_or_default "$watchdog_action_epoch_file" "0")"

executor_state="$(read_file_or_default "$executor_state_file" "")"
executor_pid="$(read_file_or_default "$executor_pid_file" "")"
executor_hb_epoch="$(read_int_file_or_default "$executor_hb_epoch_file" "0")"
executor_hb_utc="$(read_file_or_default "$executor_hb_utc_file" "")"
executor_pid_alive="false"
if [[ "$executor_pid" =~ ^[0-9]+$ ]] && kill -0 "$executor_pid" >/dev/null 2>&1; then
  executor_pid_alive="true"
fi

watchdog_executor_state="$(detail_value "$watchdog_detail" "executor_state")"
watchdog_executor_pid="$(detail_value "$watchdog_detail" "executor_pid")"
watchdog_executor_pid_alive="$(detail_value "$watchdog_detail" "executor_pid_alive")"

if [[ -z "$executor_state" ]]; then
  if [[ -n "$watchdog_executor_state" && "$watchdog_executor_state" != "none" ]]; then
    executor_state="$watchdog_executor_state"
  elif [[ "$watchdog_state" == "HEALTHY" ]]; then
    executor_state="IDLE"
  else
    executor_state="UNKNOWN"
  fi
fi

if [[ -z "$executor_pid" || "$executor_pid" == "none" ]]; then
  if [[ -n "$watchdog_executor_pid" && "$watchdog_executor_pid" != "none" ]]; then
    executor_pid="$watchdog_executor_pid"
  else
    executor_pid="none"
  fi
fi

if [[ "$executor_pid_alive" != "true" ]]; then
  case "$watchdog_executor_pid_alive" in
    1|true|TRUE|yes|YES|on|ON)
      executor_pid_alive="true"
      ;;
  esac
fi

rate_window_state="$(read_file_or_default "$rate_window_state_file" "")"
rate_window_requests="$(read_int_file_or_default "$rate_window_requests_file" "0")"
rate_window_start_utc="$(read_file_or_default "$rate_window_start_utc_file" "")"
rate_last_success_utc="$(read_file_or_default "$rate_last_success_file" "")"
rate_last_limit_utc="$(read_file_or_default "$rate_last_limit_file" "")"

github_status="$(detail_value "$daemon_detail" "GITHUB_STATUS")"
telegram_status="$(detail_value "$daemon_detail" "TELEGRAM_STATUS")"
dirty_blocking_todo="$(detail_value "$daemon_detail" "WAIT_DIRTY_WORKTREE_BLOCKING_TODO")"
dirty_tracked_count="$(detail_value "$daemon_detail" "WAIT_DIRTY_WORKTREE_TRACKED_COUNT")"
dirty_tracked_files="$(detail_value "$daemon_detail" "WAIT_DIRTY_WORKTREE_TRACKED_FILES")"
open_pr_count="$(detail_value "$daemon_detail" "WAIT_OPEN_PR_COUNT")"
dependencies_blockers="$(detail_value "$daemon_detail" "WAIT_DEPENDENCIES_BLOCKERS")"
active_task_id="$(detail_value "$daemon_detail" "WAIT_ACTIVE_TASK_ID")"
auth_degraded="$(detail_value "$daemon_detail" "AUTH_DEGRADED")"
github_rate_limit_stage="$(detail_value "$daemon_detail" "WAIT_GITHUB_RATE_LIMIT_STAGE")"
github_rate_limit_msg="$(detail_value "$daemon_detail" "WAIT_GITHUB_RATE_LIMIT_MSG")"
github_rate_limit_remaining="$(detail_value "$daemon_detail" "WAIT_GITHUB_RATE_LIMIT_REMAINING")"
github_rate_limit_reset_epoch="$(detail_value "$daemon_detail" "WAIT_GITHUB_RATE_LIMIT_RESET_EPOCH")"
github_rate_limit_reset_at="$(detail_value "$daemon_detail" "WAIT_GITHUB_RATE_LIMIT_RESET_AT")"
github_rate_limit_reset_human="$(detail_value "$daemon_detail" "WAIT_GITHUB_RATE_LIMIT_RESET_IN_HUMAN")"
github_auth_stage="$(detail_value "$daemon_detail" "WAIT_GITHUB_AUTH_STAGE")"
github_auth_msg="$(detail_value "$daemon_detail" "WAIT_GITHUB_AUTH_MSG")"
github_auth_source="$(detail_value "$daemon_detail" "WAIT_GITHUB_AUTH_SOURCE")"

[[ -z "$github_status" ]] && github_status="UNKNOWN"
[[ -z "$telegram_status" ]] && telegram_status="SKIPPED"
[[ -z "$dirty_blocking_todo" ]] && dirty_blocking_todo="0"
[[ -z "$dirty_tracked_count" ]] && dirty_tracked_count="0"
[[ -z "$open_pr_count" ]] && open_pr_count="0"
[[ -z "$github_rate_limit_remaining" ]] && github_rate_limit_remaining="0"

github_rate_limit_reset_in_sec="0"
if [[ "$github_rate_limit_reset_epoch" =~ ^[0-9]+$ ]] && (( github_rate_limit_reset_epoch > now_epoch )); then
  github_rate_limit_reset_in_sec="$(( github_rate_limit_reset_epoch - now_epoch ))"
fi
if [[ -z "$github_rate_limit_reset_human" || "$github_rate_limit_reset_human" == "0s" ]] && [[ "$github_rate_limit_reset_in_sec" =~ ^[0-9]+$ ]]; then
  github_rate_limit_reset_human="$(format_duration_human "$github_rate_limit_reset_in_sec")"
fi

outbox_pending="$(count_pending_outbox)"
runtime_pending="$(runtime_queue_pending)"
backlog_remaining="$(backlog_seed_remaining)"
backlog_next_code="$(backlog_seed_next_code)"
backlog_plan_present="false"
if [[ -f "${CODEX_DIR}/backlog_seed_plan.json" ]]; then
  backlog_plan_present="true"
fi
runtime_v2_json="$(/bin/bash "${SCRIPT_DIR}/runtime_v2_inspect.sh" --compact 2>/dev/null || printf '{}')"
if [[ -z "$runtime_v2_json" ]]; then
  runtime_v2_json='{}'
fi

daemon_state_age_sec="$(age_from_epoch "$(file_mtime_epoch "$daemon_state_file")")"
daemon_log_age_sec="$(age_from_epoch "$(file_mtime_epoch "$daemon_log_file")")"
watchdog_state_age_sec="$(age_from_epoch "$(file_mtime_epoch "$watchdog_state_file")")"
watchdog_log_age_sec="$(age_from_epoch "$(file_mtime_epoch "$watchdog_log_file")")"
watchdog_last_action_age_sec="$(age_from_epoch "$watchdog_last_action_epoch")"
executor_heartbeat_age_sec="$(age_from_epoch "$executor_hb_epoch")"

overall_status="HEALTHY"
action_required="none"
headline="Automation healthy"

case "$daemon_state" in
  ERROR_LOCAL_FLOW)
    overall_status="ERROR"
    action_required="inspect_logs"
    headline="Local flow error; inspect daemon/executor logs"
    ;;
  BLOCKED_*)
    overall_status="BLOCKED"
    action_required="inspect_blocker"
    headline="Flow blocked by local condition"
    ;;
  WAIT_GITHUB_RATE_LIMIT)
    overall_status="DEGRADED"
    action_required="wait_github"
    headline="GitHub GraphQL rate limit; daemon is waiting"
    if [[ -n "$github_rate_limit_reset_human" && "$github_rate_limit_reset_human" != "0s" ]]; then
      headline="GitHub GraphQL rate limit; reset in ${github_rate_limit_reset_human}"
    fi
    ;;
  WAIT_GITHUB_AUTH)
    overall_status="DEGRADED"
    action_required="fix_github_auth"
    headline="GitHub project credential rejected; daemon is waiting for config fix"
    ;;
  WAIT_GITHUB_OFFLINE|WAIT_AUTH_SERVICE)
    overall_status="DEGRADED"
    action_required="wait_github"
    headline="GitHub/auth service unavailable; waiting for recovery"
    ;;
  WAIT_USER_REPLY|WAIT_REVIEW_FEEDBACK)
    overall_status="WAITING_USER"
    action_required="user_reply"
    headline="Waiting for user feedback in issue comments"
    ;;
  INTERACTIVE_ONLY)
    overall_status="HEALTHY"
    action_required="none"
    headline="Interactive-only checkout; automation disabled"
    ;;
  WAIT_RUNTIME_OWNERSHIP)
    overall_status="WAITING_SYSTEM"
    action_required="fix_runtime_ownership"
    headline="Runtime ownership points to another host"
    ;;
  WAIT_DIRTY_WORKTREE)
    if [[ "$dirty_blocking_todo" == "1" ]]; then
      overall_status="BLOCKED"
      action_required="clean_worktree"
      headline="Dirty worktree blocks Todo claim"
    else
      overall_status="WORKING"
      action_required="none"
      headline="Dirty worktree detected (non-blocking, no Todo blocker)"
    fi
    ;;
  WAIT_OPEN_PR)
    overall_status="WAITING_SYSTEM"
    action_required="merge_pr"
    headline="Waiting for open development->main PR"
    ;;
  WAIT_DEPENDENCIES)
    overall_status="WAITING_SYSTEM"
    action_required="resolve_dependencies"
    headline="Waiting for dependency tasks to be completed"
    ;;
  WAIT_ACTIVE_TASK|EXECUTOR_RUNNING|EXECUTOR_STARTED|EXECUTOR_DONE|ACTIVE_TASK_CLAIMED)
    overall_status="WORKING"
    action_required="none"
    headline="Executor is processing the active task"
    ;;
  WAIT_BRANCH_SYNC|WAIT_EXECUTOR_RESTART_COOLDOWN)
    overall_status="WAITING_SYSTEM"
    action_required="none"
    headline="Waiting for branch/executor sync condition"
    ;;
  IDLE_NO_TASKS|IDLE_NO_ISSUE_TASKS)
    if [[ "$backlog_plan_present" == "true" && "$backlog_remaining" =~ ^[0-9]+$ ]] && (( backlog_remaining > 0 )); then
      overall_status="WORKING"
      action_required="none"
      headline="Runtime backlog-seed is creating tasks"
    else
      overall_status="HEALTHY"
      action_required="none"
      headline="Idle: no Todo tasks"
    fi
    ;;
  *)
    overall_status="WORKING"
    action_required="none"
    headline="Daemon active"
    ;;
esac

watchdog_effect="HEALTHY"
case "$watchdog_state" in
  HEALTHY)
    watchdog_effect="HEALTHY"
    ;;
  PAUSED_DIRTY_WORKTREE)
    watchdog_effect="WAITING_SYSTEM"
    ;;
  INTERACTIVE_ONLY)
    watchdog_effect="HEALTHY"
    ;;
  WAIT_RUNTIME_OWNERSHIP)
    watchdog_effect="WAITING_SYSTEM"
    ;;
  WAIT_AUTH_SERVICE|DEGRADED*|RECOVERY*|ERROR*)
    watchdog_effect="DEGRADED"
    ;;
  *)
    watchdog_effect="WAITING_SYSTEM"
    ;;
esac

if (( $(severity_rank "$watchdog_effect") > $(severity_rank "$overall_status") )); then
  overall_status="$watchdog_effect"
  if [[ "$watchdog_effect" == "DEGRADED" && "$action_required" == "none" ]]; then
    action_required="inspect_watchdog"
    headline="Watchdog indicates degraded state"
  fi
fi

jq -n \
  --arg generated_at "$now_utc" \
  --arg overall_status "$overall_status" \
  --arg action_required "$action_required" \
  --arg headline "$headline" \
  --arg project_profile "$project_profile" \
  --arg project_repo "$project_repo" \
  --arg project_label "$project_label" \
  --arg runtime_role "$runtime_role" \
  --arg runtime_instance_id "$runtime_instance_id" \
  --arg authoritative_runtime_id "$authoritative_runtime_id" \
  --arg state_dir "$CODEX_DIR" \
  --arg flow_logs_dir "$FLOW_LOGS_DIR" \
  --arg runtime_log_dir "$RUNTIME_LOG_DIR" \
  --arg daemon_state "$daemon_state" \
  --arg daemon_detail "$daemon_detail" \
  --arg watchdog_state "$watchdog_state" \
  --arg watchdog_detail "$watchdog_detail" \
  --arg watchdog_last_action "$watchdog_last_action" \
  --arg executor_state "$executor_state" \
  --arg executor_pid "$executor_pid" \
  --arg executor_hb_utc "$executor_hb_utc" \
  --arg github_status "$github_status" \
  --arg telegram_status "$telegram_status" \
  --arg auth_degraded "$auth_degraded" \
  --arg dirty_blocking_todo "$dirty_blocking_todo" \
  --arg dirty_tracked_count "$dirty_tracked_count" \
  --arg dirty_tracked_files "$dirty_tracked_files" \
  --arg open_pr_count "$open_pr_count" \
  --arg dependencies_blockers "$dependencies_blockers" \
  --arg active_task_id "$active_task_id" \
  --arg github_rate_limit_stage "$github_rate_limit_stage" \
  --arg github_rate_limit_msg "$github_rate_limit_msg" \
  --arg github_rate_limit_remaining "$github_rate_limit_remaining" \
  --arg github_rate_limit_reset_at "$github_rate_limit_reset_at" \
  --arg github_rate_limit_reset_human "$github_rate_limit_reset_human" \
  --arg rate_window_state "$rate_window_state" \
  --arg rate_window_start_utc "$rate_window_start_utc" \
  --arg rate_last_success_utc "$rate_last_success_utc" \
  --arg rate_last_limit_utc "$rate_last_limit_utc" \
  --arg backlog_next_code "$backlog_next_code" \
  --argjson daemon_state_age_sec "$daemon_state_age_sec" \
  --argjson daemon_log_age_sec "$daemon_log_age_sec" \
  --argjson watchdog_state_age_sec "$watchdog_state_age_sec" \
  --argjson watchdog_log_age_sec "$watchdog_log_age_sec" \
  --argjson watchdog_last_action_age_sec "$watchdog_last_action_age_sec" \
  --argjson executor_heartbeat_age_sec "$executor_heartbeat_age_sec" \
  --argjson outbox_pending "$outbox_pending" \
  --argjson runtime_pending "$runtime_pending" \
  --argjson rate_window_requests "$rate_window_requests" \
  --argjson github_rate_limit_reset_in_sec "$github_rate_limit_reset_in_sec" \
  --argjson backlog_remaining "$backlog_remaining" \
  --argjson executor_pid_alive "$executor_pid_alive" \
  --argjson backlog_plan_present "$backlog_plan_present" \
  --argjson runtime_v2 "$runtime_v2_json" \
  '{
    generated_at: $generated_at,
    project: {
      profile: $project_profile,
      repo: $project_repo,
      label: $project_label,
      runtime_role: $runtime_role,
      runtime_instance_id: $runtime_instance_id,
      authoritative_runtime_id: $authoritative_runtime_id,
      state_dir: $state_dir,
      log_dir: $flow_logs_dir,
      runtime_log_dir: $runtime_log_dir
    },
    overall_status: $overall_status,
    action_required: $action_required,
    headline: $headline,
    daemon: {
      state: $daemon_state,
      detail: $daemon_detail,
      state_age_sec: $daemon_state_age_sec,
      log_age_sec: $daemon_log_age_sec,
      github_status: $github_status,
      telegram_status: $telegram_status,
      auth_degraded: ($auth_degraded == "1")
    },
    watchdog: {
      state: $watchdog_state,
      detail: $watchdog_detail,
      state_age_sec: $watchdog_state_age_sec,
      log_age_sec: $watchdog_log_age_sec,
      last_action: $watchdog_last_action,
      last_action_age_sec: $watchdog_last_action_age_sec
    },
    executor: {
      state: $executor_state,
      pid: $executor_pid,
      pid_alive: $executor_pid_alive,
      heartbeat_utc: $executor_hb_utc,
      heartbeat_age_sec: $executor_heartbeat_age_sec
    },
    queues: {
      outbox_pending: $outbox_pending,
      runtime_status_pending: $runtime_pending
    },
    blockers: {
      dirty_worktree: {
        blocking_todo: ($dirty_blocking_todo == "1"),
        tracked_count: ($dirty_tracked_count | tonumber? // 0),
        tracked_files: $dirty_tracked_files
      },
      dependencies: {
        blockers: $dependencies_blockers
      },
      open_pr_count: ($open_pr_count | tonumber? // 0),
      active_task_id: $active_task_id
    },
    rate_limit: {
      wait_stage: $github_rate_limit_stage,
      wait_message: $github_rate_limit_msg,
      wait_remaining: ($github_rate_limit_remaining | tonumber? // 0),
      wait_reset_at_utc: $github_rate_limit_reset_at,
      wait_reset_in_sec: $github_rate_limit_reset_in_sec,
      wait_reset_in_human: $github_rate_limit_reset_human,
      window_state: $rate_window_state,
      window_requests: $rate_window_requests,
      window_start_utc: $rate_window_start_utc,
      last_success_utc: $rate_last_success_utc,
      last_limit_utc: $rate_last_limit_utc
    },
    backlog_seed: {
      plan_present: $backlog_plan_present,
      remaining: $backlog_remaining,
      next_code: $backlog_next_code
    },
    runtime_v2: $runtime_v2
  }'
