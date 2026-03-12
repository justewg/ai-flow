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

cat > "$output_file" <<EOF
Ты автономный executor разработки для репозитория PLANKA.

Контекст задачи:
- Task ID: ${task_id}
- Issue: #${issue_number}
- Issue title: ${issue_title}

Описание issue:
${issue_body}

Последний ответ пользователя в Issue (если есть):
${reply_text}

Обязательные правила:
1) Общение, коммиты и тексты PR — на русском.
2) Один task -> один PR.
3) Работай только в этой задаче: ${task_id}.
4) Не трогай нерелевантные файлы.
5) Если нужен вопрос пользователю или есть блокер:
   - создай файл с вопросом;
   - выполни: .flow/shared/scripts/run.sh task_ask question <message-file> (или blocker);
   - после этого остановись (ожидание ответа).
6) По итогам рабочего шага:
   - заполни ${CODEX_DIR}/commit_message.txt
   - заполни ${CODEX_DIR}/stage_paths.txt
   - обнови ${CODEX_DIR}/pr_title.txt и ${CODEX_DIR}/pr_body.txt
   - в ${CODEX_DIR}/pr_body.txt обязательно зафиксируй:
     * что конкретно сделано по пунктам Issue;
     * какие файлы/секции изменены;
     * какие проверки выполнены и результат проверок;
     * что осталось вне scope текущей дельты (если есть)
   - не используй расплывчатые формулировки вроде "всё сделано по задаче" без детализации
   - выполни: .flow/shared/scripts/run.sh task_finalize
7) Если задача финализирована для ревью:
   - переведи PR в ready_for_review.

Ожидаемый режим:
- Если после ответа пользователя можно продолжать — продолжай сразу.
- Если задача уже в состоянии готовности к ревью — доведи до финального PR-сигнала.

Начинай выполнение сейчас.
EOF

echo "EXECUTOR_PROMPT_READY=1"
echo "TASK_ID=$task_id"
echo "ISSUE_NUMBER=$issue_number"
echo "PROMPT_FILE=$output_file"
