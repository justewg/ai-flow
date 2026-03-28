#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <task-id> <issue-number> <output-file>"
  exit 1
fi

task_id="$1"
issue_number="$2"
output_file="$3"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
CODEX_DIR="$(codex_export_state_dir)"
REPO="${GITHUB_REPO:-justewg/planka}"

mkdir -p "$CODEX_DIR"

issue_title=""
issue_body=""
if issue_json="$(gh issue view "$issue_number" --repo "$REPO" --json title,body --jq '.' 2>/dev/null)"; then
  issue_title="$(printf '%s' "$issue_json" | jq -r '.title // ""')"
  issue_body="$(printf '%s' "$issue_json" | jq -r '.body // ""')"
fi

reply_text=""
reply_task="$(cat "${CODEX_DIR}/daemon_user_reply_task_id.txt" 2>/dev/null || true)"
if [[ "$reply_task" == "$task_id" && -s "${CODEX_DIR}/daemon_user_reply.txt" ]]; then
  reply_text="$(cat "${CODEX_DIR}/daemon_user_reply.txt")"
fi

{
  printf '%s\n' 'Ты автономный executor разработки для репозитория PLANKA.'
  printf '\n'
  printf '%s\n' 'Контекст задачи:'
  printf '%s\n' "- Task ID: ${task_id}"
  printf '%s\n' "- Issue: #${issue_number}"
  printf '%s\n' "- Issue title: ${issue_title}"
  printf '\n'
  printf '%s\n' 'Описание issue:'
  printf '%s\n' "${issue_body}"
  printf '\n'
  printf '%s\n' 'Последний ответ пользователя в Issue (если есть):'
  printf '%s\n' "${reply_text}"
  printf '\n'
  printf '%s\n' 'Обязательные правила:'
  printf '%s\n' '1) Общение, коммиты и тексты PR — на русском.'
  printf '%s\n' '2) Один task -> один PR.'
  printf '%s\n' "3) Работай только в этой задаче: ${task_id}."
  printf '%s\n' '4) Не трогай нерелевантные файлы.'
  printf '%s\n' '5) Если нужен вопрос пользователю или есть блокер:'
  printf '%s\n' '   - сначала проверь, действительно ли от пользователя нужен новый факт, выбор или явное решение;'
  printf '%s\n' '   - если единственный разумный ответ был бы "продолжай", не публикуй blocker и не останавливайся;'
  printf '%s\n' '   - внутренние сбои executor (rate limit, сеть, GitHub, странный лог, обрыв stream, кусок кода без вопроса) не считаются вопросом пользователю: делай bounded retry, локальное продолжение или диагностический комментарий без `USER_REPLY`;'
  printf '%s\n' '   - `task_ask blocker` допустим только если в тексте есть один конкретный вопрос или явный запрос решения, на который пользователь может ответить чем-то содержательнее, чем "продолжай";'
  printf '%s\n' '   - если вопрос всё-таки нужен, message-file должен быть структурирован:'
  printf '%s\n' '     * `ASK_REASON=<needs_user_fact|needs_user_decision|needs_scope_decision>`'
  printf '%s\n' '     * `ASK_QUESTION=<один конкретный вопрос>`'
  printf '%s\n' '     * ниже можно добавить короткий контекст обычным текстом;'
  printf '%s\n' '   - если вопрос всё-таки нужен, создай файл с вопросом и выполни: .flow/shared/scripts/run.sh task_ask question <message-file> (или blocker);'
  printf '%s\n' '   - после настоящего вопроса остановись и жди ответ.'
  printf '%s\n' '6) По итогам рабочего шага:'
  printf '%s\n' "   - заполни ${CODEX_DIR}/commit_message.txt"
  printf '%s\n' "   - заполни ${CODEX_DIR}/stage_paths.txt"
  printf '%s\n' "   - обнови ${CODEX_DIR}/pr_title.txt и ${CODEX_DIR}/pr_body.txt"
  printf '%s\n' "   - в ${CODEX_DIR}/pr_body.txt обязательно зафиксируй:"
  printf '%s\n' '     * что конкретно сделано по пунктам Issue;'
  printf '%s\n' '     * какие файлы/секции изменены;'
  printf '%s\n' '     * какие проверки выполнены и результат проверок;'
  printf '%s\n' '     * что осталось вне scope текущей дельты (если есть)'
  printf '%s\n' '   - не используй расплывчатые формулировки вроде "всё сделано по задаче" без детализации'
  printf '%s\n' '   - выполни: .flow/shared/scripts/run.sh task_finalize'
  printf '%s\n' '7) Если задача финализирована для ревью:'
  printf '%s\n' '   - переведи PR в ready_for_review.'
  printf '\n'
  printf '%s\n' 'Ожидаемый режим:'
  printf '%s\n' '- Если после ответа пользователя можно продолжать — продолжай сразу.'
  printf '%s\n' '- Если задача уже в состоянии готовности к ревью — доведи до финального PR-сигнала.'
  printf '%s\n' '- Не генерируй псевдо-блокеры из строк кода, stack trace, одиночных log fragments или внутренних ошибок executor.'
  printf '\n'
  printf '%s\n' 'Начинай выполнение сейчас.'
} > "$output_file"

echo "EXECUTOR_PROMPT_READY=1"
echo "TASK_ID=$task_id"
echo "ISSUE_NUMBER=$issue_number"
echo "PROMPT_FILE=$output_file"
