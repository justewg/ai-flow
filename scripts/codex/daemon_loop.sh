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

detect_flow_degradation() {
  local parts=()
  local pending_outbox_count="0"
  if [[ -d "${CODEX_DIR}/outbox" ]]; then
    pending_outbox_count="$(
      find "${CODEX_DIR}/outbox" -type f -name '*.txt' -size +0c 2>/dev/null | wc -l | tr -d ' '
    )"
  fi
  if [[ "${pending_outbox_count}" != "0" ]]; then
    parts+=("DEGRADED=PENDING_OUTBOX:${pending_outbox_count}")
  fi

  local probe_out
  if probe_out="$(curl -sS -o /dev/null --max-time 5 https://api.github.com 2>&1)"; then
    :
  else
    if printf '%s' "$probe_out" | grep -Eiq 'could not resolve host: api\.github\.com|temporary failure in name resolution'; then
      parts+=("DEGRADED=GITHUB_DNS_OFFLINE")
    elif printf '%s' "$probe_out" | grep -Eiq 'connection timed out|operation timed out|tls handshake timeout|failed to connect'; then
      parts+=("DEGRADED=GITHUB_API_UNREACHABLE")
    else
      parts+=("DEGRADED=GITHUB_UNSTABLE")
    fi
  fi

  if (( ${#parts[@]} > 0 )); then
    local joined
    joined="$(IFS=';'; echo "${parts[*]}")"
    echo "$joined"
  else
    echo ""
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
    degradation="$(detect_flow_degradation)"
    detail="$first_line"
    if [[ -n "$degradation" ]]; then
      detail="${detail} | ${degradation}"
    fi
    set_state "$state" "$detail"
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
    if [[ -n "$degradation" ]]; then
      detail="${detail} | ${degradation}"
    fi
    set_state "$state" "$detail"
  fi
  sleep "$interval"
done
