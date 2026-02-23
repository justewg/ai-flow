#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CODEX_DIR="${ROOT_DIR}/.tmp/codex"
LOCK_DIR="${CODEX_DIR}/daemon.lock"
LOG_FILE="${CODEX_DIR}/daemon.log"
STATE_FILE="${CODEX_DIR}/daemon_state.txt"
STATE_DETAIL_FILE="${CODEX_DIR}/daemon_state_detail.txt"

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
  if printf '%s' "$output" | grep -q '^CLAIMED_TASK_ID='; then
    echo "ACTIVE_TASK_CLAIMED"
  elif printf '%s' "$output" | grep -q '^WAIT_USER_REPLY=1'; then
    echo "WAIT_USER_REPLY"
  elif printf '%s' "$output" | grep -q '^WAIT_ACTIVE_TASK_ID='; then
    echo "WAIT_ACTIVE_TASK"
  elif printf '%s' "$output" | grep -q '^WAIT_OPEN_PR_COUNT='; then
    echo "WAIT_OPEN_PR"
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
  elif printf '%s' "$output" | grep -q '^USER_REPLY_RECEIVED=1'; then
    echo "USER_REPLY_RECEIVED"
  else
    echo "OK"
  fi
}

classify_error_state() {
  local output="$1"
  if printf '%s' "$output" | grep -Eiq 'error connecting to api\.github\.com|could not resolve host: api\.github\.com|connection timed out|tls handshake timeout|temporary failure in name resolution'; then
    echo "WAIT_GITHUB_OFFLINE"
  else
    echo "ERROR_LOCAL_FLOW"
  fi
}

log "daemon_loop start interval=${interval}s"
set_state "BOOTING" "daemon_loop started"

while true; do
  log "heartbeat"
  if output="$("${ROOT_DIR}/scripts/codex/daemon_tick.sh" 2>&1)"; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      log "$line"
    done <<<"$output"
    state="$(classify_success_state "$output")"
    first_line="$(printf '%s' "$output" | head -n1 | tr '\n' ' ')"
    set_state "$state" "$first_line"
  else
    rc=$?
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      log "ERROR(rc=$rc): $line"
    done <<<"$output"
    state="$(classify_error_state "$output")"
    first_line="$(printf '%s' "$output" | head -n1 | tr '\n' ' ')"
    set_state "$state" "rc=$rc; ${first_line}"
  fi
  sleep "$interval"
done
