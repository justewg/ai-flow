#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

max_attempts="${GH_HEALTH_MAX_ATTEMPTS:-2}"
base_sleep_sec="${GH_HEALTH_BASE_SLEEP_SEC:-1}"

if ! [[ "$max_attempts" =~ ^[0-9]+$ ]] || (( max_attempts < 1 )); then
  max_attempts=2
fi
if ! [[ "$base_sleep_sec" =~ ^[0-9]+$ ]] || (( base_sleep_sec < 1 )); then
  base_sleep_sec=1
fi

probe_out=""
if probe_out="$(GH_RETRY_MAX_ATTEMPTS="$max_attempts" GH_RETRY_BASE_SLEEP_SEC="$base_sleep_sec" "${CODEX_SHARED_SCRIPTS_DIR}/gh_retry.sh" gh api rate_limit --jq '.rate.remaining' 2>&1)"; then
  remaining="$(printf '%s' "$probe_out" | tail -n1 | tr -d '[:space:]')"
  echo "GITHUB_HEALTHY=1"
  [[ -n "$remaining" ]] && echo "GITHUB_RATE_REMAINING=$remaining"
  exit 0
fi
rc=$?

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  echo "$line"
done <<<"$probe_out"

if [[ "$rc" -eq 75 ]]; then
  echo "GITHUB_API_UNSTABLE=1"
  exit 75
fi

echo "GITHUB_HEALTHY=0"
exit "$rc"
