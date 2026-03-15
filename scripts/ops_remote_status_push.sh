#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
CODEX_DIR="$(codex_export_state_dir)"
project_profile="$(codex_resolve_project_profile_name)"
project_repo="$(codex_resolve_project_repo_slug)"
project_label="$(codex_resolve_project_display_label)"
codex_load_flow_env
mkdir -p "${CODEX_DIR}"

is_truthy() {
  local raw="$1"
  local value
  value="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

enabled_raw="${OPS_REMOTE_STATUS_PUSH_ENABLED:-1}"
if ! is_truthy "$enabled_raw"; then
  echo "OPS_REMOTE_PUSH_SKIPPED=DISABLED"
  exit 0
fi

push_url="${OPS_REMOTE_STATUS_PUSH_URL:-}"
if [[ -z "$push_url" ]]; then
  echo "OPS_REMOTE_PUSH_SKIPPED=URL_NOT_CONFIGURED"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "OPS_REMOTE_PUSH_ERROR=jq command is required" >&2
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "OPS_REMOTE_PUSH_ERROR=curl command is required" >&2
  exit 1
fi

push_timeout_sec="${OPS_REMOTE_STATUS_PUSH_TIMEOUT_SEC:-6}"
if ! [[ "$push_timeout_sec" =~ ^[0-9]+$ ]] || (( push_timeout_sec < 2 )); then
  push_timeout_sec=6
fi

source_name="${OPS_REMOTE_STATUS_SOURCE:-}"
if [[ -z "$source_name" ]]; then
  if [[ -n "$project_profile" && "$project_profile" != "default" ]]; then
    source_name="$project_profile"
  elif [[ -n "$project_repo" ]]; then
    source_name="${project_repo##*/}"
  else
    source_name="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo local-runtime)"
  fi
fi

snapshot_json="$("${CODEX_SHARED_SCRIPTS_DIR}/status_snapshot.sh")"
if [[ -z "$snapshot_json" ]]; then
  echo "OPS_REMOTE_PUSH_ERROR=empty snapshot output" >&2
  exit 1
fi

pushed_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
payload_json="$(
  printf '%s' "$snapshot_json" \
    | jq -c \
      --arg source "$source_name" \
      --arg pushed_at "$pushed_at" \
      --arg profile "$project_profile" \
      --arg repo "$project_repo" \
      --arg project_label_value "$project_label" \
      '{"source":$source,"pushed_at":$pushed_at,"profile":$profile,"repo":$repo,"label":$project_label_value,"snapshot":.}'
)"

secret="${OPS_REMOTE_STATUS_PUSH_SECRET:-}"
curl_args=(
  -sS
  --max-time "${push_timeout_sec}"
  -H "Content-Type: application/json"
  --data "$payload_json"
  -o "${CODEX_DIR}/ops_remote_push_response.json"
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
    -o "${CODEX_DIR}/ops_remote_push_response.json"
    -w "%{http_code}"
    "${push_url}"
  )
fi

http_code="$(curl "${curl_args[@]}")"
response_body="$(cat "${CODEX_DIR}/ops_remote_push_response.json" 2>/dev/null || true)"

if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
  echo "OPS_REMOTE_PUSH_OK=1"
  echo "OPS_REMOTE_PUSH_URL=${push_url}"
  echo "OPS_REMOTE_PUSH_SOURCE=${source_name}"
  echo "OPS_REMOTE_PUSH_HTTP_STATUS=${http_code}"
  exit 0
fi

echo "OPS_REMOTE_PUSH_OK=0"
echo "OPS_REMOTE_PUSH_URL=${push_url}"
echo "OPS_REMOTE_PUSH_HTTP_STATUS=${http_code}"
if [[ -n "$response_body" ]]; then
  compact_response="$(printf '%s' "$response_body" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
  echo "OPS_REMOTE_PUSH_RESPONSE=${compact_response}"
fi
exit 1
