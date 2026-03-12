#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <command> [args...]"
  exit 1
fi

max_attempts="${GH_RETRY_MAX_ATTEMPTS:-5}"
base_sleep_sec="${GH_RETRY_BASE_SLEEP_SEC:-2}"

if ! [[ "$max_attempts" =~ ^[0-9]+$ ]] || (( max_attempts < 1 )); then
  max_attempts=5
fi
if ! [[ "$base_sleep_sec" =~ ^[0-9]+$ ]] || (( base_sleep_sec < 1 )); then
  base_sleep_sec=2
fi

is_unstable_error() {
  local text="$1"
  printf '%s' "$text" | grep -Eiq \
    'error connecting to api\.github\.com|could not resolve host: api\.github\.com|could not resolve hostname github\.com|temporary failure in name resolution|connection timed out|operation timed out|tls handshake timeout|failed to connect|unknown owner type'
}

attempt=1
while (( attempt <= max_attempts )); do
  cmd_out=""
  if cmd_out="$("$@" 2>&1)"; then
    printf '%s' "$cmd_out"
    exit 0
  fi
  rc=$?

  if ! is_unstable_error "$cmd_out"; then
    printf '%s\n' "$cmd_out" >&2
    exit "$rc"
  fi

  if (( attempt == max_attempts )); then
    printf '%s\n' "$cmd_out" >&2
    echo "GITHUB_API_UNSTABLE=1" >&2
    exit 75
  fi

  sleep_sec=$(( base_sleep_sec * attempt ))
  echo "GH_RETRY_ATTEMPT_FAILED=$attempt" >&2
  echo "GH_RETRY_SLEEP_SEC=$sleep_sec" >&2
  sleep "$sleep_sec"
  ((attempt++))
done

echo "GITHUB_API_UNSTABLE=1" >&2
exit 75
