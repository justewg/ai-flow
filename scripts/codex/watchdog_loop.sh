#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CODEX_DIR="${ROOT_DIR}/.tmp/codex"
LOCK_DIR="${CODEX_DIR}/watchdog.lock"
LOG_FILE="${CODEX_DIR}/watchdog.log"
STATE_FILE="${CODEX_DIR}/watchdog_state.txt"
DETAIL_FILE="${CODEX_DIR}/watchdog_state_detail.txt"

interval="${1:-${WATCHDOG_INTERVAL_SEC:-45}}"
if ! [[ "$interval" =~ ^[0-9]+$ ]] || (( interval < 10 )); then
  echo "Invalid interval: '$interval' (expected integer >= 10 sec)"
  exit 1
fi

mkdir -p "$CODEX_DIR"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "Watchdog already running (lock: $LOCK_DIR)"
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
  printf '%s\n' "$detail" > "$DETAIL_FILE"
  if [[ -n "$detail" ]]; then
    log "STATE=$state DETAIL=$detail"
  else
    log "STATE=$state"
  fi
}

WATCHDOG_AUTH_LAST_DETAIL=""

refresh_watchdog_github_token() {
  local auth_log_file token line rc
  WATCHDOG_AUTH_LAST_DETAIL=""
  auth_log_file="$(mktemp "${CODEX_DIR}/watchdog_auth.XXXXXX")"

  if token="$("${ROOT_DIR}/scripts/codex/gh_app_auth_token.sh" 2>"$auth_log_file")"; then
    token="$(printf '%s' "$token" | tr -d '\r\n')"
    if [[ -z "$token" ]]; then
      rm -f "$auth_log_file"
      WATCHDOG_AUTH_LAST_DETAIL="AUTH_ERROR_CODE=AUTH_SERVICE_BAD_PAYLOAD"
      return 1
    fi
    export GH_TOKEN="$token"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      log "WATCHDOG_AUTH: $line"
    done < "$auth_log_file"
    rm -f "$auth_log_file"
    return 0
  fi

  rc=$?
  unset GH_TOKEN || true
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ -z "$WATCHDOG_AUTH_LAST_DETAIL" ]] && WATCHDOG_AUTH_LAST_DETAIL="$line"
    log "WATCHDOG_AUTH_ERROR(rc=$rc): $line"
  done < "$auth_log_file"
  rm -f "$auth_log_file"
  if [[ -z "$WATCHDOG_AUTH_LAST_DETAIL" ]]; then
    WATCHDOG_AUTH_LAST_DETAIL="AUTH_ERROR_CODE=AUTH_SERVICE_UNREACHABLE"
  fi
  return "$rc"
}

log "watchdog_loop start interval=${interval}s"
set_state "BOOTING" "watchdog_loop started"

while true; do
  log "watchdog_heartbeat"
  if ! refresh_watchdog_github_token; then
    rc=$?
    detail="AUTH_UNAVAILABLE=1; AUTH_RC=${rc}; ${WATCHDOG_AUTH_LAST_DETAIL}"
    set_state "WAIT_AUTH_SERVICE" "$detail"
    sleep "$interval"
    continue
  fi

  if output="$("${ROOT_DIR}/scripts/codex/watchdog_tick.sh" 2>&1)"; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      log "$line"
    done <<<"$output"
  else
    rc=$?
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      log "WATCHDOG_ERROR(rc=$rc): $line"
    done <<<"$output"
  fi
  sleep "$interval"
done
