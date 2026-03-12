#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
codex_load_flow_env
CODEX_DIR="$(codex_export_state_dir)"
RUNTIME_LOG_DIR="$(codex_resolve_flow_runtime_log_dir)"
STATE_TMP_DIR="$(codex_resolve_state_tmp_dir "$CODEX_DIR")"
DAEMON_STATE_DIR="$(codex_resolve_state_daemon_dir "$CODEX_DIR")"
PROJECT_LABEL="$(codex_resolve_project_display_label)"
LOCK_DIR="${DAEMON_STATE_DIR}/lock"
LOCK_OWNER_FILE="${LOCK_DIR}/owner.pid"
LOG_FILE="${RUNTIME_LOG_DIR}/daemon.log"
STATE_FILE="${CODEX_DIR}/daemon_state.txt"
STATE_DETAIL_FILE="${CODEX_DIR}/daemon_state_detail.txt"
NOTIFY_MODE_FILE="${CODEX_DIR}/daemon_notify_mode.txt"
NOTIFY_EPOCH_FILE="${CODEX_DIR}/daemon_notify_last_epoch.txt"
NOTIFY_SIGNATURE_FILE="${CODEX_DIR}/daemon_notify_last_signature.txt"
GITHUB_RUNTIME_NOTIFY_MODE_FILE="${CODEX_DIR}/daemon_github_runtime_notify_mode.txt"

interval="${1:-${DAEMON_INTERVAL_SEC:-45}}"
if ! [[ "$interval" =~ ^[0-9]+$ ]] || (( interval < 5 )); then
  echo "Invalid interval: '$interval' (expected integer >= 5 sec)"
  exit 1
fi

rate_limit_backoff_base_sec="${DAEMON_RATE_LIMIT_BACKOFF_BASE_SEC:-$interval}"
if ! [[ "$rate_limit_backoff_base_sec" =~ ^[0-9]+$ ]] || (( rate_limit_backoff_base_sec < 5 )); then
  rate_limit_backoff_base_sec="$interval"
fi
if (( rate_limit_backoff_base_sec < interval )); then
  rate_limit_backoff_base_sec="$interval"
fi

rate_limit_backoff_max_sec="${DAEMON_RATE_LIMIT_MAX_SLEEP_SEC:-360}"
if ! [[ "$rate_limit_backoff_max_sec" =~ ^[0-9]+$ ]] || (( rate_limit_backoff_max_sec < rate_limit_backoff_base_sec )); then
  rate_limit_backoff_max_sec="$rate_limit_backoff_base_sec"
fi

mkdir -p "$CODEX_DIR" "$RUNTIME_LOG_DIR" "$STATE_TMP_DIR" "$DAEMON_STATE_DIR"

stale_lock_recovered="0"
stale_lock_owner_pid=""

acquire_lock_dir() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" > "$LOCK_OWNER_FILE"
    return 0
  fi

  local owner_pid=""
  if [[ -s "$LOCK_OWNER_FILE" ]]; then
    owner_pid="$(tr -d '\r\n' < "$LOCK_OWNER_FILE" 2>/dev/null || true)"
  fi

  if [[ "$owner_pid" =~ ^[0-9]+$ ]] && kill -0 "$owner_pid" 2>/dev/null; then
    echo "Daemon already running (lock: $LOCK_DIR pid=$owner_pid)"
    return 1
  fi

  stale_lock_recovered="1"
  stale_lock_owner_pid="${owner_pid:-unknown}"
  rm -f "$LOCK_OWNER_FILE" 2>/dev/null || true
  rmdir "$LOCK_DIR" 2>/dev/null || true

  if mkdir "$LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" > "$LOCK_OWNER_FILE"
    return 0
  fi

  echo "Daemon already running (lock: $LOCK_DIR)"
  return 1
}

if ! acquire_lock_dir; then
  exit 1
fi

cleanup() {
  rm -f "$LOCK_OWNER_FILE" 2>/dev/null || true
  rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

log() {
  local ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf '%s %s\n' "$ts" "$*" >> "$LOG_FILE"
}

resolve_config_value() {
  codex_resolve_config_value "$@"
}

is_truthy() {
  local raw_value="$1"
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

AUTH_LAST_DETAIL=""
AUTH_RUNTIME_DETAIL=""
AUTH_FALLBACK_ENABLED="0"
AUTH_FALLBACK_TOKEN_PRESENT="0"
AUTH_FALLBACK_REASON="DISABLED"
AUTH_FALLBACK_SOURCE=""

refresh_daemon_github_token() {
  local auth_log_file token line rc fallback_enabled_raw fallback_token
  AUTH_LAST_DETAIL=""
  AUTH_RUNTIME_DETAIL=""
  AUTH_FALLBACK_ENABLED="0"
  AUTH_FALLBACK_TOKEN_PRESENT="0"
  AUTH_FALLBACK_REASON="DISABLED"
  AUTH_FALLBACK_SOURCE=""
  auth_log_file="$(mktemp "${STATE_TMP_DIR}/daemon_auth.XXXXXX")"

  fallback_enabled_raw="$(resolve_config_value "DAEMON_GH_TOKEN_FALLBACK_ENABLED" "")"
  if [[ -z "$fallback_enabled_raw" ]]; then
    fallback_enabled_raw="$(resolve_config_value "CODEX_GH_TOKEN_FALLBACK_ENABLED" "0")"
  fi
  if is_truthy "$fallback_enabled_raw"; then
    AUTH_FALLBACK_ENABLED="1"
    AUTH_FALLBACK_REASON="TOKEN_MISSING"
  fi

  fallback_token="$(resolve_config_value "DAEMON_GH_TOKEN" "")"
  if [[ -n "$fallback_token" ]]; then
    AUTH_FALLBACK_SOURCE="DAEMON_GH_TOKEN"
  else
    fallback_token="$(resolve_config_value "CODEX_GH_TOKEN" "")"
    if [[ -n "$fallback_token" ]]; then
      AUTH_FALLBACK_SOURCE="CODEX_GH_TOKEN"
    fi
  fi
  fallback_token="$(printf '%s' "$fallback_token" | tr -d '\r\n')"
  if [[ -n "$fallback_token" ]]; then
    AUTH_FALLBACK_TOKEN_PRESENT="1"
  fi

  if token="$("${CODEX_SHARED_SCRIPTS_DIR}/gh_app_auth_token.sh" 2>"$auth_log_file")"; then
    token="$(printf '%s' "$token" | tr -d '\r\n')"
    if [[ -z "$token" ]]; then
      rm -f "$auth_log_file"
      AUTH_LAST_DETAIL="AUTH_ERROR_CODE=AUTH_SERVICE_BAD_PAYLOAD"
      return 1
    fi
    export GH_TOKEN="$token"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      log "AUTH: $line"
    done < "$auth_log_file"
    rm -f "$auth_log_file"
    return 0
  else
    rc=$?
  fi
  unset GH_TOKEN || true
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ -z "$AUTH_LAST_DETAIL" ]] && AUTH_LAST_DETAIL="$line"
    log "AUTH_ERROR(rc=$rc): $line"
  done < "$auth_log_file"
  rm -f "$auth_log_file"
  if [[ -z "$AUTH_LAST_DETAIL" ]]; then
    AUTH_LAST_DETAIL="AUTH_ERROR_CODE=AUTH_SERVICE_UNREACHABLE"
  fi

  if [[ "$AUTH_FALLBACK_ENABLED" == "1" && "$AUTH_FALLBACK_TOKEN_PRESENT" == "1" ]]; then
    export GH_TOKEN="$fallback_token"
    AUTH_FALLBACK_REASON="ACTIVE"
    AUTH_RUNTIME_DETAIL="AUTH_DEGRADED=1; DEGRADED=AUTH_SERVICE_UNAVAILABLE; AUTH_MODE=PAT_FALLBACK; AUTH_FALLBACK_SOURCE=${AUTH_FALLBACK_SOURCE}; AUTH_PRIMARY_RC=${rc}; ${AUTH_LAST_DETAIL}"
    log "AUTH_FALLBACK_ACTIVE source=${AUTH_FALLBACK_SOURCE}; auth_rc=${rc}; auth_detail=${AUTH_LAST_DETAIL}"
    return 0
  fi

  if [[ "$AUTH_FALLBACK_ENABLED" == "1" ]]; then
    AUTH_FALLBACK_REASON="TOKEN_MISSING"
  fi
  return "$rc"
}

read_file_or_default() {
  local file_path="$1"
  local default_value="$2"
  if [[ -s "$file_path" ]]; then
    cat "$file_path"
  else
    printf '%s' "$default_value"
  fi
}

rate_limit_backoff_hits=0
rate_limit_backoff_next_sec="$rate_limit_backoff_base_sec"
loop_sleep_sec="$interval"

compute_loop_sleep_sec() {
  local state="$1"
  loop_sleep_sec="$interval"

  if [[ "$state" == "WAIT_GITHUB_RATE_LIMIT" ]]; then
    loop_sleep_sec="$rate_limit_backoff_next_sec"
    if (( loop_sleep_sec < rate_limit_backoff_base_sec )); then
      loop_sleep_sec="$rate_limit_backoff_base_sec"
    fi
    if (( loop_sleep_sec > rate_limit_backoff_max_sec )); then
      loop_sleep_sec="$rate_limit_backoff_max_sec"
    fi
    rate_limit_backoff_hits=$(( rate_limit_backoff_hits + 1 ))

    local next_sec
    next_sec=$(( loop_sleep_sec * 2 ))
    if (( next_sec > rate_limit_backoff_max_sec )); then
      next_sec="$rate_limit_backoff_max_sec"
    fi
    rate_limit_backoff_next_sec="$next_sec"
    return 0
  fi

  if (( rate_limit_backoff_hits > 0 )); then
    log "RATE_LIMIT_BACKOFF_RESET_AFTER_STATE=${state}"
  fi
  rate_limit_backoff_hits=0
  rate_limit_backoff_next_sec="$rate_limit_backoff_base_sec"
}

set_state() {
  local state="$1"
  local detail="${2:-}"
  printf '%s\n' "$state" > "$STATE_FILE"
  printf '%s\n' "$detail" > "$STATE_DETAIL_FILE"
  if [[ -n "$detail" ]]; then
    log "STATE=$state DETAIL=$detail"
  else
    log "STATE=$state"
  fi
}

classify_success_state() {
  local output="$1"
  if printf '%s' "$output" | grep -q '^WAIT_GITHUB_RATE_LIMIT=1'; then
    echo "WAIT_GITHUB_RATE_LIMIT"
  elif printf '%s' "$output" | grep -Eiq 'graphql:.*rate limit|api rate limit already exceeded|graphql_rate_limit|rate limit exceeded'; then
    echo "WAIT_GITHUB_RATE_LIMIT"
  elif printf '%s' "$output" | grep -q '^WAIT_GITHUB_API_UNSTABLE=1'; then
    echo "WAIT_GITHUB_OFFLINE"
  elif printf '%s' "$output" | grep -q '^WAIT_BRANCH_SYNC_REQUIRED=1'; then
    echo "WAIT_BRANCH_SYNC"
  elif printf '%s' "$output" | grep -q '^EXECUTOR_FAILED=1'; then
    echo "BLOCKED_EXECUTOR_FAILED"
  elif printf '%s' "$output" | grep -q '^BLOCKED_ACTIVE_TASK_WITHOUT_ISSUE=1'; then
    echo "BLOCKED_ACTIVE_TASK_WITHOUT_ISSUE"
  elif printf '%s' "$output" | grep -q '^EXECUTOR_RUNNING=1'; then
    echo "EXECUTOR_RUNNING"
  elif printf '%s' "$output" | grep -q '^EXECUTOR_STARTED=1'; then
    echo "EXECUTOR_STARTED"
  elif printf '%s' "$output" | grep -q '^EXECUTOR_DONE=1'; then
    echo "EXECUTOR_DONE"
  elif printf '%s' "$output" | grep -q '^EXECUTOR_WAIT_USER_REPLY=1'; then
    echo "WAIT_USER_REPLY"
  elif printf '%s' "$output" | grep -q '^WAIT_REVIEW_FEEDBACK=1'; then
    echo "WAIT_REVIEW_FEEDBACK"
  elif printf '%s' "$output" | grep -q '^CLAIMED_TASK_ID='; then
    echo "ACTIVE_TASK_CLAIMED"
  elif printf '%s' "$output" | grep -q '^USER_REPLY_RECEIVED=1'; then
    echo "USER_REPLY_RECEIVED"
  elif printf '%s' "$output" | grep -q '^WAIT_USER_REPLY=1'; then
    echo "WAIT_USER_REPLY"
  elif printf '%s' "$output" | grep -q '^WAIT_EXECUTOR_RESTART_COOLDOWN='; then
    echo "WAIT_EXECUTOR_RESTART_COOLDOWN"
  elif printf '%s' "$output" | grep -q '^WAIT_ACTIVE_TASK_ID='; then
    echo "WAIT_ACTIVE_TASK"
  elif printf '%s' "$output" | grep -q '^WAIT_OPEN_PR_COUNT='; then
    echo "WAIT_OPEN_PR"
  elif printf '%s' "$output" | grep -q '^WAIT_DEPENDENCIES=1'; then
    echo "WAIT_DEPENDENCIES"
  elif printf '%s' "$output" | grep -q '^WAIT_DIRTY_WORKTREE_TRACKED=1'; then
    echo "WAIT_DIRTY_WORKTREE"
  elif printf '%s' "$output" | grep -q '^BLOCKED_MULTIPLE_TRIGGER_TASKS='; then
    echo "BLOCKED_MULTIPLE_TRIGGER_TASKS"
  elif printf '%s' "$output" | grep -q '^BLOCKED_TRIGGER_TASKS_WITHOUT_TASK_ID='; then
    echo "BLOCKED_TASKS_WITHOUT_TASK_ID"
  elif printf '%s' "$output" | grep -q '^NO_ISSUE_TASKS_IN_TRIGGER_STATUS='; then
    echo "IDLE_NO_ISSUE_TASKS"
  elif printf '%s' "$output" | grep -q '^NO_TASKS_IN_TRIGGER_STATUS='; then
    echo "IDLE_NO_TASKS"
  else
    echo "OK"
  fi
}

build_success_detail() {
  local state="$1"
  local output="$2"
  local line=""

  case "$state" in
    BLOCKED_EXECUTOR_FAILED)
      line="$(printf '%s\n' "$output" | grep -m1 '^EXECUTOR_EXIT_CODE=' || true)"
      [[ -z "$line" ]] && line="$(printf '%s\n' "$output" | grep -m1 '^EXECUTOR_FAILED=1' || true)"
      ;;
    EXECUTOR_RUNNING)
      line="$(printf '%s\n' "$output" | grep -m1 '^EXECUTOR_PID=' || true)"
      [[ -z "$line" ]] && line="$(printf '%s\n' "$output" | grep -m1 '^EXECUTOR_RUNNING=1' || true)"
      ;;
    EXECUTOR_STARTED)
      line="$(printf '%s\n' "$output" | grep -m1 '^EXECUTOR_STARTED=1' || true)"
      ;;
    EXECUTOR_DONE)
      line="$(printf '%s\n' "$output" | grep -m1 '^EXECUTOR_DONE=1' || true)"
      ;;
    WAIT_USER_REPLY)
      line="$(printf '%s\n' "$output" | grep -m1 -E '^(WAIT_USER_REPLY=1|EXECUTOR_WAIT_USER_REPLY=1)' || true)"
      ;;
    WAIT_REVIEW_FEEDBACK)
      line="$(printf '%s\n' "$output" | grep -m1 '^QUESTION_KIND=' || true)"
      [[ -z "$line" ]] && line="$(printf '%s\n' "$output" | grep -m1 '^WAIT_REVIEW_FEEDBACK=1' || true)"
      ;;
    USER_REPLY_RECEIVED)
      line="$(printf '%s\n' "$output" | grep -m1 '^USER_REPLY_RECEIVED=1' || true)"
      ;;
    WAIT_OPEN_PR)
      line="$(printf '%s\n' "$output" | grep -m1 '^WAIT_OPEN_PR_COUNT=' || true)"
      ;;
    WAIT_DEPENDENCIES)
      line="$(printf '%s\n' "$output" | grep -m1 '^WAIT_DEPENDENCIES_BLOCKERS=' || true)"
      [[ -z "$line" ]] && line="$(printf '%s\n' "$output" | grep -m1 '^WAIT_DEPENDENCIES=1' || true)"
      ;;
    WAIT_GITHUB_OFFLINE)
      line="$(printf '%s\n' "$output" | grep -m1 -E '^(WAIT_GITHUB_STAGE=|WAIT_GITHUB_API_UNSTABLE=1)' || true)"
      ;;
    WAIT_GITHUB_RATE_LIMIT)
      local stage_line msg_line req_line dur_line raw_rate_line
      local parts=()
      stage_line="$(printf '%s\n' "$output" | grep -m1 '^WAIT_GITHUB_RATE_LIMIT_STAGE=' || true)"
      msg_line="$(printf '%s\n' "$output" | grep -m1 '^WAIT_GITHUB_RATE_LIMIT_MSG=' || true)"
      req_line="$(printf '%s\n' "$output" | grep -m1 '^GQL_STATS_WINDOW_REQUESTS=' || true)"
      dur_line="$(printf '%s\n' "$output" | grep -m1 '^GQL_STATS_WINDOW_DURATION_SEC=' || true)"
      raw_rate_line="$(printf '%s\n' "$output" | grep -m1 -Ei 'graphql:.*rate limit|api rate limit already exceeded|graphql_rate_limit|rate limit exceeded' || true)"
      parts+=("DEGRADED=GITHUB_GRAPHQL_RATE_LIMIT")
      [[ -z "$stage_line" ]] && stage_line="WAIT_GITHUB_RATE_LIMIT_STAGE=PROJECT_QUERY_OR_FALLBACK"
      if [[ -z "$msg_line" && -n "$raw_rate_line" ]]; then
        msg_line="WAIT_GITHUB_RATE_LIMIT_MSG=$raw_rate_line"
      fi
      [[ -n "$stage_line" ]] && parts+=("$stage_line")
      [[ -n "$msg_line" ]] && parts+=("$msg_line")
      [[ -n "$req_line" ]] && parts+=("$req_line")
      [[ -n "$dur_line" ]] && parts+=("$dur_line")
      line="$(IFS=';'; echo "${parts[*]}")"
      ;;
    WAIT_BRANCH_SYNC)
      line="$(printf '%s\n' "$output" | grep -m1 '^WAIT_BRANCH_SYNC_REQUIRED=1' || true)"
      [[ -z "$line" ]] && line="$(printf '%s\n' "$output" | grep -m1 '^WAIT_BRANCH_STAGE=' || true)"
      ;;
    WAIT_DIRTY_WORKTREE)
      line="$(printf '%s\n' "$output" | grep -m1 '^WAIT_DIRTY_WORKTREE_TRACKED=1' || true)"
      local dirty_count_line dirty_files_line dirty_blocked_ref_line dirty_blocked_issue_line dirty_blocked_title_line dirty_gate_issue_line dirty_gate_item_line
      local dirty_blocking_todo="0"
      dirty_count_line="$(printf '%s\n' "$output" | grep -m1 '^WAIT_DIRTY_WORKTREE_TRACKED_COUNT=' || true)"
      dirty_files_line="$(printf '%s\n' "$output" | grep -m1 '^WAIT_DIRTY_WORKTREE_TRACKED_FILES=' || true)"
      dirty_blocked_ref_line="$(printf '%s\n' "$output" | grep -m1 '^WAIT_DIRTY_WORKTREE_BLOCKED_REF=' || true)"
      dirty_blocked_issue_line="$(printf '%s\n' "$output" | grep -m1 '^WAIT_DIRTY_WORKTREE_BLOCKED_ISSUE_NUMBER=' || true)"
      dirty_blocked_title_line="$(printf '%s\n' "$output" | grep -m1 '^WAIT_DIRTY_WORKTREE_BLOCKED_ISSUE_TITLE=' || true)"
      dirty_gate_issue_line="$(printf '%s\n' "$output" | grep -m1 '^WAIT_DIRTY_WORKTREE_GATE_ISSUE_NUMBER=' || true)"
      dirty_gate_item_line="$(printf '%s\n' "$output" | grep -m1 '^WAIT_DIRTY_WORKTREE_GATE_PROJECT_ITEM_ID=' || true)"
      [[ -n "$dirty_count_line" ]] && line="${line}; ${dirty_count_line}"
      [[ -n "$dirty_files_line" ]] && line="${line}; ${dirty_files_line}"
      [[ -n "$dirty_blocked_ref_line" ]] && line="${line}; ${dirty_blocked_ref_line}"
      [[ -n "$dirty_blocked_issue_line" ]] && line="${line}; ${dirty_blocked_issue_line}"
      [[ -n "$dirty_blocked_title_line" ]] && line="${line}; ${dirty_blocked_title_line}"
      [[ -n "$dirty_gate_issue_line" ]] && line="${line}; ${dirty_gate_issue_line}"
      [[ -n "$dirty_gate_item_line" ]] && line="${line}; ${dirty_gate_item_line}"
      if [[ -n "$dirty_blocked_ref_line" ]]; then
        dirty_blocking_todo="1"
      fi
      line="${line}; WAIT_DIRTY_WORKTREE_BLOCKING_TODO=${dirty_blocking_todo}"
      ;;
    ACTIVE_TASK_CLAIMED)
      line="$(printf '%s\n' "$output" | grep -m1 '^CLAIMED_TASK_ID=' || true)"
      ;;
  esac

  if [[ -z "$line" ]]; then
    line="$(printf '%s\n' "$output" | awk 'NF {print; exit}')"
  fi
  printf '%s' "$line"
}

classify_error_state() {
  local output="$1"
  if printf '%s' "$output" | grep -Eiq 'graphql:.*rate limit|api rate limit exceeded|rate limit exceeded'; then
    echo "WAIT_GITHUB_RATE_LIMIT"
  elif printf '%s' "$output" | grep -Eiq 'error connecting to api\.github\.com|could not resolve host: api\.github\.com|could not resolve host: github\.com|connection timed out|tls handshake timeout|temporary failure in name resolution|failed to connect'; then
    echo "WAIT_GITHUB_OFFLINE"
  else
    echo "ERROR_LOCAL_FLOW"
  fi
}

classify_probe_status() {
  local probe_out="$1"
  if printf '%s' "$probe_out" | grep -Eiq 'could not resolve host|temporary failure in name resolution'; then
    echo "DNS_OFFLINE"
  elif printf '%s' "$probe_out" | grep -Eiq 'connection timed out|operation timed out|tls handshake timeout|failed to connect'; then
    echo "UNREACHABLE"
  else
    echo "UNSTABLE"
  fi
}

probe_http_status() {
  local url="$1"
  local probe_out
  if probe_out="$(curl -sS -o /dev/null --max-time 5 "$url" 2>&1)"; then
    echo "OK"
    return 0
  fi
  classify_probe_status "$probe_out"
  return 1
}

detect_flow_degradation() {
  local parts=()
  local pending_outbox_count="0"
  local outbox_dir
  outbox_dir="$(codex_resolve_state_outbox_dir "$CODEX_DIR")"
  if [[ -d "$outbox_dir" ]]; then
    pending_outbox_count="$(
      find "$outbox_dir" -maxdepth 1 -type f -name '*.json' -size +0c 2>/dev/null | wc -l | tr -d ' '
    )"
  fi
  if [[ "${pending_outbox_count}" != "0" ]]; then
    parts+=("DEGRADED=PENDING_OUTBOX:${pending_outbox_count}")
  fi

  local github_status
  github_status="$(probe_http_status "https://api.github.com")"
  parts+=("GITHUB_STATUS=${github_status}")
  if [[ "$github_status" != "OK" ]]; then
    if [[ "$github_status" == "DNS_OFFLINE" ]]; then
      parts+=("DEGRADED=GITHUB_DNS_OFFLINE")
    elif [[ "$github_status" == "UNREACHABLE" ]]; then
      parts+=("DEGRADED=GITHUB_API_UNREACHABLE")
    else
      parts+=("DEGRADED=GITHUB_UNSTABLE")
    fi
  fi

  # При DNS-деградации GitHub дополнительно проверяем Telegram-канал.
  # Это позволяет явно сигнализировать в бот, что проблема именно в GitHub-пути.
  if [[ "$github_status" == "DNS_OFFLINE" ]]; then
    local telegram_status
    telegram_status="$(probe_http_status "https://api.telegram.org")"
    parts+=("TELEGRAM_STATUS=${telegram_status}")
    parts+=("CHECK_TELEGRAM=${telegram_status}")
    if [[ "$telegram_status" == "OK" ]]; then
      parts+=("TELEGRAM_NOTIFY_ROUTE=AVAILABLE")
    elif [[ "$telegram_status" == "DNS_OFFLINE" ]]; then
      parts+=("DEGRADED=TELEGRAM_DNS_OFFLINE")
    elif [[ "$telegram_status" == "UNREACHABLE" ]]; then
      parts+=("DEGRADED=TELEGRAM_API_UNREACHABLE")
    else
      parts+=("DEGRADED=TELEGRAM_UNSTABLE")
    fi
  else
    parts+=("TELEGRAM_STATUS=SKIPPED")
  fi

  if (( ${#parts[@]} > 0 )); then
    local joined
    joined="$(IFS=';'; echo "${parts[*]}")"
    echo "$joined"
  else
    echo ""
  fi
}

runtime_queue_count() {
  local queue_file="${CODEX_DIR}/project_status_runtime_queue.json"
  local count="0"
  if [[ -f "$queue_file" ]]; then
    count="$(jq -r '(.items // []) | length' "$queue_file" 2>/dev/null || echo 0)"
  fi
  if ! [[ "$count" =~ ^[0-9]+$ ]]; then
    count="0"
  fi
  printf '%s' "$count"
}

push_remote_status_if_needed() {
  local push_out rc
  if push_out="$("${CODEX_SHARED_SCRIPTS_DIR}/ops_remote_status_push.sh" 2>&1)"; then
    while IFS= read -r line; do
      [[ -z "$line" || "$line" == "OPS_REMOTE_PUSH_SKIPPED=URL_NOT_CONFIGURED" || "$line" == "OPS_REMOTE_PUSH_SKIPPED=DISABLED" ]] && continue
      log "$line"
    done <<<"$push_out"
    return 0
  fi
  rc=$?
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    log "OPS_REMOTE_PUSH_ERROR(rc=$rc): $line"
  done <<<"$push_out"
  return 0
}

push_remote_summary_if_needed() {
  local push_out rc
  if push_out="$("${CODEX_SHARED_SCRIPTS_DIR}/ops_remote_summary_push.sh" 2>&1)"; then
    while IFS= read -r line; do
      [[ -z "$line" || "$line" == "OPS_REMOTE_SUMMARY_PUSH_SKIPPED=URL_NOT_CONFIGURED" || "$line" == "OPS_REMOTE_SUMMARY_PUSH_SKIPPED=DISABLED" || "$line" == "OPS_REMOTE_SUMMARY_PUSH_SKIPPED=THROTTLED" || "$line" == "OPS_REMOTE_SUMMARY_PUSH_SKIPPED=ENDPOINT_NOT_FOUND" || "$line" == "OPS_REMOTE_SUMMARY_PUSH_SKIPPED=ENDPOINT_NOT_FOUND_CACHE" ]] && continue
      log "$line"
    done <<<"$push_out"
    return 0
  fi
  rc=$?
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    log "OPS_REMOTE_SUMMARY_PUSH_ERROR(rc=$rc): $line"
  done <<<"$push_out"
  return 0
}

html_escape() {
  local value="${1:-}"
  jq -rn --arg v "$value" '$v|@html'
}

detail_value() {
  local detail="$1"
  local key="$2"
  local match
  match="$(
    printf '%s' "$detail" \
      | tr ';|' '\n\n' \
      | sed 's/^[[:space:]]*//' \
      | grep -m1 "^${key}=" || true
  )"
  if [[ -z "$match" ]]; then
    return 1
  fi
  printf '%s' "${match#*=}"
}

service_status_icon() {
  local status="$1"
  case "$status" in
    OK) echo "🟢" ;;
    SKIPPED) echo "⚪" ;;
    DNS_OFFLINE|UNREACHABLE) echo "🔴" ;;
    UNSTABLE) echo "🟡" ;;
    *) echo "⚪" ;;
  esac
}

has_only_github_degradation() {
  local detail="$1"
  local line value
  local has_github="0"
  local has_other="0"

  while IFS= read -r line; do
    line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [[ -z "$line" ]] && continue

    if [[ "$line" == AUTH_DEGRADED=1* ]]; then
      has_other="1"
      continue
    fi

    if [[ "$line" == DEGRADED=* ]]; then
      value="${line#DEGRADED=}"
      case "$value" in
        GITHUB_*|GITHUB_GRAPHQL_RATE_LIMIT|PENDING_OUTBOX:*)
          has_github="1"
          ;;
        *)
          has_other="1"
          ;;
      esac
    fi
  done < <(printf '%s' "$detail" | tr ';|' '\n')

  [[ "$has_github" == "1" && "$has_other" == "0" ]]
}

notify_github_runtime_if_needed() {
  local state="$1"
  local detail="$2"
  local output="$3"

  local mode
  mode="$(read_file_or_default "$GITHUB_RUNTIME_NOTIFY_MODE_FILE" "ONLINE")"
  if [[ "$mode" != "WAITING" && "$mode" != "ONLINE" ]]; then
    mode="ONLINE"
  fi

  local queue_count
  queue_count="$(runtime_queue_count)"
  local queue_count_num=0
  if [[ "$queue_count" =~ ^[0-9]+$ ]]; then
    queue_count_num="$queue_count"
  fi

  local applied_count
  applied_count="$(
    printf '%s\n' "$output" | awk '/^RUNTIME_PROJECT_STATUS_APPLIED=1/{c++} END {print c+0}'
  )"
  if ! [[ "$applied_count" =~ ^[0-9]+$ ]]; then
    applied_count=0
  fi

  local github_wait="0"
  local runtime_wait_marker="0"
  if printf '%s\n' "$output" | grep -q '^RUNTIME_PROJECT_STATUS_WAIT_GITHUB=1'; then
    runtime_wait_marker="1"
  fi

  if [[ "$runtime_wait_marker" == "1" ]]; then
    github_wait="1"
  elif (( queue_count_num > 0 )); then
    if [[ "$state" == "WAIT_GITHUB_OFFLINE" || "$state" == "WAIT_GITHUB_RATE_LIMIT" ]]; then
      github_wait="1"
    elif [[ "$detail" == *"DEGRADED=GITHUB_"* || "$detail" == *"DEGRADED=GITHUB_GRAPHQL_RATE_LIMIT"* ]]; then
      github_wait="1"
    fi
  fi

  local now_utc
  now_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  if (( applied_count > 0 )); then
    local targets stage_line msg msg_file notify_out rc
    targets="$(
      printf '%s\n' "$output" \
        | sed -n 's/^RUNTIME_PROJECT_STATUS_TARGET=//p' \
        | awk 'NF' \
        | awk '!seen[$0]++' \
        | paste -sd ',' -
    )"
    stage_line="$(printf '%s\n' "$output" | grep -m1 -E '^(WAIT_GITHUB_STAGE=|RUNTIME_PROJECT_STATUS_WAIT_ERROR=|WAIT_GITHUB_RATE_LIMIT_STAGE=)' || true)"
    msg="<b>✅ ${PROJECT_LABEL}: GitHub ответил, runtime-задачи применены</b>"$'\n'
    msg+="<b>📌 State:</b> <code>$(html_escape "$state")</code>"$'\n'
    msg+="<b>📦 Applied:</b> <code>${applied_count}</code>"
    [[ -n "$targets" ]] && msg+=" · <b>Targets:</b> <code>$(html_escape "$targets")</code>"
    msg+=$'\n'
    [[ -n "$stage_line" ]] && msg+="<b>🧭 Last wait:</b> <code>$(html_escape "$stage_line")</code>"$'\n'
    msg+="<b>🗂️ Queue left:</b> <code>${queue_count}</code>"$'\n'
    msg+="<b>🕒 Time:</b> <code>$(html_escape "$now_utc")</code>"

    msg_file="$(mktemp "${STATE_TMP_DIR}/daemon_runtime_notify.XXXXXX")"
    printf '%s' "$msg" > "$msg_file"
    if notify_out="$("${CODEX_SHARED_SCRIPTS_DIR}/telegram_local_notify.sh" "$msg_file" 2>&1)"; then
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        log "TG_NOTIFY_RUNTIME: $line"
      done <<<"$notify_out"
      log "TG_NOTIFY_RUNTIME_REASON=GITHUB_RUNTIME_RECOVERED"
    else
      rc=$?
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        log "TG_NOTIFY_RUNTIME_ERROR(rc=$rc): $line"
      done <<<"$notify_out"
      log "TG_NOTIFY_RUNTIME_REASON=GITHUB_RUNTIME_RECOVERED"
    fi
    rm -f "$msg_file"
    printf '%s\n' "ONLINE" > "$GITHUB_RUNTIME_NOTIFY_MODE_FILE"
    return 0
  fi

  if [[ "$github_wait" == "1" ]]; then
    if [[ "$mode" != "WAITING" ]]; then
      local wait_line msg msg_file notify_out rc title_line action_line
      wait_line="$(printf '%s\n' "$output" | grep -m1 -E '^(WAIT_GITHUB_STAGE=|RUNTIME_PROJECT_STATUS_WAIT_ERROR=|WAIT_GITHUB_RATE_LIMIT_STAGE=|WAIT_GITHUB_RATE_LIMIT_MSG=)' || true)"
      [[ -z "$wait_line" ]] && wait_line="$(printf '%s' "$detail" | tr '|' '\n' | sed 's/^[[:space:]]*//' | grep -m1 -E '^(DEGRADED=GITHUB_|GITHUB_STATUS=)' || true)"
      title_line="<b>⛔ ${PROJECT_LABEL}: GitHub недоступен, ждём восстановление</b>"
      action_line="<b>➡️ Action:</b> <code>авто-ретраи включены, выполняем при восстановлении GitHub</code>"
      if [[ "$state" == "WAIT_GITHUB_RATE_LIMIT" || "$wait_line" == *"RATE_LIMIT"* || "$detail" == *"GITHUB_GRAPHQL_RATE_LIMIT"* ]]; then
        title_line="<b>⏳ ${PROJECT_LABEL}: GitHub GraphQL rate limit, ждём окно</b>"
        action_line="<b>➡️ Action:</b> <code>авто-ретраи включены, продолжим после сброса лимита</code>"
      fi
      msg="${title_line}"$'\n'
      msg+="<b>📌 State:</b> <code>$(html_escape "$state")</code>"$'\n'
      [[ -n "$wait_line" ]] && msg+="<b>🧭 Reason:</b> <code>$(html_escape "$wait_line")</code>"$'\n'
      msg+="<b>🗂️ Runtime queue:</b> <code>${queue_count}</code>"$'\n'
      msg+="${action_line}"$'\n'
      msg+="<b>🕒 Time:</b> <code>$(html_escape "$now_utc")</code>"

      msg_file="$(mktemp "${STATE_TMP_DIR}/daemon_runtime_notify.XXXXXX")"
      printf '%s' "$msg" > "$msg_file"
      if notify_out="$("${CODEX_SHARED_SCRIPTS_DIR}/telegram_local_notify.sh" "$msg_file" 2>&1)"; then
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          log "TG_NOTIFY_RUNTIME: $line"
        done <<<"$notify_out"
        log "TG_NOTIFY_RUNTIME_REASON=GITHUB_RUNTIME_WAIT"
      else
        rc=$?
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          log "TG_NOTIFY_RUNTIME_ERROR(rc=$rc): $line"
        done <<<"$notify_out"
        log "TG_NOTIFY_RUNTIME_REASON=GITHUB_RUNTIME_WAIT"
      fi
      rm -f "$msg_file"
    fi
    printf '%s\n' "WAITING" > "$GITHUB_RUNTIME_NOTIFY_MODE_FILE"
    return 0
  fi

  printf '%s\n' "ONLINE" > "$GITHUB_RUNTIME_NOTIFY_MODE_FILE"
}

is_reaction_required() {
  local reason="$1"
  local state="$2"
  local detail="$3"

  if [[ "$reason" == "RECOVERED" || "$reason" == "DIRTY_WORKTREE_RESOLVED" ]]; then
    echo "0"
    return 0
  fi

  if [[ "$detail" == *"DEGRADED="* || "$detail" == *"AUTH_DEGRADED=1"* ]]; then
    echo "1"
    return 0
  fi

  case "$state" in
    WAIT_USER_REPLY|WAIT_REVIEW_FEEDBACK|WAIT_DIRTY_WORKTREE|WAIT_GITHUB_RATE_LIMIT|WAIT_GITHUB_OFFLINE|WAIT_BRANCH_SYNC|BLOCKED_*|ERROR_LOCAL_FLOW)
      echo "1"
      ;;
    *)
      echo "0"
      ;;
  esac
}

dirty_worktree_action_text() {
  local reason="$1"
  case "$reason" in
    WAIT_DIRTY_WORKTREE_ENTER)
      echo "daemon waits for decision по измененным tracked-файлам (COMMIT/STASH/REVERT/IGNORE)."
      ;;
    WAIT_DIRTY_WORKTREE_CHANGED)
      echo "daemon waits for updated decision: набор tracked-файлов изменился с прошлого сигнала."
      ;;
    WAIT_DIRTY_WORKTREE_REMINDER)
      echo "daemon все еще ждет решение по tracked-файлам (COMMIT/STASH/REVERT/IGNORE)."
      ;;
    DIRTY_WORKTREE_RESOLVED)
      echo "dirty worktree блокировка снята; daemon вернулся к обычному циклу."
      ;;
    *)
      echo "daemon обновил состояние dirty worktree."
      ;;
  esac
}

build_notify_message() {
  local reason="$1"
  local state="$2"
  local detail="$3"
  local now_utc
  now_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  local title
  if [[ "$reason" == WAIT_DIRTY_WORKTREE_* ]]; then
    title="<b>🚨 🧹 ${PROJECT_LABEL}: daemon paused (dirty worktree)</b>"
  elif [[ "$reason" == "DIRTY_WORKTREE_RESOLVED" ]]; then
    title="<b>💤 ✅ ${PROJECT_LABEL}: dirty worktree resolved</b>"
  else
    title="<b>⚠️ ${PROJECT_LABEL}: daemon degradation signal</b>"
  fi

  local gh_status tg_status gh_icon tg_icon
  gh_status="$(detail_value "$detail" "GITHUB_STATUS" || true)"
  tg_status="$(detail_value "$detail" "TELEGRAM_STATUS" || true)"
  [[ -z "$gh_status" ]] && gh_status="UNKNOWN"
  [[ -z "$tg_status" ]] && tg_status="UNKNOWN"
  gh_icon="$(service_status_icon "$gh_status")"
  tg_icon="$(service_status_icon "$tg_status")"

  local degraded_labels
  degraded_labels="$(
    printf '%s' "$detail" \
      | tr ';' '\n' \
      | sed 's/^[[:space:]]*//' \
      | grep '^DEGRADED=' \
      | sed 's/^DEGRADED=//' \
      | xargs || true
  )"

  local reaction_required check_badge
  reaction_required="$(is_reaction_required "$reason" "$state" "$detail")"
  if [[ "$reaction_required" == "1" ]]; then
    check_badge="🚨 НУЖНА РЕАКЦИЯ"
  else
    check_badge="💤 IDLE"
  fi

  local main_state_line
  main_state_line="<b>📌 State:</b> <code>$(html_escape "$state")</code>"
  if [[ -n "$degraded_labels" ]]; then
    main_state_line+=" · <b>📉 Degraded:</b> <code>$(html_escape "$degraded_labels")</code>"
  fi

  local aux_text aux_escaped msg
  aux_text=$'REASON='"${reason}"$'\n'
  aux_text+=$'STATE='"${state}"$'\n'
  aux_text+=$'DETAIL='"${detail}"$'\n'
  aux_text+=$'TIME_UTC='"${now_utc}"
  aux_escaped="$(html_escape "$aux_text")"

  if [[ "$reason" == WAIT_DIRTY_WORKTREE_* || "$reason" == "DIRTY_WORKTREE_RESOLVED" ]]; then
    local dirty_tracked_count dirty_tracked_files
    local dirty_blocked_ref dirty_blocked_issue dirty_blocked_title
    local dirty_gate_issue dirty_gate_item dirty_action
    local dirty_blocked_line dirty_gate_line
    dirty_tracked_count="$(detail_value "$detail" "WAIT_DIRTY_WORKTREE_TRACKED_COUNT" || true)"
    dirty_tracked_files="$(detail_value "$detail" "WAIT_DIRTY_WORKTREE_TRACKED_FILES" || true)"
    dirty_blocked_ref="$(detail_value "$detail" "WAIT_DIRTY_WORKTREE_BLOCKED_REF" || true)"
    dirty_blocked_issue="$(detail_value "$detail" "WAIT_DIRTY_WORKTREE_BLOCKED_ISSUE_NUMBER" || true)"
    dirty_blocked_title="$(detail_value "$detail" "WAIT_DIRTY_WORKTREE_BLOCKED_ISSUE_TITLE" || true)"
    dirty_gate_issue="$(detail_value "$detail" "WAIT_DIRTY_WORKTREE_GATE_ISSUE_NUMBER" || true)"
    dirty_gate_item="$(detail_value "$detail" "WAIT_DIRTY_WORKTREE_GATE_PROJECT_ITEM_ID" || true)"
    dirty_action="$(dirty_worktree_action_text "$reason")"

    dirty_blocked_line=""
    if [[ -n "$dirty_blocked_issue" ]]; then
      dirty_blocked_line="Issue #${dirty_blocked_issue}"
    elif [[ -n "$dirty_blocked_ref" ]]; then
      dirty_blocked_line="$dirty_blocked_ref"
    fi
    if [[ -n "$dirty_blocked_title" ]]; then
      if [[ -n "$dirty_blocked_line" ]]; then
        dirty_blocked_line="${dirty_blocked_line}: ${dirty_blocked_title}"
      else
        dirty_blocked_line="$dirty_blocked_title"
      fi
    fi

    dirty_gate_line=""
    if [[ -n "$dirty_gate_issue" ]]; then
      dirty_gate_line="Issue #${dirty_gate_issue}"
    fi
    if [[ -n "$dirty_gate_item" ]]; then
      if [[ -n "$dirty_gate_line" ]]; then
        dirty_gate_line="${dirty_gate_line}; item=${dirty_gate_item}"
      else
        dirty_gate_line="item=${dirty_gate_item}"
      fi
    fi

    msg="${title}"$'\n'
    msg+="<b>⚙️ Reason:</b> <code>$(html_escape "$reason")</code>"$'\n'
    msg+="<b>📌 State:</b> <code>$(html_escape "$state")</code>"$'\n'
    [[ -n "$dirty_blocked_line" ]] && msg+="<b>🧱 Blocked:</b> <code>$(html_escape "$dirty_blocked_line")</code>"$'\n'
    [[ -n "$dirty_tracked_count" ]] && msg+="<b>🧪 Tracked count:</b> <code>$(html_escape "$dirty_tracked_count")</code>"$'\n'
    [[ -n "$dirty_tracked_files" ]] && msg+="<b>📂 Tracked files:</b> <code>$(html_escape "$dirty_tracked_files")</code>"$'\n'
    [[ -n "$dirty_gate_line" ]] && msg+="<b>🧷 Dirty-gate:</b> <code>$(html_escape "$dirty_gate_line")</code>"$'\n'
    msg+="<b>➡️ Action:</b> $(html_escape "$dirty_action")"$'\n'
    msg+="<b>🌐 GitHub:</b> ${gh_icon} <code>$(html_escape "$gh_status")</code> · <b>Telegram:</b> ${tg_icon} <code>$(html_escape "$tg_status")</code>"$'\n'
    msg+="<b>🕒 Time:</b> <code>$(html_escape "$now_utc")</code>"
    msg+=$'\n'"<blockquote><code>${aux_escaped}</code></blockquote>"
    printf '%s' "$msg"
    return 0
  fi

  msg="${title}"$'\n'
  msg+="<b>🧭 CHECK NOW:</b> ${check_badge}"$'\n'
  msg+="${main_state_line}"$'\n'
  msg+="<b>🌐 GitHub:</b> ${gh_icon} <code>$(html_escape "$gh_status")</code> · <b>Telegram:</b> ${tg_icon} <code>$(html_escape "$tg_status")</code>"$'\n'
  msg+="<blockquote><code>${aux_escaped}</code></blockquote>"
  printf '%s' "$msg"
}

notify_if_needed() {
  local state="$1"
  local detail="$2"

  local mode="healthy"
  local dirty_blocking_todo="0"
  if [[ "$detail" == *"WAIT_DIRTY_WORKTREE_BLOCKING_TODO=1"* ]]; then
    dirty_blocking_todo="1"
  fi
  if [[ "$state" == "WAIT_DIRTY_WORKTREE" && "$dirty_blocking_todo" == "1" ]]; then
    mode="dirty_worktree"
  elif [[ "$detail" == *"DEGRADED="* || "$detail" == *"AUTH_DEGRADED=1"* ]]; then
    mode="degraded"
  fi

  # GitHub-specific деградацию отправляем отдельным "runtime" каналом
  # (WAIT/RECOVERED), чтобы избежать дублирующих общих alert-сообщений.
  if [[ "$mode" == "degraded" ]] && has_only_github_degradation "$detail"; then
    mode="healthy"
  fi

  local now_epoch
  now_epoch="$(date +%s)"
  local reminder_sec="${DAEMON_TG_REMINDER_SEC:-1800}"
  if ! [[ "$reminder_sec" =~ ^[0-9]+$ ]] || (( reminder_sec < 60 )); then
    reminder_sec=1800
  fi
  local github_dns_reminder_sec="${DAEMON_TG_GH_DNS_REMINDER_SEC:-300}"
  if ! [[ "$github_dns_reminder_sec" =~ ^[0-9]+$ ]] || (( github_dns_reminder_sec < 60 )); then
    github_dns_reminder_sec=300
  fi
  local dirty_reminder_sec="${DAEMON_TG_DIRTY_REMINDER_SEC:-600}"
  if ! [[ "$dirty_reminder_sec" =~ ^[0-9]+$ ]] || (( dirty_reminder_sec < 60 )); then
    dirty_reminder_sec=600
  fi

  local signature
  signature="$(printf '%s|%s' "$state" "$detail" | shasum -a 1 | awk '{print $1}')"

  local last_mode
  last_mode="$(read_file_or_default "$NOTIFY_MODE_FILE" "unknown")"
  local last_epoch
  last_epoch="$(read_file_or_default "$NOTIFY_EPOCH_FILE" "0")"
  local last_signature
  last_signature="$(read_file_or_default "$NOTIFY_SIGNATURE_FILE" "")"
  if ! [[ "$last_epoch" =~ ^[0-9]+$ ]]; then
    last_epoch=0
  fi

  local should_notify="0"
  local reason=""
  local github_dns_via_telegram="0"
  if [[ "$detail" == *"DEGRADED=GITHUB_DNS_OFFLINE"* && "$detail" == *"TELEGRAM_NOTIFY_ROUTE=AVAILABLE"* ]]; then
    github_dns_via_telegram="1"
  fi

  if [[ "$mode" == "dirty_worktree" ]]; then
    if [[ "$last_mode" != "dirty_worktree" ]]; then
      should_notify="1"
      reason="WAIT_DIRTY_WORKTREE_ENTER"
    elif [[ "$last_signature" != "$signature" ]]; then
      should_notify="1"
      reason="WAIT_DIRTY_WORKTREE_CHANGED"
    elif (( now_epoch - last_epoch >= dirty_reminder_sec )); then
      should_notify="1"
      reason="WAIT_DIRTY_WORKTREE_REMINDER"
    fi
  elif [[ "$mode" == "degraded" ]]; then
    if [[ "$github_dns_via_telegram" == "1" ]]; then
      if [[ "$last_mode" != "degraded" ]]; then
        should_notify="1"
        reason="GITHUB_DNS_TELEGRAM_OK_ENTER"
      elif [[ "$last_signature" != "$signature" ]]; then
        should_notify="1"
        reason="GITHUB_DNS_TELEGRAM_OK_CHANGED"
      elif (( now_epoch - last_epoch >= github_dns_reminder_sec )); then
        should_notify="1"
        reason="GITHUB_DNS_TELEGRAM_OK_REMINDER"
      fi
    else
      if [[ "$last_mode" != "degraded" ]]; then
        should_notify="1"
        reason="ENTER_DEGRADED"
      elif [[ "$last_signature" != "$signature" ]]; then
        should_notify="1"
        reason="DEGRADED_CHANGED"
      elif (( now_epoch - last_epoch >= reminder_sec )); then
        should_notify="1"
        reason="DEGRADED_REMINDER"
      fi
    fi
  else
    if [[ "$last_mode" == "degraded" ]]; then
      should_notify="1"
      reason="RECOVERED"
    elif [[ "$last_mode" == "dirty_worktree" ]]; then
      should_notify="1"
      reason="DIRTY_WORKTREE_RESOLVED"
    fi
  fi

  if [[ "$should_notify" == "1" ]]; then
    local msg_file notify_out rc
    msg_file="$(mktemp "${STATE_TMP_DIR}/daemon_notify.XXXXXX")"
    build_notify_message "$reason" "$state" "$detail" > "$msg_file"
    if notify_out="$("${CODEX_SHARED_SCRIPTS_DIR}/telegram_local_notify.sh" "$msg_file" 2>&1)"; then
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        log "TG_NOTIFY: $line"
      done <<<"$notify_out"
      log "TG_NOTIFY_REASON=$reason"
    else
      rc=$?
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        log "TG_NOTIFY_ERROR(rc=$rc): $line"
      done <<<"$notify_out"
      log "TG_NOTIFY_REASON=$reason"
    fi
    rm -f "$msg_file"
    printf '%s\n' "$now_epoch" > "$NOTIFY_EPOCH_FILE"
    printf '%s\n' "$signature" > "$NOTIFY_SIGNATURE_FILE"
    printf '%s\n' "$mode" > "$NOTIFY_MODE_FILE"
  fi
}

log "daemon_loop start interval=${interval}s rate_limit_backoff_base=${rate_limit_backoff_base_sec}s rate_limit_backoff_max=${rate_limit_backoff_max_sec}s"
if [[ "$stale_lock_recovered" == "1" ]]; then
  log "STALE_DAEMON_LOCK_RECOVERED=1 PREVIOUS_PID=${stale_lock_owner_pid}"
fi
set_state "BOOTING" "daemon_loop started"

while true; do
  log "heartbeat"
  if refresh_daemon_github_token; then
    :
  else
    rc=$?
    degradation="$(detect_flow_degradation)"
    detail="AUTH_UNAVAILABLE=1; AUTH_DEGRADED=1; DEGRADED=AUTH_SERVICE_UNAVAILABLE; AUTH_RC=${rc}; ${AUTH_LAST_DETAIL}; AUTH_FALLBACK_ENABLED=${AUTH_FALLBACK_ENABLED}; AUTH_FALLBACK_TOKEN_PRESENT=${AUTH_FALLBACK_TOKEN_PRESENT}; AUTH_FALLBACK_REASON=${AUTH_FALLBACK_REASON}"
    if [[ -n "$AUTH_FALLBACK_SOURCE" ]]; then
      detail="${detail}; AUTH_FALLBACK_SOURCE=${AUTH_FALLBACK_SOURCE}"
    fi
    if [[ -n "$degradation" ]]; then
      detail="${detail} | ${degradation}"
    fi
    set_state "WAIT_AUTH_SERVICE" "$detail"
    push_remote_status_if_needed
    push_remote_summary_if_needed
    notify_if_needed "WAIT_AUTH_SERVICE" "$detail"
    sleep "$interval"
    continue
  fi

  runtime_apply_out="$("${CODEX_SHARED_SCRIPTS_DIR}/project_status_runtime.sh" apply 5 2>&1 || true)"
  if [[ -n "$runtime_apply_out" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" || "$line" == "RUNTIME_PROJECT_STATUS_QUEUE_ABSENT=1" ]] && continue
      log "$line"
    done <<<"$runtime_apply_out"
  fi

  if output="$(DAEMON_LOOP_PUSH_REMOTE=1 "${CODEX_SHARED_SCRIPTS_DIR}/daemon_tick.sh" 2>&1)"; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      log "$line"
    done <<<"$output"
    state="$(classify_success_state "$output")"
    first_line="$(build_success_detail "$state" "$output" | tr '\n' ' ')"
    degradation="$(detect_flow_degradation)"
    detail="$first_line"
    if [[ -n "$AUTH_RUNTIME_DETAIL" ]]; then
      if [[ -n "$detail" ]]; then
        detail="${detail} | ${AUTH_RUNTIME_DETAIL}"
      else
        detail="$AUTH_RUNTIME_DETAIL"
      fi
    fi
    if [[ -n "$degradation" ]]; then
      detail="${detail} | ${degradation}"
    fi
    set_state "$state" "$detail"
    push_remote_status_if_needed
    push_remote_summary_if_needed
    combined_output="${runtime_apply_out}"$'\n'"${output}"
    notify_github_runtime_if_needed "$state" "$detail" "$combined_output"
    notify_if_needed "$state" "$detail"
  else
    rc=$?
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      log "ERROR(rc=$rc): $line"
    done <<<"$output"
    state="$(classify_error_state "$output")"
    first_line="$(printf '%s' "$output" | head -n1 | tr '\n' ' ')"
    degradation="$(detect_flow_degradation)"
    detail="rc=$rc; ${first_line}"
    if [[ -n "$AUTH_RUNTIME_DETAIL" ]]; then
      detail="${detail} | ${AUTH_RUNTIME_DETAIL}"
    fi
    if [[ -n "$degradation" ]]; then
      detail="${detail} | ${degradation}"
    fi
    set_state "$state" "$detail"
    push_remote_status_if_needed
    push_remote_summary_if_needed
    combined_output="${runtime_apply_out}"$'\n'"${output}"
    notify_github_runtime_if_needed "$state" "$detail" "$combined_output"
    notify_if_needed "$state" "$detail"
  fi

  compute_loop_sleep_sec "$state"
  if [[ "$state" == "WAIT_GITHUB_RATE_LIMIT" ]]; then
    log "RATE_LIMIT_BACKOFF_ACTIVE=1 STEP=${rate_limit_backoff_hits} SLEEP_SEC=${loop_sleep_sec} NEXT_SLEEP_SEC=${rate_limit_backoff_next_sec} BASE_SEC=${rate_limit_backoff_base_sec} MAX_SEC=${rate_limit_backoff_max_sec}"
  fi

  sleep "$loop_sleep_sec"
done
