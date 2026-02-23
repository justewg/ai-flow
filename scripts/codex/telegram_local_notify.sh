#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <message-file>"
  exit 1
fi

message_file="$1"
if [[ ! -f "$message_file" ]]; then
  echo "Message file not found: $message_file"
  exit 1
fi

message_text="$(<"$message_file")"
if [[ -z "$message_text" ]]; then
  echo "Message file is empty: $message_file"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

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

bot_token="${DAEMON_TG_BOT_TOKEN:-${TG_BOT_TOKEN:-}}"
chat_id="${DAEMON_TG_CHAT_ID:-${TG_CHAT_ID:-}}"

env_candidates=()
if [[ -n "${DAEMON_TG_ENV_FILE:-}" ]]; then
  env_candidates+=("${DAEMON_TG_ENV_FILE}")
fi
env_candidates+=("${ROOT_DIR}/.env")
env_candidates+=("${ROOT_DIR}/.env.deploy")

for env_file in "${env_candidates[@]}"; do
  if [[ -z "$bot_token" ]]; then
    bot_token="$(read_key_from_env_file "$env_file" "DAEMON_TG_BOT_TOKEN" || true)"
  fi
  if [[ -z "$bot_token" ]]; then
    bot_token="$(read_key_from_env_file "$env_file" "TG_BOT_TOKEN" || true)"
  fi
  if [[ -z "$chat_id" ]]; then
    chat_id="$(read_key_from_env_file "$env_file" "DAEMON_TG_CHAT_ID" || true)"
  fi
  if [[ -z "$chat_id" ]]; then
    chat_id="$(read_key_from_env_file "$env_file" "TG_CHAT_ID" || true)"
  fi
done

if [[ -z "$bot_token" || -z "$chat_id" ]]; then
  echo "SKIP_TG_NOTIFY_MISSING_CREDENTIALS=1"
  exit 2
fi

payload="$(
  jq -n \
    --arg chat_id "$chat_id" \
    --arg text "$message_text" \
    '{chat_id: $chat_id, text: $text, disable_web_page_preview: true}'
)"

curl -fsS --max-time 12 \
  -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
  -H "Content-Type: application/json" \
  --data "$payload" >/dev/null

echo "TG_NOTIFY_SENT=1"
