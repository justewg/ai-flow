#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=./env/resolve_config.sh
source "${ROOT_DIR}/.flow/scripts/env/resolve_config.sh"

sanitize_line() {
  local value="$1"
  printf '%s' "$value" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

if ! command -v jq >/dev/null 2>&1; then
  echo "AUTH_ERROR_CODE=AUTH_PREREQUISITE_MISSING" >&2
  echo "AUTH_ERROR_MESSAGE=jq command is required" >&2
  exit 1
fi

bind="$(codex_resolve_config_value "GH_APP_BIND" "127.0.0.1")"
port="$(codex_resolve_config_value "GH_APP_PORT" "8787")"
secret="$(codex_resolve_config_value "GH_APP_INTERNAL_SECRET" "")"
timeout_sec="$(codex_resolve_config_value "DAEMON_GH_AUTH_TIMEOUT_SEC" "8")"
custom_token_url="$(codex_resolve_config_value "DAEMON_GH_AUTH_TOKEN_URL" "")"

if ! [[ "$timeout_sec" =~ ^[0-9]+$ ]] || (( timeout_sec < 2 || timeout_sec > 120 )); then
  timeout_sec=8
fi

if [[ -z "$secret" ]]; then
  echo "AUTH_ERROR_CODE=AUTH_CONFIG_MISSING_SECRET" >&2
  echo "AUTH_ERROR_MESSAGE=GH_APP_INTERNAL_SECRET is not set" >&2
  exit 2
fi

if [[ -n "$custom_token_url" ]]; then
  token_url="$custom_token_url"
else
  token_url="http://${bind}:${port}/token"
fi

body_file="$(mktemp)"
err_file="$(mktemp)"
cleanup() {
  rm -f "$body_file" "$err_file"
}
trap cleanup EXIT

http_status=""
if ! http_status="$(
  curl -sS \
    --max-time "$timeout_sec" \
    -H "X-Internal-Secret: ${secret}" \
    -o "$body_file" \
    -w '%{http_code}' \
    "$token_url" 2>"$err_file"
)"; then
  curl_error="$(sanitize_line "$(cat "$err_file" 2>/dev/null || true)")"
  [[ -z "$curl_error" ]] && curl_error="failed to connect to auth service"
  echo "AUTH_ERROR_CODE=AUTH_SERVICE_UNREACHABLE" >&2
  echo "AUTH_ERROR_MESSAGE=${curl_error}" >&2
  echo "AUTH_ENDPOINT=${token_url}" >&2
  exit 3
fi

if [[ "$http_status" != "200" ]]; then
  error_code="$(jq -r '.error // empty' "$body_file" 2>/dev/null || true)"
  error_message="$(jq -r '.message // empty' "$body_file" 2>/dev/null || true)"
  [[ -z "$error_code" ]] && error_code="AUTH_SERVICE_BAD_STATUS"
  if [[ -z "$error_message" ]]; then
    error_message="auth service responded with HTTP ${http_status}"
  fi
  error_message="$(sanitize_line "$error_message")"
  echo "AUTH_ERROR_CODE=${error_code}" >&2
  echo "AUTH_ERROR_MESSAGE=${error_message}" >&2
  echo "AUTH_HTTP_STATUS=${http_status}" >&2
  echo "AUTH_ENDPOINT=${token_url}" >&2
  exit 4
fi

token="$(jq -r '.token // empty' "$body_file" 2>/dev/null || true)"
expires_at="$(jq -r '.expires_at // empty' "$body_file" 2>/dev/null || true)"
source="$(jq -r '.source // "unknown"' "$body_file" 2>/dev/null || true)"

if [[ -z "$token" || -z "$expires_at" ]]; then
  echo "AUTH_ERROR_CODE=AUTH_SERVICE_BAD_PAYLOAD" >&2
  echo "AUTH_ERROR_MESSAGE=token response missing token/expires_at" >&2
  echo "AUTH_HTTP_STATUS=200" >&2
  echo "AUTH_ENDPOINT=${token_url}" >&2
  exit 5
fi

echo "AUTH_HTTP_STATUS=200" >&2
echo "AUTH_SOURCE=${source}" >&2
echo "AUTH_EXPIRES_AT=${expires_at}" >&2
echo "AUTH_ENDPOINT=${token_url}" >&2
printf '%s\n' "$token"
