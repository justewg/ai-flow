#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
codex_load_flow_env
CODEX_DIR="$(codex_export_state_dir)"
RUNTIME_LOG_DIR="$(codex_resolve_flow_runtime_log_dir)"
STATE_TMP_DIR="$(codex_resolve_state_tmp_dir "$CODEX_DIR")"
WATCHDOG_STATE_DIR="$(codex_resolve_state_watchdog_dir "$CODEX_DIR")"
LOCK_DIR="${WATCHDOG_STATE_DIR}/lock"
LOCK_OWNER_FILE="${LOCK_DIR}/owner.pid"
LOG_FILE="${RUNTIME_LOG_DIR}/watchdog.log"
STATE_FILE="${CODEX_DIR}/watchdog_state.txt"
DETAIL_FILE="${CODEX_DIR}/watchdog_state_detail.txt"

interval="${1:-${WATCHDOG_INTERVAL_SEC:-45}}"
if ! [[ "$interval" =~ ^[0-9]+$ ]] || (( interval < 10 )); then
  echo "Invalid interval: '$interval' (expected integer >= 10 sec)"
  exit 1
fi

mkdir -p "$CODEX_DIR" "$RUNTIME_LOG_DIR" "$STATE_TMP_DIR" "$WATCHDOG_STATE_DIR"

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
    echo "Watchdog already running (lock: $LOCK_DIR pid=$owner_pid)"
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

  echo "Watchdog already running (lock: $LOCK_DIR)"
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

runtime_ownership_detail() {
  local runtime_role runtime_instance_id authoritative_runtime_id
  runtime_role="$(codex_resolve_flow_automation_runtime_role)"
  runtime_instance_id="$(codex_resolve_flow_runtime_instance_id)"
  authoritative_runtime_id="$(codex_resolve_flow_authoritative_runtime_id)"

  printf 'FLOW_AUTOMATION_RUNTIME_ROLE=%s; RUNTIME_INSTANCE_ID=%s' \
    "$runtime_role" "$runtime_instance_id"
  if [[ -n "$authoritative_runtime_id" ]]; then
    printf '; FLOW_AUTHORITATIVE_RUNTIME_ID=%s' "$authoritative_runtime_id"
  fi
}

enforce_runtime_ownership() {
  local ownership_state detail
  ownership_state="$(codex_resolve_flow_runtime_ownership_state)"
  detail="$(runtime_ownership_detail)"

  case "$ownership_state" in
    INTERACTIVE_ONLY)
      set_state "INTERACTIVE_ONLY" "INTERACTIVE_ONLY=1; ${detail}"
      return 1
      ;;
    OWNER_MISMATCH)
      set_state "WAIT_RUNTIME_OWNERSHIP" "WAIT_RUNTIME_OWNERSHIP=1; RUNTIME_OWNERSHIP_REASON=OWNER_MISMATCH; ${detail}"
      return 1
      ;;
    *)
      return 0
      ;;
  esac
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
  auth_log_file="$(mktemp "${STATE_TMP_DIR}/watchdog_auth.XXXXXX")"

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

  if token="$("${CODEX_SHARED_SCRIPTS_DIR}/gh_app_auth_token.sh" 2>"$auth_log_file")"; then
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
if [[ "$stale_lock_recovered" == "1" ]]; then
  log "STALE_WATCHDOG_LOCK_RECOVERED=1 PREVIOUS_PID=${stale_lock_owner_pid}"
fi
set_state "BOOTING" "watchdog_loop started"

while true; do
  if ! enforce_runtime_ownership; then
    sleep "$interval"
    continue
  fi
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
    "${CODEX_SHARED_SCRIPTS_DIR}/watchdog_tick.sh" 2>&1
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
