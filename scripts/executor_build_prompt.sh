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
# shellcheck source=./task_worktree_lib.sh
source "${SCRIPT_DIR}/task_worktree_lib.sh"
CODEX_DIR="$(codex_export_state_dir)"
state_dir="$(codex_resolve_state_dir)"
profile_name="$(codex_resolve_project_profile_name 2>/dev/null || printf '%s' "${PROJECT_PROFILE:-default}")"
profile_file="$(task_worktree_execution_profile_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
source_file="$(task_worktree_source_definition_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
spec_file="$(task_worktree_standardized_spec_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
intake_profile_file="$(task_worktree_intake_profile_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"

mkdir -p "$CODEX_DIR"

profile_kind=""
if [[ -f "$profile_file" ]]; then
  profile_kind="$(jq -r '.profile // ""' "$profile_file" 2>/dev/null || true)"
fi

if [[ ! -f "$spec_file" || ! -f "$source_file" || ! -f "$intake_profile_file" ]]; then
  /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/task_interpret.sh" "$task_id" "$issue_number" >/dev/null
fi

if [[ "$profile_kind" == "micro" ]]; then
  /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/context_builder.sh" "$task_id" "$issue_number" "$output_file"
  echo "EXECUTOR_PROMPT_READY=1"
  echo "TASK_ID=$task_id"
  echo "ISSUE_NUMBER=$issue_number"
  echo "PROMPT_FILE=$output_file"
  echo "EXECUTION_PROFILE=micro"
  exit 0
fi

source_json="$(cat "$source_file")"
spec_json="$(cat "$spec_file")"
intake_profile_json="$(cat "$intake_profile_file")"
issue_title="$(printf '%s' "$source_json" | jq -r '.title // ""')"
issue_body="$(printf '%s' "$source_json" | jq -r '.body // ""')"

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
  printf '%s\n' "- Source title: ${issue_title}"
  printf '\n'
  printf '%s\n' 'Normalized task spec:'
  printf '%s\n' "- Profile decision: $(printf '%s' "$spec_json" | jq -r '.profileDecision // "standard"')"
  printf '%s\n' "- Decision reason: $(printf '%s' "$spec_json" | jq -r '.decisionReason // ""')"
  printf '%s\n' "- Interpreted intent: $(printf '%s' "$spec_json" | jq -r '.interpretedIntent // ""')"
  printf '%s\n' '- Candidate target files:'
  printf '%s' "$spec_json" | jq -r '.candidateTargetFiles[]? | "  - " + .' || true
  printf '%s\n' '- Expected change:'
  printf '%s' "$spec_json" | jq -r '.expectedChange[]? | "  - " + .' || true
  printf '%s\n' '- Checks:'
  printf '%s' "$spec_json" | jq -r '.checks[]? | "  - " + .' || true
  printf '%s\n' '- Notes:'
  printf '%s' "$spec_json" | jq -r '.notes[]? | "  - " + .' || true
  printf '%s\n' "- Confidence: $(printf '%s' "$spec_json" | jq -r '.confidence.label // "unknown"') ($(printf '%s' "$spec_json" | jq -r '(.confidence.score // 0) | tostring'))"
  printf '\n'
  printf '%s\n' 'Source Definition (audit only, not primary execution contract):'
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
echo "EXECUTION_PROFILE=standard"
