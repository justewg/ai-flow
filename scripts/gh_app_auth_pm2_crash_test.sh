#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PM2_APP_NAME="${GH_APP_PM2_APP_NAME:-planka-gh-app-auth}"
RESTART_TIMEOUT_SEC="${GH_APP_PM2_RESTART_TIMEOUT_SEC:-20}"

extract_kv() {
  local payload="$1"
  local key="$2"
  printf '%s\n' "$payload" | awk -F= -v expected="$key" '$1 == expected { print substr($0, index($0, "=") + 1) }' | tail -n1
}

if ! [[ "${RESTART_TIMEOUT_SEC}" =~ ^[0-9]+$ ]] || (( RESTART_TIMEOUT_SEC < 5 )); then
  echo "GH_APP_PM2_RESTART_TIMEOUT_SEC must be integer >= 5" >&2
  exit 1
fi

before_status="$("${CODEX_SHARED_SCRIPTS_DIR}/gh_app_auth_pm2_status.sh" --require-online)"
before_pid="$(extract_kv "${before_status}" "PM2_PID")"
before_restarts="$(extract_kv "${before_status}" "PM2_RESTARTS")"

if ! [[ "${before_pid}" =~ ^[0-9]+$ ]] || (( before_pid <= 0 )); then
  echo "Failed to get a valid PM2 PID before crash test" >&2
  exit 1
fi

if ! [[ "${before_restarts}" =~ ^[0-9]+$ ]]; then
  echo "Failed to get PM2 restart counter before crash test" >&2
  exit 1
fi

kill -9 "${before_pid}"

deadline=$((SECONDS + RESTART_TIMEOUT_SEC))
while (( SECONDS < deadline )); do
  sleep 1
  if after_status="$("${CODEX_SHARED_SCRIPTS_DIR}/gh_app_auth_pm2_status.sh" 2>/dev/null)"; then
    after_state="$(extract_kv "${after_status}" "PM2_STATUS")"
    after_pid="$(extract_kv "${after_status}" "PM2_PID")"
    after_restarts="$(extract_kv "${after_status}" "PM2_RESTARTS")"

    if [[ "${after_state}" == "online" ]] \
      && [[ "${after_pid}" =~ ^[0-9]+$ ]] && (( after_pid > 0 )) \
      && [[ "${after_restarts}" =~ ^[0-9]+$ ]] \
      && (( after_pid != before_pid )) \
      && (( after_restarts > before_restarts )); then
      echo "PM2_CRASH_TEST_OK app=${PM2_APP_NAME} old_pid=${before_pid} new_pid=${after_pid} restarts=${after_restarts}"
      "${CODEX_SHARED_SCRIPTS_DIR}/gh_app_auth_health.sh" >/dev/null
      echo "AUTH_HEALTH_OK"
      exit 0
    fi
  fi
done

echo "PM2_CRASH_TEST_FAILED app=${PM2_APP_NAME} timeout_sec=${RESTART_TIMEOUT_SEC}" >&2
"${CODEX_SHARED_SCRIPTS_DIR}/gh_app_auth_pm2_status.sh" || true
exit 1
