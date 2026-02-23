#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CODEX_DIR="${ROOT_DIR}/.tmp/codex"
LOCK_DIR="${CODEX_DIR}/watchdog.lock"
LOG_FILE="${CODEX_DIR}/watchdog.log"

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

log "watchdog_loop start interval=${interval}s"

while true; do
  log "watchdog_heartbeat"
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
