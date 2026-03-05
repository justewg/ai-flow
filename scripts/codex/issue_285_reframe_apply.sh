#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CODEX_DIR="${ROOT_DIR}/.tmp/codex"
mkdir -p "${CODEX_DIR}"

REPO="${GITHUB_REPO:-justewg/planka}"
PROJECT_OWNER="${GITHUB_PROJECT_OWNER:-justewg}"
PROJECT_NUMBER="${GITHUB_PROJECT_NUMBER:-2}"
MANUAL_ISSUE_NUMBER="${1:-285}"
ASSIGNEE="${GITHUB_DEFAULT_ASSIGNEE:-justewg}"

run_gh_retry_capture() {
  local out=""
  local rc=0
  if out="$("${ROOT_DIR}/scripts/codex/gh_retry.sh" "$@" 2>&1)"; then
    printf '%s' "$out"
    return 0
  fi
  rc=$?
  printf '%s\n' "$out" >&2
  return "$rc"
}

find_issue_by_code() {
  local code="$1"
  local issues_json issue_number

  issues_json="$(run_gh_retry_capture gh api "repos/${REPO}/issues?state=all&per_page=100")"
  issue_number="$(
    printf '%s' "$issues_json" |
      jq -r --arg code "$code" '
        .[]
        | select((.pull_request // null) == null)
        | select((.title // "") | test("^\\[" + $code + "\\]"))
        | .number
      ' |
      head -n1
  )"
  printf '%s' "$issue_number"
}

ensure_project_backlog() {
  local issue_number="$1"
  local issue_url="https://github.com/${REPO}/issues/${issue_number}"
  local out rc

  if out="$(run_gh_retry_capture gh project item-add "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --url "$issue_url" 2>&1)"; then
    :
  else
    rc=$?
    if [[ "$rc" -eq 75 ]] || printf '%s' "$out" | grep -Eiq 'rate limit|api\.github\.com|could not resolve|timeout|connection reset|failed to connect'; then
      echo "PROJECT_ITEM_ADD_DEFERRED=1 ISSUE=${issue_number}" >&2
      return 0
    fi
    if ! printf '%s' "$out" | grep -Eiq 'already exists|already in project|item already'; then
      printf '%s\n' "$out" >&2
    fi
  fi

  if out="$("${ROOT_DIR}/scripts/codex/project_set_status.sh" "ISSUE-${issue_number}" "Backlog" "Backlog" 2>&1)"; then
    :
  else
    rc=$?
    if [[ "$rc" -eq 75 ]] || printf '%s' "$out" | grep -Eiq 'rate limit|api\.github\.com|could not resolve|timeout|connection reset|failed to connect'; then
      "${ROOT_DIR}/scripts/codex/project_status_runtime.sh" enqueue "ISSUE-${issue_number}" "Backlog" "Backlog" "issue-285-reframe:${issue_number}" >/dev/null 2>&1 || true
      echo "PROJECT_STATUS_DEFERRED=1 ISSUE=${issue_number}" >&2
      return 0
    fi
    if ! printf '%s' "$out" | grep -Eiq 'Task not found in project'; then
      printf '%s\n' "$out" >&2
    fi
  fi
}

ensure_issue() {
  local code="$1"
  local title="$2"
  local body_file="$3"
  local labels_csv="${4:-}"
  local issue_number=""
  local out rc

  issue_number="$(find_issue_by_code "$code")"

  if [[ -n "$issue_number" ]]; then
    if ! out="$(run_gh_retry_capture gh issue edit "$issue_number" --repo "$REPO" --title "$title" --body-file "$body_file" --add-assignee "$ASSIGNEE" 2>&1)"; then
      rc=$?
      printf '%s\n' "$out" >&2
      return "$rc"
    fi
  else
    local create_cmd=(gh issue create --repo "$REPO" --title "$title" --body-file "$body_file" --assignee "$ASSIGNEE")
    IFS=',' read -r -a labels_arr <<< "$labels_csv"
    for label in "${labels_arr[@]:-}"; do
      label="$(printf '%s' "$label" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
      [[ -z "$label" ]] && continue
      create_cmd+=(--label "$label")
    done

    if ! out="$(run_gh_retry_capture "${create_cmd[@]}" 2>&1)"; then
      rc=$?
      printf '%s\n' "$out" >&2
      return "$rc"
    fi

    if [[ "$out" =~ /issues/([0-9]+)$ ]]; then
      issue_number="${BASH_REMATCH[1]}"
    else
      issue_number="$(find_issue_by_code "$code")"
    fi
  fi

  if [[ -n "$labels_csv" ]]; then
    IFS=',' read -r -a labels_arr <<< "$labels_csv"
    for label in "${labels_arr[@]:-}"; do
      label="$(printf '%s' "$label" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
      [[ -z "$label" ]] && continue
      run_gh_retry_capture gh issue edit "$issue_number" --repo "$REPO" --add-label "$label" >/dev/null 2>&1 || true
    done
  fi

  printf '%s' "$issue_number"
}

tmp_manual_body="$(mktemp "${CODEX_DIR}/issue285.manual.XXXXXX.md")"
tmp_auto_body="$(mktemp "${CODEX_DIR}/issue285.auto.XXXXXX.md")"
tmp_post_body="$(mktemp "${CODEX_DIR}/issue285.post.XXXXXX.md")"
tmp_reframed_285="$(mktemp "${CODEX_DIR}/issue285.reframed.XXXXXX.md")"

trap 'rm -f "$tmp_manual_body" "$tmp_auto_body" "$tmp_post_body" "$tmp_reframed_285"' EXIT

cat > "$tmp_manual_body" <<'EOF'
## Цель
Провести ручной rollout внешнего доступа к ops-сервису (`/ops/status`, `/ops/status.json`) и Telegram webhook на домене `https://planka.ewg40.ru`.

Важно: это **manual-only** задача владельца окружения. Автоматика не должна брать ее в работу.

## Что нужно сделать вручную
1. Подготовить env на хосте (в `.env`/`.env.deploy`):
   - `OPS_BOT_BIND=127.0.0.1`
   - `OPS_BOT_PORT=8790`
   - `OPS_BOT_WEBHOOK_PATH=/telegram/webhook`
   - `OPS_BOT_WEBHOOK_SECRET=<long-random-secret-in-path>`
   - `OPS_BOT_TG_SECRET_TOKEN=<long-random-header-secret>`
   - `OPS_BOT_ALLOWED_CHAT_IDS=<your_chat_id>`
   - `OPS_BOT_PUBLIC_BASE_URL=https://planka.ewg40.ru`
   - `OPS_BOT_TG_BOT_TOKEN=<telegram_bot_token>` (или `TG_BOT_TOKEN`)
2. Поднять сервис:
   - `scripts/codex/run.sh ops_bot_pm2_start`
   - `scripts/codex/run.sh ops_bot_pm2_health`
   - `scripts/codex/run.sh ops_bot_pm2_status`
3. Настроить nginx-routing:
   - `location /ops/` -> `http://127.0.0.1:8790`
   - `location /telegram/webhook/` -> `http://127.0.0.1:8790`
   - проверить: `nginx -t`
   - применить reload/restart nginx
4. Зарегистрировать webhook:
   - `curl -sS -X POST "https://api.telegram.org/bot${OPS_BOT_TG_BOT_TOKEN}/setWebhook" -d "url=https://planka.ewg40.ru/telegram/webhook/${OPS_BOT_WEBHOOK_SECRET}" -d "secret_token=${OPS_BOT_TG_SECRET_TOKEN}"`
   - `curl -sS "https://api.telegram.org/bot${OPS_BOT_TG_BOT_TOKEN}/getWebhookInfo"`
5. Проверить end-to-end:
   - `curl -sS https://planka.ewg40.ru/ops/status.json | jq .`
   - открыть `https://planka.ewg40.ru/ops/status` в браузере
   - отправить боту `/status`, `/summary 6`, `/help`, `/status_page`
6. Отписаться в задаче по шаблону:
   - `MANUAL_ROLLOUT_DONE`
   - `OPS_HEALTH: <ok/fail + details>`
   - `WEBHOOK_INFO: <ok/fail + last_error_message>`
   - `BOT_COMMANDS: <ok/fail + what exactly works>`
   - `OPS_STATUS_JSON: <ok/fail>`

## Критерии готовности
- `ops_bot_pm2_health` = OK.
- `/ops/status` и `/ops/status.json` отвечают с публичного домена.
- Telegram webhook зарегистрирован без ошибок.
- Команды бота отвечают в целевом чате.

## Rollback (ручной)
- отключить `location /ops/` и `/telegram/webhook/` в nginx;
- reload nginx;
- остановить ops bot: `scripts/codex/run.sh ops_bot_pm2_stop`.

## Flow Meta
Task-ID: ISSUE-285-MANUAL
Priority: P1
Scope: infra+ops
Status: Backlog
Flow: Backlog
Depends-On:
Blocks:
EOF

cat > "$tmp_auto_body" <<'EOF'
## Задача для автоматики
Подготовить/довести код и скрипты ops-бота до состояния, где manual rollout из соседней задачи выполняется без доработок кода.

## Что должен сделать executor
1. Проверить, что актуальные endpoints и команды реализованы:
   - `GET /health`
   - `GET /ops/status`
   - `GET /ops/status.json`
   - `POST /telegram/webhook[/<secret>]`
   - `/status`, `/summary [hours]`, `/help`, `/status_page`
2. Проверить PM2-обвязку:
   - `ops_bot_pm2_start|stop|restart|status|health`
   - корректный вывод и exit-коды для health.
3. Проверить устойчивость:
   - отсутствие падений на пустых/частично отсутствующих `.tmp/codex/*`;
   - безопасная обработка невалидного Telegram update.
4. Привести docs/runbook к текущей реализации:
   - `docs/ops-bot-dashboard.md`
   - `scripts/codex/README.md`
5. Подготовить короткий smoke-checklist для владельца окружения (для ручного rollout).

## Результат
- PR с кодом/доками (если требуются изменения).
- Комментарий в задаче с итоговым checklist для ручного этапа.

## Flow Meta
Task-ID: ISSUE-285-AUTO
Priority: P1
Scope: automation+backend+docs
Status: Backlog
Flow: Backlog
Depends-On:
Blocks: ISSUE-285-MANUAL
EOF

cat > "$tmp_post_body" <<'EOF'
## Задача для автоматики после manual rollout
После комментария `MANUAL_ROLLOUT_DONE` в manual-задаче:
1. собрать подтверждение по шагам (health/webhook/commands/status-page);
2. воспроизвести доступные проверки через локальные скрипты;
3. при проблемах — создать fix PR(ы) и довести до зеленого состояния;
4. при успехе — оставить итоговое резюме и закрыть цикл.

## Входные данные
- Комментарий владельца окружения в manual-задаче с шаблоном статуса.

## Выход
- Либо “rollout accepted” с конкретными проверками,
- Либо список инцидентов + PR с исправлениями.

## Flow Meta
Task-ID: ISSUE-285-POST-SMOKE
Priority: P1
Scope: qa+automation+ops
Status: Backlog
Flow: Backlog
Depends-On: ISSUE-285-MANUAL, ISSUE-285-AUTO
Blocks:
EOF

AUTO_ISSUE_TITLE='[ISSUE-285-AUTO] Ops bot: подготовка реализации и smoke-checklist для rollout'
POST_ISSUE_TITLE='[ISSUE-285-POST-SMOKE] Ops bot: пост-роллаут проверка и фиксы'

auto_issue_number="$(
  ensure_issue \
    "ISSUE-285-AUTO" \
    "$AUTO_ISSUE_TITLE" \
    "$tmp_auto_body" \
    ""
)"

post_issue_number="$(
  ensure_issue \
    "ISSUE-285-POST-SMOKE" \
    "$POST_ISSUE_TITLE" \
    "$tmp_post_body" \
    ""
)"

ensure_project_backlog "$auto_issue_number" || true
ensure_project_backlog "$post_issue_number" || true

cat > "$tmp_reframed_285" <<'EOF'
## Это manual-only задача владельца окружения
Смысл задачи: выполнить ручной rollout доступа к ops dashboard и Telegram webhook на `https://planka.ewg40.ru`.

Автоматика не должна брать эту задачу в работу (label `auto:ignore` обязателен).

## Детальные шаги для владельца окружения
1. Подготовить env на хосте:
   - `OPS_BOT_BIND=127.0.0.1`
   - `OPS_BOT_PORT=8790`
   - `OPS_BOT_WEBHOOK_PATH=/telegram/webhook`
   - `OPS_BOT_WEBHOOK_SECRET=<long-random-secret>`
   - `OPS_BOT_TG_SECRET_TOKEN=<long-random-header-secret>`
   - `OPS_BOT_ALLOWED_CHAT_IDS=<your_chat_id>`
   - `OPS_BOT_PUBLIC_BASE_URL=https://planka.ewg40.ru`
   - `OPS_BOT_TG_BOT_TOKEN=<telegram_bot_token>` (или `TG_BOT_TOKEN`)
2. Поднять ops-сервис:
   - `scripts/codex/run.sh ops_bot_pm2_start`
   - `scripts/codex/run.sh ops_bot_pm2_health`
   - `scripts/codex/run.sh ops_bot_pm2_status`
3. Включить nginx маршруты:
   - `/ops/` -> `127.0.0.1:8790`
   - `/telegram/webhook/` -> `127.0.0.1:8790`
   - `nginx -t` + reload.
4. Зарегистрировать webhook:
   - `curl -sS -X POST "https://api.telegram.org/bot\${OPS_BOT_TG_BOT_TOKEN}/setWebhook" -d "url=https://planka.ewg40.ru/telegram/webhook/\${OPS_BOT_WEBHOOK_SECRET}" -d "secret_token=\${OPS_BOT_TG_SECRET_TOKEN}"`
   - `curl -sS "https://api.telegram.org/bot\${OPS_BOT_TG_BOT_TOKEN}/getWebhookInfo"`
5. Проверить доступность:
   - `curl -sS https://planka.ewg40.ru/ops/status.json | jq .`
   - открыть `https://planka.ewg40.ru/ops/status`
   - команды в Telegram: `/status`, `/summary 6`, `/help`, `/status_page`.
6. Отписаться в задаче:
   - `MANUAL_ROLLOUT_DONE`
   - `OPS_HEALTH: ...`
   - `WEBHOOK_INFO: ...`
   - `BOT_COMMANDS: ...`
   - `OPS_STATUS_JSON: ...`

## Разделение на соседние задачи
- Автоматизация кода/скриптов: #__AUTO_ISSUE_NUMBER__
- Пост-роллаут проверка и доводка: #__POST_ISSUE_NUMBER__

## Flow Meta
Task-ID: ISSUE-285-MANUAL
Priority: P1
Scope: infra+ops
Status: Backlog
Flow: Backlog
Depends-On:
Blocks: ISSUE-285-AUTO, ISSUE-285-POST-SMOKE
EOF

sed -i '' "s/__AUTO_ISSUE_NUMBER__/${auto_issue_number}/g; s/__POST_ISSUE_NUMBER__/${post_issue_number}/g" "$tmp_reframed_285"

run_gh_retry_capture gh issue edit "$MANUAL_ISSUE_NUMBER" \
  --repo "$REPO" \
  --title "[ISSUE-285-MANUAL] Manual rollout: ops dashboard + Telegram webhook on planka.ewg40.ru" \
  --body-file "$tmp_reframed_285" \
  --add-label "auto:ignore" \
  --add-assignee "$ASSIGNEE" >/dev/null

ensure_project_backlog "$MANUAL_ISSUE_NUMBER" || true

echo "ISSUE_285_REFRAMED=1"
echo "MANUAL_ISSUE=${MANUAL_ISSUE_NUMBER}"
echo "AUTO_ISSUE=${auto_issue_number}"
echo "POST_SMOKE_ISSUE=${post_issue_number}"
