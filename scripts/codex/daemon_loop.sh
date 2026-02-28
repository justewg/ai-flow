#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CODEX_DIR="${ROOT_DIR}/.tmp/codex"
LOCK_DIR="${CODEX_DIR}/daemon.lock"
LOG_FILE="${CODEX_DIR}/daemon.log"
STATE_FILE="${CODEX_DIR}/daemon_state.txt"
STATE_DETAIL_FILE="${CODEX_DIR}/daemon_state_detail.txt"
NOTIFY_MODE_FILE="${CODEX_DIR}/daemon_notify_mode.txt"
NOTIFY_EPOCH_FILE="${CODEX_DIR}/daemon_notify_last_epoch.txt"
NOTIFY_SIGNATURE_FILE="${CODEX_DIR}/daemon_notify_last_signature.txt"

interval="${1:-${DAEMON_INTERVAL_SEC:-45}}"
if ! [[ "$interval" =~ ^[0-9]+$ ]] || (( interval < 5 )); then
  echo "Invalid interval: '$interval' (expected integer >= 5 sec)"
  exit 1
fi

mkdir -p "$CODEX_DIR"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "Daemon already running (lock: $LOCK_DIR)"
  exit 1
fi

cleanup() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

log() {
  local ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf '%s %s\n' "$ts" "$*" >> "$LOG_FILE"
}

strip_quotes() {
  local value="$1"
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"
  printf '%s' "$value"
}

read_key_from_env_file() {
  local file_path="$1"
  local key="$2"
  [[ -f "$file_path" ]] || return 1
  local raw
  raw="$(grep -E "^${key}=" "$file_path" | tail -n1 | cut -d'=' -f2- || true)"
  [[ -n "$raw" ]] || return 1
  strip_quotes "$raw"
}

resolve_config_value() {
  local key="$1"
  local default_value="${2:-}"
  local env_value="${!key:-}"
  if [[ -n "$env_value" ]]; then
    printf '%s' "$env_value"
    return 0
  fi

  local env_candidates=()
  if [[ -n "${DAEMON_GH_ENV_FILE:-}" ]]; then
    env_candidates+=("${DAEMON_GH_ENV_FILE}")
  fi
  env_candidates+=("${ROOT_DIR}/.env")
  env_candidates+=("${ROOT_DIR}/.env.deploy")

  local env_file value
  for env_file in "${env_candidates[@]}"; do
    value="$(read_key_from_env_file "$env_file" "$key" || true)"
    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return 0
    fi
  done

  printf '%s' "$default_value"
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
  auth_log_file="$(mktemp "${CODEX_DIR}/daemon_auth.XXXXXX")"

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

  if token="$("${ROOT_DIR}/scripts/codex/gh_app_auth_token.sh" 2>"$auth_log_file")"; then
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
      local stage_line msg_line req_line dur_line
      local parts=()
      stage_line="$(printf '%s\n' "$output" | grep -m1 '^WAIT_GITHUB_RATE_LIMIT_STAGE=' || true)"
      msg_line="$(printf '%s\n' "$output" | grep -m1 '^WAIT_GITHUB_RATE_LIMIT_MSG=' || true)"
      req_line="$(printf '%s\n' "$output" | grep -m1 '^GQL_STATS_WINDOW_REQUESTS=' || true)"
      dur_line="$(printf '%s\n' "$output" | grep -m1 '^GQL_STATS_WINDOW_DURATION_SEC=' || true)"
      parts+=("DEGRADED=GITHUB_GRAPHQL_RATE_LIMIT")
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
  if [[ -d "${CODEX_DIR}/outbox" ]]; then
    pending_outbox_count="$(
      find "${CODEX_DIR}/outbox" -maxdepth 1 -type f -name '*.json' -size +0c 2>/dev/null | wc -l | tr -d ' '
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

build_notify_message() {
  local reason="$1"
  local state="$2"
  local detail="$3"
  local now_utc
  now_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  local msg
  if [[ "$reason" == WAIT_DIRTY_WORKTREE_* ]]; then
    msg=$'PLANKA: daemon paused (dirty worktree)\n'
    msg+="Reason: ${reason}"$'\n'
    msg+="State: ${state}"$'\n'
    msg+="Detail: ${detail}"$'\n'
    msg+=$'Action: daemon waits for decision по измененным tracked-файлам (commit/stash/revert).\n'
    msg+="Time: ${now_utc}"
  elif [[ "$reason" == "DIRTY_WORKTREE_RESOLVED" ]]; then
    msg=$'PLANKA: dirty worktree resolved\n'
    msg+="Reason: ${reason}"$'\n'
    msg+="State: ${state}"$'\n'
    msg+="Detail: ${detail}"$'\n'
    msg+="Time: ${now_utc}"
  else
    msg=$'PLANKA: daemon degradation signal\n'
    msg+="Reason: ${reason}"$'\n'
    msg+="State: ${state}"$'\n'
    msg+="Detail: ${detail}"$'\n'
    msg+="Time: ${now_utc}"
  fi
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
    msg_file="$(mktemp "${CODEX_DIR}/daemon_notify.XXXXXX")"
    build_notify_message "$reason" "$state" "$detail" > "$msg_file"
    if notify_out="$("${ROOT_DIR}/scripts/codex/telegram_local_notify.sh" "$msg_file" 2>&1)"; then
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

log "daemon_loop start interval=${interval}s"
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
    notify_if_needed "WAIT_AUTH_SERVICE" "$detail"
    sleep "$interval"
    continue
  fi

  if output="$("${ROOT_DIR}/scripts/codex/daemon_tick.sh" 2>&1)"; then
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
    notify_if_needed "$state" "$detail"
  fi
  sleep "$interval"
done
