#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

load_env_file() {
  local file_path="$1"
  if [[ -f "$file_path" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$file_path"
    set +a
  fi
}

ensure_cmd() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "Required command not found: $name" >&2
    exit 1
  fi
}

normalize_base_url() {
  local value="$1"
  value="${value%/}"
  printf '%s' "$value"
}

normalize_path() {
  local value="$1"
  if [[ -z "$value" ]]; then
    value="/telegram/webhook"
  fi
  if [[ "$value" != /* ]]; then
    value="/$value"
  fi
  printf '%s' "${value%/}"
}

usage() {
  cat <<'EOF'
Usage:
  scripts/codex/ops_bot_webhook_register.sh register
  scripts/codex/ops_bot_webhook_register.sh refresh
  scripts/codex/ops_bot_webhook_register.sh delete
  scripts/codex/ops_bot_webhook_register.sh info

Environment (from .env/.env.deploy or process env):
  OPS_BOT_PUBLIC_BASE_URL (required for register; example: https://planka.ewg40.ru)
  OPS_BOT_WEBHOOK_PATH (optional, default: /telegram/webhook)
  OPS_BOT_WEBHOOK_SECRET (optional; appended to webhook path)
  OPS_BOT_TG_SECRET_TOKEN (optional; passed as secret_token for Telegram webhook)
  OPS_BOT_WEBHOOK_IP_ADDRESS (optional; passed as ip_address to Telegram setWebhook)
  OPS_BOT_WEBHOOK_DROP_PENDING_UPDATES (optional; default 1 for refresh/delete)
  OPS_BOT_TG_BOT_TOKEN (or DAEMON_TG_BOT_TOKEN or TG_BOT_TOKEN)
EOF
}

load_env_file "${ROOT_DIR}/.env"
load_env_file "${ROOT_DIR}/.env.deploy"

ensure_cmd curl
ensure_cmd jq

command_name="${1:-register}"
if [[ "$command_name" != "register" && "$command_name" != "refresh" && "$command_name" != "delete" && "$command_name" != "info" ]]; then
  usage
  exit 1
fi

tg_bot_token="${OPS_BOT_TG_BOT_TOKEN:-${DAEMON_TG_BOT_TOKEN:-${TG_BOT_TOKEN:-}}}"
if [[ -z "$tg_bot_token" ]]; then
  echo "Missing bot token. Set OPS_BOT_TG_BOT_TOKEN (fallback: DAEMON_TG_BOT_TOKEN/TG_BOT_TOKEN)." >&2
  exit 1
fi

webhook_path_base="$(normalize_path "${OPS_BOT_WEBHOOK_PATH:-/telegram/webhook}")"
webhook_secret="${OPS_BOT_WEBHOOK_SECRET:-}"
webhook_path="$webhook_path_base"
if [[ -n "$webhook_secret" ]]; then
  webhook_path="${webhook_path}/${webhook_secret}"
fi

run_delete_webhook() {
  local drop_pending="${OPS_BOT_WEBHOOK_DROP_PENDING_UPDATES:-1}"
  local delete_response
  delete_response="$(
    curl -fsS --max-time 20 -X POST \
      "https://api.telegram.org/bot${tg_bot_token}/deleteWebhook" \
      --data-urlencode "drop_pending_updates=${drop_pending}"
  )"
  if [[ "$(printf '%s' "$delete_response" | jq -r '.ok // false')" != "true" ]]; then
    echo "WEBHOOK_DELETE_OK=0"
    printf '%s\n' "$delete_response" | jq .
    exit 1
  fi
  echo "WEBHOOK_DELETE_OK=1"
  echo "WEBHOOK_DROP_PENDING_UPDATES=${drop_pending}"
  printf '%s\n' "$delete_response" | jq .
}

run_set_webhook() {
  public_base_url="$(normalize_base_url "${OPS_BOT_PUBLIC_BASE_URL:-}")"
  if [[ -z "$public_base_url" ]]; then
    echo "OPS_BOT_PUBLIC_BASE_URL is required for register (example: https://planka.ewg40.ru)." >&2
    exit 1
  fi
  if [[ "$public_base_url" != http://* && "$public_base_url" != https://* ]]; then
    echo "OPS_BOT_PUBLIC_BASE_URL must start with http:// or https://." >&2
    exit 1
  fi

  webhook_url="${public_base_url}${webhook_path}"
  telegram_secret_token="${OPS_BOT_TG_SECRET_TOKEN:-}"
  webhook_ip_address="${OPS_BOT_WEBHOOK_IP_ADDRESS:-}"

  curl_args=(
    -fsS
    --max-time 20
    -X POST
    "https://api.telegram.org/bot${tg_bot_token}/setWebhook"
    --data-urlencode "url=${webhook_url}"
  )
  if [[ -n "$telegram_secret_token" ]]; then
    curl_args+=(--data-urlencode "secret_token=${telegram_secret_token}")
  fi
  if [[ -n "$webhook_ip_address" ]]; then
    curl_args+=(--data-urlencode "ip_address=${webhook_ip_address}")
  fi

  set_response="$(curl "${curl_args[@]}")"
  if [[ "$(printf '%s' "$set_response" | jq -r '.ok // false')" != "true" ]]; then
    echo "WEBHOOK_SET_OK=0"
    printf '%s\n' "$set_response" | jq .
    exit 1
  fi

  echo "WEBHOOK_SET_OK=1"
  echo "WEBHOOK_URL=${webhook_url}"
  if [[ -n "$telegram_secret_token" ]]; then
    echo "WEBHOOK_SECRET_TOKEN_CONFIGURED=1"
  else
    echo "WEBHOOK_SECRET_TOKEN_CONFIGURED=0"
  fi
  if [[ -n "$webhook_ip_address" ]]; then
    echo "WEBHOOK_IP_ADDRESS=${webhook_ip_address}"
  fi
  printf '%s\n' "$set_response" | jq .
}

if [[ "$command_name" == "delete" ]]; then
  run_delete_webhook
fi

if [[ "$command_name" == "refresh" ]]; then
  run_delete_webhook
  run_set_webhook
fi

if [[ "$command_name" == "register" ]]; then
  run_set_webhook
fi

info_response="$(curl -fsS --max-time 20 -X POST "https://api.telegram.org/bot${tg_bot_token}/getWebhookInfo")"
if [[ "$(printf '%s' "$info_response" | jq -r '.ok // false')" != "true" ]]; then
  echo "WEBHOOK_INFO_OK=0"
  printf '%s\n' "$info_response" | jq .
  exit 1
fi

echo "WEBHOOK_INFO_OK=1"
printf '%s\n' "$info_response" | jq .
