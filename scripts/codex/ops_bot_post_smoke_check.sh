#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CODEX_DIR="${ROOT_DIR}/.tmp/codex"
SERVICE_FILE="${ROOT_DIR}/scripts/codex/ops_bot_service.js"

manual_file="${CODEX_DIR}/issue_285_manual_enriched.md"
report_file="${CODEX_DIR}/issue_316_post_smoke_report.md"
write_report="1"

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

usage() {
  cat <<'EOF'
Usage:
  scripts/codex/ops_bot_post_smoke_check.sh [--manual-file <path>] [--report-file <path>] [--no-report]

Checks:
  1) MANUAL_ROLLOUT_DONE + status fields in manual input
  2) local prereq commands (node/pm2/curl/jq)
  3) local health endpoint
  4) Telegram webhook info (best effort)
  5) public status-page endpoints (best effort)
  6) static check of bot commands/status-page handlers in source
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manual-file)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --manual-file" >&2
        exit 1
      fi
      manual_file="$2"
      shift 2
      ;;
    --report-file)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --report-file" >&2
        exit 1
      fi
      report_file="$2"
      shift 2
      ;;
    --no-report)
      write_report="0"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

mkdir -p "${CODEX_DIR}"

checks=()
incidents=()

add_check() {
  local key="$1"
  local status="$2"
  local details="$3"
  checks+=("${key}|${status}|${details}")
}

add_incident() {
  local id="$1"
  local message="$2"
  incidents+=("${id}: ${message}")
}

check_manual_rollout_comment() {
  local missing=()

  if [[ ! -f "$manual_file" ]]; then
    add_check "manual_comment" "fail" "Файл не найден: ${manual_file}"
    add_incident "manual-comment-missing" "Не найден входной файл с подтверждением manual rollout."
    return
  fi

  if ! grep -Eq '^[[:space:]]*MANUAL_ROLLOUT_DONE[[:space:]]*$' "$manual_file"; then
    missing+=("MANUAL_ROLLOUT_DONE")
  fi

  local field line value
  for field in OPS_HEALTH WEBHOOK_INFO BOT_COMMANDS OPS_STATUS_JSON; do
    line="$(grep -E "^[[:space:]]*${field}[[:space:]]*:" "$manual_file" | tail -n1 || true)"
    if [[ -z "$line" ]]; then
      missing+=("${field}")
      continue
    fi
    value="${line#*:}"
    value="$(trim "$value")"
    if [[ -z "$value" || "$value" == "..." ]]; then
      missing+=("${field}")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    add_check "manual_comment" "fail" "Отсутствуют поля: $(IFS=,; echo "${missing[*]}")"
    add_incident "manual-template-incomplete" "Нет полного подтверждения rollout по шаблону (${missing[*]})."
    return
  fi

  add_check "manual_comment" "ok" "Подтверждение rollout найдено."
}

check_local_prerequisites() {
  local missing=()
  local cmd
  for cmd in node pm2 curl jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    add_check "local_prerequisites" "fail" "Отсутствуют команды: $(IFS=,; echo "${missing[*]}")"
    add_incident "local-prerequisites-missing" "В окружении нет обязательных зависимостей (${missing[*]})."
    return
  fi

  add_check "local_prerequisites" "ok" "node/pm2/curl/jq доступны."
}

check_local_health() {
  local bind="${OPS_BOT_BIND:-127.0.0.1}"
  local port="${OPS_BOT_PORT:-8790}"
  local url="http://${bind}:${port}/health"
  local output=""
  local rc=0

  set +e
  output="$(curl -fsS --max-time 5 "$url" 2>&1)"
  rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    add_check "local_health" "ok" "GET ${url} доступен."
    return
  fi

  add_check "local_health" "fail" "GET ${url} недоступен (${output})."
  add_incident "local-health-unavailable" "Локальный health endpoint не отвечает на ${url}."
}

check_webhook_info() {
  local output=""
  local rc=0

  set +e
  output="$("${ROOT_DIR}/scripts/codex/ops_bot_webhook_register.sh" info 2>&1)"
  rc=$?
  set -e

  if [[ $rc -eq 0 ]] && printf '%s\n' "$output" | grep -q '^WEBHOOK_INFO_OK=1$'; then
    add_check "webhook_info" "ok" "Telegram getWebhookInfo выполнен успешно."
    return
  fi

  local first_line
  first_line="$(printf '%s\n' "$output" | sed -n '1p')"
  first_line="$(trim "$first_line")"
  [[ -z "$first_line" ]] && first_line="неизвестная ошибка"
  add_check "webhook_info" "fail" "Не удалось получить webhook info (${first_line})."
  add_incident "webhook-info-unavailable" "Проверка webhook не прошла (${first_line})."
}

check_public_status_endpoints() {
  local base="${OPS_BOT_PUBLIC_BASE_URL:-}"
  base="${base%/}"
  if [[ -z "$base" ]]; then
    add_check "public_status_page" "fail" "OPS_BOT_PUBLIC_BASE_URL не задан."
    add_incident "public-base-url-missing" "Не задан OPS_BOT_PUBLIC_BASE_URL для проверки status-page."
    return
  fi

  local output_json=""
  local output_html=""
  local rc_json=0
  local rc_html=0

  set +e
  output_json="$(curl -fsS --max-time 8 "${base}/ops/status.json" 2>&1)"
  rc_json=$?
  output_html="$(curl -fsS --max-time 8 "${base}/ops/status" 2>&1)"
  rc_html=$?
  set -e

  if [[ $rc_json -eq 0 && $rc_html -eq 0 ]]; then
    add_check "public_status_page" "ok" "Публичные endpoints /ops/status и /ops/status.json доступны."
    return
  fi

  local reason=""
  if [[ $rc_json -ne 0 ]]; then
    reason="status.json: $(trim "$(printf '%s\n' "$output_json" | sed -n '1p')")"
  fi
  if [[ $rc_html -ne 0 ]]; then
    if [[ -n "$reason" ]]; then
      reason="${reason}; "
    fi
    reason="${reason}status: $(trim "$(printf '%s\n' "$output_html" | sed -n '1p')")"
  fi
  add_check "public_status_page" "fail" "Публичные endpoints недоступны (${reason})."
  add_incident "public-status-page-unavailable" "Не удалось проверить ${base}/ops/status(.json)."
}

check_static_bot_handlers() {
  if [[ ! -f "$SERVICE_FILE" ]]; then
    add_check "commands_static" "fail" "Не найден файл ${SERVICE_FILE}."
    add_incident "service-file-missing" "Отсутствует файл ops_bot_service.js для статической проверки."
    return
  fi

  local missing=()
  local pattern
  for pattern in \
    'name === "/help"' \
    'name === "/status"' \
    'name === "/summary"' \
    'name === "/status_page"' \
    'url.pathname === "/ops/status"' \
    'url.pathname === "/ops/status.json"' \
    'url.pathname === "/health"'
  do
    if ! rg -q "$pattern" "$SERVICE_FILE"; then
      missing+=("$pattern")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    add_check "commands_static" "fail" "Не найдены expected handlers: $(IFS=,; echo "${missing[*]}")"
    add_incident "commands-handler-mismatch" "Статическая проверка обработчиков команд/endpoint не прошла."
    return
  fi

  add_check "commands_static" "ok" "Статические обработчики команд и status-page присутствуют."
}

check_manual_rollout_comment
check_local_prerequisites
check_local_health
check_webhook_info
check_public_status_endpoints
check_static_bot_handlers

ok_count=0
fail_count=0
warn_count=0

for row in "${checks[@]}"; do
  status="$(printf '%s' "$row" | cut -d'|' -f2)"
  case "$status" in
    ok) ok_count=$((ok_count + 1)) ;;
    warn) warn_count=$((warn_count + 1)) ;;
    *) fail_count=$((fail_count + 1)) ;;
  esac
done

result="rollout_accepted"
if (( ${#incidents[@]} > 0 )); then
  result="incidents"
fi

if [[ "$write_report" == "1" ]]; then
  {
    echo "ISSUE-316 post-smoke report"
    echo "Generated at: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo
    echo "Result: ${result}"
    echo "Checks: ok=${ok_count}, warn=${warn_count}, fail=${fail_count}"
    echo
    echo "Checks detail:"
    for row in "${checks[@]}"; do
      key="$(printf '%s' "$row" | cut -d'|' -f1)"
      status="$(printf '%s' "$row" | cut -d'|' -f2)"
      details="$(printf '%s' "$row" | cut -d'|' -f3-)"
      echo "- ${key}: ${status} (${details})"
    done
    echo
    echo "Incidents:"
    if (( ${#incidents[@]} == 0 )); then
      echo "- none"
    else
      for item in "${incidents[@]}"; do
        echo "- ${item}"
      done
    fi
  } > "$report_file"
fi

echo "POST_SMOKE_RESULT=${result}"
echo "POST_SMOKE_CHECK_OK=${ok_count}"
echo "POST_SMOKE_CHECK_WARN=${warn_count}"
echo "POST_SMOKE_CHECK_FAIL=${fail_count}"
echo "POST_SMOKE_INCIDENT_COUNT=${#incidents[@]}"
echo "POST_SMOKE_REPORT_FILE=${report_file}"

for row in "${checks[@]}"; do
  key="$(printf '%s' "$row" | cut -d'|' -f1)"
  status="$(printf '%s' "$row" | cut -d'|' -f2)"
  details="$(printf '%s' "$row" | cut -d'|' -f3-)"
  echo "CHECK_${key}=${status}|${details}"
done

if (( ${#incidents[@]} > 0 )); then
  for item in "${incidents[@]}"; do
    echo "INCIDENT=${item}"
  done
  exit 2
fi

exit 0
