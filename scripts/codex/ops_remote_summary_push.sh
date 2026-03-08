#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=./env/resolve_config.sh
source "${ROOT_DIR}/scripts/codex/env/resolve_config.sh"
CODEX_DIR="$(codex_export_state_dir)"
mkdir -p "${CODEX_DIR}"

load_env_file() {
  local file_path="$1"
  if [[ -f "$file_path" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$file_path"
    set +a
  fi
}

is_truthy() {
  local raw="$1"
  local value
  value="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

load_env_file "${ROOT_DIR}/.env"
load_env_file "${ROOT_DIR}/.env.deploy"

enabled_raw="${OPS_REMOTE_SUMMARY_PUSH_ENABLED:-1}"
if ! is_truthy "$enabled_raw"; then
  echo "OPS_REMOTE_SUMMARY_PUSH_SKIPPED=DISABLED"
  exit 0
fi

push_url="${OPS_REMOTE_SUMMARY_PUSH_URL:-}"
if [[ -z "$push_url" ]]; then
  status_url="${OPS_REMOTE_STATUS_PUSH_URL:-}"
  if [[ -n "$status_url" ]]; then
    push_url="${status_url%/ops/ingest/status}/ops/ingest/log-summary"
  fi
fi
if [[ -z "$push_url" ]]; then
  echo "OPS_REMOTE_SUMMARY_PUSH_SKIPPED=URL_NOT_CONFIGURED"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "OPS_REMOTE_SUMMARY_PUSH_ERROR=jq command is required" >&2
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "OPS_REMOTE_SUMMARY_PUSH_ERROR=curl command is required" >&2
  exit 1
fi

push_timeout_sec="${OPS_REMOTE_SUMMARY_PUSH_TIMEOUT_SEC:-${OPS_REMOTE_STATUS_PUSH_TIMEOUT_SEC:-8}}"
if ! [[ "$push_timeout_sec" =~ ^[0-9]+$ ]] || (( push_timeout_sec < 2 )); then
  push_timeout_sec=8
fi

min_interval_sec="${OPS_REMOTE_SUMMARY_PUSH_MIN_INTERVAL_SEC:-300}"
if ! [[ "$min_interval_sec" =~ ^[0-9]+$ ]] || (( min_interval_sec < 30 )); then
  min_interval_sec=300
fi

endpoint_missing_backoff_sec="${OPS_REMOTE_SUMMARY_PUSH_ENDPOINT_MISSING_BACKOFF_SEC:-3600}"
if ! [[ "$endpoint_missing_backoff_sec" =~ ^[0-9]+$ ]] || (( endpoint_missing_backoff_sec < 60 )); then
  endpoint_missing_backoff_sec=3600
fi

last_push_epoch_file="${CODEX_DIR}/ops_remote_summary_last_push_epoch.txt"
endpoint_missing_epoch_file="${CODEX_DIR}/ops_remote_summary_endpoint_missing_epoch.txt"
now_epoch="$(date +%s)"
last_push_epoch="0"
if [[ -f "$last_push_epoch_file" ]]; then
  last_raw="$(cat "$last_push_epoch_file" 2>/dev/null || true)"
  if [[ "$last_raw" =~ ^[0-9]+$ ]]; then
    last_push_epoch="$last_raw"
  fi
fi
if (( last_push_epoch > 0 && now_epoch - last_push_epoch < min_interval_sec )); then
  echo "OPS_REMOTE_SUMMARY_PUSH_SKIPPED=THROTTLED"
  echo "OPS_REMOTE_SUMMARY_PUSH_NEXT_SEC=$(( min_interval_sec - (now_epoch - last_push_epoch) ))"
  exit 0
fi

if [[ -f "$endpoint_missing_epoch_file" ]]; then
  endpoint_missing_raw="$(cat "$endpoint_missing_epoch_file" 2>/dev/null || true)"
  if [[ "$endpoint_missing_raw" =~ ^[0-9]+$ ]] && (( now_epoch - endpoint_missing_raw < endpoint_missing_backoff_sec )); then
    echo "OPS_REMOTE_SUMMARY_PUSH_SKIPPED=ENDPOINT_NOT_FOUND_CACHE"
    echo "OPS_REMOTE_SUMMARY_PUSH_NEXT_SEC=$(( endpoint_missing_backoff_sec - (now_epoch - endpoint_missing_raw) ))"
    exit 0
  fi
fi

hours_csv="${OPS_REMOTE_SUMMARY_PUSH_HOURS:-6}"
hours_list=()
while IFS=',' read -r -a tokens; do
  for token in "${tokens[@]}"; do
    value="$(printf '%s' "$token" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [[ -z "$value" ]] && continue
    if [[ "$value" =~ ^[0-9]+$ ]] && (( value >= 1 && value <= 168 )); then
      hours_list+=("$value")
    fi
  done
done <<< "$hours_csv"
if (( ${#hours_list[@]} == 0 )); then
  hours_list=(6)
fi

unique_hours="$(printf '%s\n' "${hours_list[@]}" | sort -n | uniq | tr '\n' ',' | sed 's/,$//')"
hours_list=()
while IFS=',' read -r -a tokens; do
  for token in "${tokens[@]}"; do
    [[ -z "$token" ]] && continue
    hours_list+=("$token")
  done
done <<< "$unique_hours"

source_name="${OPS_REMOTE_SUMMARY_PUSH_SOURCE:-${OPS_REMOTE_STATUS_SOURCE:-}}"
if [[ -z "$source_name" ]]; then
  source_name="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo local-runtime)"
fi

summaries_json='{}'
for hours in "${hours_list[@]}"; do
  summary_text="$("${ROOT_DIR}/scripts/codex/log_summary.sh" --hours "$hours" 2>&1 || true)"
  if [[ -z "$summary_text" ]]; then
    summary_text="no data"
  fi
  summaries_json="$(
    jq -cn --argjson obj "$summaries_json" --arg k "$hours" --arg v "$summary_text" '$obj + {($k):$v}'
  )"
done

pushed_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
payload_json="$(
  jq -cn \
    --arg source "$source_name" \
    --arg pushed_at "$pushed_at" \
    --arg generated_at "$pushed_at" \
    --argjson summaries "$summaries_json" \
    '{source:$source,pushed_at:$pushed_at,generated_at:$generated_at,summaries:$summaries}'
)"

secret="${OPS_REMOTE_SUMMARY_PUSH_SECRET:-${OPS_REMOTE_STATUS_PUSH_SECRET:-}}"
curl_args=(
  -sS
  --max-time "${push_timeout_sec}"
  -H "Content-Type: application/json"
  --data "$payload_json"
  -o "${CODEX_DIR}/ops_remote_summary_push_response.json"
  -w "%{http_code}"
  "${push_url}"
)
if [[ -n "$secret" ]]; then
  curl_args=(
    -sS
    --max-time "${push_timeout_sec}"
    -H "Content-Type: application/json"
    -H "X-Ops-Status-Secret: ${secret}"
    --data "$payload_json"
    -o "${CODEX_DIR}/ops_remote_summary_push_response.json"
    -w "%{http_code}"
    "${push_url}"
  )
fi

http_code="$(curl "${curl_args[@]}")"
response_body="$(cat "${CODEX_DIR}/ops_remote_summary_push_response.json" 2>/dev/null || true)"

if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
  printf '%s\n' "$now_epoch" > "$last_push_epoch_file"
  rm -f "$endpoint_missing_epoch_file"
  echo "OPS_REMOTE_SUMMARY_PUSH_OK=1"
  echo "OPS_REMOTE_SUMMARY_PUSH_URL=${push_url}"
  echo "OPS_REMOTE_SUMMARY_PUSH_SOURCE=${source_name}"
  echo "OPS_REMOTE_SUMMARY_PUSH_WINDOWS=${unique_hours}"
  echo "OPS_REMOTE_SUMMARY_PUSH_HTTP_STATUS=${http_code}"
  exit 0
fi

if [[ "$http_code" == "404" ]] && printf '%s' "$response_body" | grep -Eiq '"error"[[:space:]]*:[[:space:]]*"NOT_FOUND"|endpoint not found'; then
  printf '%s\n' "$now_epoch" > "$endpoint_missing_epoch_file"
  echo "OPS_REMOTE_SUMMARY_PUSH_SKIPPED=ENDPOINT_NOT_FOUND"
  echo "OPS_REMOTE_SUMMARY_PUSH_URL=${push_url}"
  exit 0
fi

echo "OPS_REMOTE_SUMMARY_PUSH_OK=0"
echo "OPS_REMOTE_SUMMARY_PUSH_URL=${push_url}"
echo "OPS_REMOTE_SUMMARY_PUSH_HTTP_STATUS=${http_code}"
if [[ -n "$response_body" ]]; then
  compact_response="$(printf '%s' "$response_body" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
  echo "OPS_REMOTE_SUMMARY_PUSH_RESPONSE=${compact_response}"
fi
exit 1
