#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <message-file>" >&2
  exit 1
fi

message_file="$1"
if [[ ! -f "$message_file" ]]; then
  echo "TELEGRAM_SEND_ERROR=message_file_missing" >&2
  exit 1
fi

: "${TG_BOT_TOKEN:?TG_BOT_TOKEN is required}"
: "${TG_CHAT_ID:?TG_CHAT_ID is required}"

message_text="$(<"$message_file")"
if [[ -z "$message_text" ]]; then
  echo "TELEGRAM_SEND_ERROR=message_file_empty" >&2
  exit 1
fi

payload="$(
  jq -n \
    --arg chat_id "${TG_CHAT_ID}" \
    --arg text "${message_text}" \
    '{chat_id: $chat_id, text: $text, parse_mode: "HTML", disable_web_page_preview: true}'
)"

response_file="$(mktemp)"
trap 'rm -f "$response_file"' EXIT

http_status="$(
  curl -sS \
    -o "$response_file" \
    -w "%{http_code}" \
    --max-time 20 \
    -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
    -H "Content-Type: application/json" \
    --data "${payload}" || true
)"

description=""
if jq -e . >/dev/null 2>&1 <"$response_file"; then
  description="$(jq -r '.description // ""' <"$response_file")"
fi

if [[ "$http_status" == "200" ]]; then
  echo "TELEGRAM_SEND_OK=1"
  exit 0
fi

echo "TELEGRAM_SEND_OK=0" >&2
echo "TELEGRAM_SEND_HTTP_STATUS=${http_status:-curl_failed}" >&2
if [[ -n "$description" ]]; then
  echo "TELEGRAM_SEND_DESCRIPTION=${description}" >&2
fi

if [[ "${TELEGRAM_SOFT_FAIL:-0}" == "1" ]]; then
  echo "::warning::Telegram notify failed with HTTP ${http_status:-curl_failed}${description:+: ${description}}" >&2
  exit 0
fi

exit 1
