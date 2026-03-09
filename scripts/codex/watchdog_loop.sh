#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=./env/resolve_config.sh
source "${ROOT_DIR}/scripts/codex/env/resolve_config.sh"
CODEX_DIR="$(codex_export_state_dir)"
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
WATCHDOG_AUTH_FALLBACK_ENABLED="0"
WATCHDOG_AUTH_FALLBACK_TOKEN_PRESENT="0"
WATCHDOG_AUTH_FALLBACK_REASON="DISABLED"
WATCHDOG_AUTH_FALLBACK_SOURCE=""
WATCHDOG_AUTH_DEGRADED="0"

refresh_watchdog_github_token() {
  local auth_log_file token line rc fallback_enabled_raw fallback_token
  WATCHDOG_AUTH_LAST_DETAIL=""
  WATCHDOG_AUTH_FALLBACK_ENABLED="0"
  WATCHDOG_AUTH_FALLBACK_TOKEN_PRESENT="0"
  WATCHDOG_AUTH_FALLBACK_REASON="DISABLED"
  WATCHDOG_AUTH_FALLBACK_SOURCE=""
  WATCHDOG_AUTH_DEGRADED="0"
  auth_log_file="$(mktemp "${CODEX_DIR}/watchdog_auth.XXXXXX")"

  fallback_enabled_raw="$(resolve_config_value "DAEMON_GH_TOKEN_FALLBACK_ENABLED" "")"
  if [[ -z "$fallback_enabled_raw" ]]; then
    fallback_enabled_raw="$(resolve_config_value "CODEX_GH_TOKEN_FALLBACK_ENABLED" "0")"
  fi
  if is_truthy "$fallback_enabled_raw"; then
    WATCHDOG_AUTH_FALLBACK_ENABLED="1"
    WATCHDOG_AUTH_FALLBACK_REASON="TOKEN_MISSING"
  fi

  fallback_token="$(resolve_config_value "DAEMON_GH_TOKEN" "")"
  if [[ -n "$fallback_token" ]]; then
    WATCHDOG_AUTH_FALLBACK_SOURCE="DAEMON_GH_TOKEN"
  else
    fallback_token="$(resolve_config_value "CODEX_GH_TOKEN" "")"
    if [[ -n "$fallback_token" ]]; then
      WATCHDOG_AUTH_FALLBACK_SOURCE="CODEX_GH_TOKEN"
    fi
  fi
  fallback_token="$(printf '%s' "$fallback_token" | tr -d '\r\n')"
  if [[ -n "$fallback_token" ]]; then
    WATCHDOG_AUTH_FALLBACK_TOKEN_PRESENT="1"
  fi

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
    WATCHDOG_AUTH_DEGRADED="0"
    return 0
  else
    rc=$?
  fi
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

  if [[ "$WATCHDOG_AUTH_FALLBACK_ENABLED" == "1" && "$WATCHDOG_AUTH_FALLBACK_TOKEN_PRESENT" == "1" ]]; then
    export GH_TOKEN="$fallback_token"
    WATCHDOG_AUTH_FALLBACK_REASON="ACTIVE"
    WATCHDOG_AUTH_DEGRADED="1"
    log "WATCHDOG_AUTH_FALLBACK_ACTIVE source=${WATCHDOG_AUTH_FALLBACK_SOURCE}; auth_rc=${rc}; auth_detail=${WATCHDOG_AUTH_LAST_DETAIL}"
    return 0
  fi

  if [[ "$WATCHDOG_AUTH_FALLBACK_ENABLED" == "1" ]]; then
    WATCHDOG_AUTH_FALLBACK_REASON="TOKEN_MISSING"
  fi
  WATCHDOG_AUTH_DEGRADED="1"
  return "$rc"
}

log "watchdog_loop start interval=${interval}s"
set_state "BOOTING" "watchdog_loop started"

while true; do
  log "watchdog_heartbeat"
  if refresh_watchdog_github_token; then
    :
  else
    rc=$?
    detail="AUTH_UNAVAILABLE=1; AUTH_DEGRADED=1; DEGRADED=AUTH_SERVICE_UNAVAILABLE; AUTH_RC=${rc}; ${WATCHDOG_AUTH_LAST_DETAIL}; AUTH_FALLBACK_ENABLED=${WATCHDOG_AUTH_FALLBACK_ENABLED}; AUTH_FALLBACK_TOKEN_PRESENT=${WATCHDOG_AUTH_FALLBACK_TOKEN_PRESENT}; AUTH_FALLBACK_REASON=${WATCHDOG_AUTH_FALLBACK_REASON}"
    if [[ -n "$WATCHDOG_AUTH_FALLBACK_SOURCE" ]]; then
      detail="${detail}; AUTH_FALLBACK_SOURCE=${WATCHDOG_AUTH_FALLBACK_SOURCE}"
    fi
    set_state "WAIT_AUTH_SERVICE" "$detail"
    log "WATCHDOG_AUTH_DEGRADED_CONTINUE=1"
  fi

  if output="$(
    WATCHDOG_AUTH_DEGRADED="${WATCHDOG_AUTH_DEGRADED}" \
    WATCHDOG_AUTH_LAST_DETAIL="${WATCHDOG_AUTH_LAST_DETAIL}" \
    WATCHDOG_AUTH_FALLBACK_REASON="${WATCHDOG_AUTH_FALLBACK_REASON}" \
    "${ROOT_DIR}/scripts/codex/watchdog_tick.sh" 2>&1
  )"; then
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
