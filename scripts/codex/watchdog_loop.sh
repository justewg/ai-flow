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

configure_daemon_github_token() {
  if [[ -n "${GH_TOKEN:-}" ]]; then
    log "WATCHDOG_GITHUB_AUTH_MODE=ENV_GH_TOKEN"
    return 0
  fi

  local token=""
  local source="none"
  local env_candidates=()

  if [[ -n "${DAEMON_GH_TOKEN:-}" ]]; then
    token="${DAEMON_GH_TOKEN}"
    source="env:DAEMON_GH_TOKEN"
  elif [[ -n "${CODEX_GH_TOKEN:-}" ]]; then
    token="${CODEX_GH_TOKEN}"
    source="env:CODEX_GH_TOKEN"
  else
    if [[ -n "${DAEMON_GH_ENV_FILE:-}" ]]; then
      env_candidates+=("${DAEMON_GH_ENV_FILE}")
    fi
    env_candidates+=("${ROOT_DIR}/.env")
    env_candidates+=("${ROOT_DIR}/.env.deploy")

    local env_file
    for env_file in "${env_candidates[@]}"; do
      token="$(read_key_from_env_file "$env_file" "DAEMON_GH_TOKEN" || true)"
      if [[ -n "$token" ]]; then
        source="file:${env_file}:DAEMON_GH_TOKEN"
        break
      fi
      token="$(read_key_from_env_file "$env_file" "CODEX_GH_TOKEN" || true)"
      if [[ -n "$token" ]]; then
        source="file:${env_file}:CODEX_GH_TOKEN"
        break
      fi
    done
  fi

  if [[ -n "$token" ]]; then
    export GH_TOKEN="$token"
    log "WATCHDOG_GITHUB_AUTH_MODE=DAEMON_TOKEN (${source})"
  else
    log "WATCHDOG_GITHUB_AUTH_MODE=DEFAULT_GH_AUTH"
  fi
}

configure_daemon_github_token

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
