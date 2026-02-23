# COMMAND_TEMPLATES.md
## Шаблоны команд и regex-маски авто-разрешений

Назначение:
- зафиксировать стабильные шаблоны команд, которые используются в проектном flow;
- минимизировать лишние подтверждения в интерфейсе Codex;
- расширять список вручную по мере необходимости.

Как используем:
- команды из списка ниже считаются стандартным потоком разработки;
- если нужен новый тип команды, сначала добавляем его сюда, затем начинаем использовать;
- стараемся вызывать команды в одном и том же формате (без случайных вариаций).
- приоритет: сначала wrapper-команды из `scripts/codex/*.sh`, прямые команды — fallback.

Модель применения:
- `Префикс` — человекочитаемая короткая маска команды.
- `Шаблон` — пример формы команды.
- `Regex mask` — авторитетный паттерн allowlist, который мы редактируем руками.
- `UI mask` — короткий префикс для кнопки `Yes, and don't ask again...` в Codex VSCode.
- Я выполняю команды только в рамках allowlist-масок из этого файла.

## Wrapper-first (рекомендуемый режим)
- Префикс: `scripts/codex/run.sh`
  - Шаблон: `scripts/codex/run.sh <command>`
  - Поддерживаемые команды: `help`, `clear`, `write`, `append`, `copy`, `sync_branches`, `pr_list_open`, `pr_view`, `pr_create`, `pr_edit`, `commit_push`, `project_add_task`, `project_set_status`, `next_task`, `daemon_tick`, `daemon_loop`, `daemon_install`, `daemon_uninstall`, `daemon_status`, `task_ask`, `daemon_check_replies`, `task_finalize`
  - Regex mask: `^scripts/codex/run\.sh(?:\s+.+)?$`
  - UI mask: `scripts/codex/run.sh`
- Префикс: `scripts/codex/dev_commit_push.sh`
  - Шаблон: `scripts/codex/dev_commit_push.sh "<message>" <path...>`
  - Regex mask: `^scripts/codex/dev_commit_push\.sh(?:\s+.+)?$`
  - UI mask: `scripts/codex/dev_commit_push.sh`
- Префикс: `scripts/codex/pr_list_open.sh`
  - Шаблон: `scripts/codex/pr_list_open.sh`
  - Regex mask: `^scripts/codex/pr_list_open\.sh$`
  - UI mask: `scripts/codex/pr_list_open.sh`
- Префикс: `scripts/codex/pr_view.sh`
  - Шаблон: `scripts/codex/pr_view.sh <pr-number>`
  - Regex mask: `^scripts/codex/pr_view\.sh\s+\d+$`
  - UI mask: `scripts/codex/pr_view.sh`
- Префикс: `scripts/codex/pr_create.sh`
  - Шаблон: `scripts/codex/pr_create.sh <title-file> <body-file>`
  - Regex mask: `^scripts/codex/pr_create\.sh(?:\s+.+){2,}$`
  - UI mask: `scripts/codex/pr_create.sh`
- Префикс: `scripts/codex/pr_edit.sh`
  - Шаблон: `scripts/codex/pr_edit.sh <pr-number> <title-file> <body-file>`
  - Regex mask: `^scripts/codex/pr_edit\.sh\s+\d+(?:\s+.+){2,}$`
  - UI mask: `scripts/codex/pr_edit.sh`
- Префикс: `scripts/codex/project_set_status.sh`
  - Шаблон: `scripts/codex/project_set_status.sh <task-id|project-item-id> <status-name> [flow-name]`
  - Regex mask: `^scripts/codex/project_set_status\.sh(?:\s+.+){2,3}$`
  - UI mask: `scripts/codex/project_set_status.sh`
- Префикс: `scripts/codex/task_ask.sh`
  - Шаблон: `scripts/codex/task_ask.sh <question|blocker> <message-file>`
  - Regex mask: `^scripts/codex/task_ask\.sh\s+(?:question|blocker)\s+.+$`
  - UI mask: `scripts/codex/task_ask.sh`
- Префикс: `scripts/codex/daemon_check_replies.sh`
  - Шаблон: `scripts/codex/daemon_check_replies.sh`
  - Regex mask: `^scripts/codex/daemon_check_replies\.sh$`
  - UI mask: `scripts/codex/daemon_check_replies.sh`

## Git (стандартный flow)
- Префикс: `git add`
  - Шаблон: `git add <path...>`
  - Regex mask: `^git add(?:\s+.+)?$`
  - UI mask: `git add`
- Префикс: `git commit`
  - Шаблон: `git commit -m "<message>"`
  - Regex mask: `^git commit(?:\s+.+)?$`
  - UI mask: `git commit`
- Префикс: `git push`
  - Шаблон: `git push origin development`
  - Regex mask: `^git push(?:\s+origin\s+development)?$`
  - UI mask: `git push`
- Префикс: `git fetch`
  - Шаблон: `git fetch origin`
  - Regex mask: `^git fetch(?:\s+origin)?$`
  - UI mask: `git fetch`
- Префикс: `git pull`
  - Шаблон: `git pull --ff-only origin main`
  - Regex mask: `^git pull(?:\s+--ff-only\s+origin\s+(?:main|development))?$`
  - UI mask: `git pull`
- Префикс: `git merge`
  - Шаблон: `git merge --ff-only main`
  - Regex mask: `^git merge\s+--ff-only\s+main$`
  - UI mask: `git merge`

## GitHub CLI (PR)
- Префикс: `gh pr list`
  - Шаблон: `gh pr list --repo justewg/planka --state open --base main --head development --json number,url,title`
  - Regex mask: `^gh pr list(?:\s+.+)?$`
  - UI mask: `gh pr list`
- Префикс: `gh pr view`
  - Шаблон: `gh pr view <number> --repo justewg/planka --json number,state,url,title,headRefName,baseRefName --jq '.'`
  - Regex mask: `^gh pr view\s+\d+(?:\s+--repo\s+justewg/planka)?(?:\s+.+)?$`
  - UI mask: `gh pr view`
- Префикс: `gh pr create`
  - Шаблон: `gh pr create --repo justewg/planka --base main --head development --title "<title>" --body "<body>"`
  - Regex mask: `^gh pr create(?:\s+.+)?$`
  - UI mask: `gh pr create`
- Префикс: `gh pr edit`
  - Шаблон: `gh pr edit <number> --repo justewg/planka --title "<title>" --body "<body>"`
  - Regex mask: `^gh pr edit\s+\d+\s+--repo\s+justewg/planka(?:\s+.+)?$`
  - UI mask: `gh pr edit`

## GitHub CLI (Project)
- Префикс: `gh project item-list`
  - Шаблон: `gh project item-list 2 --owner justewg --limit 100 --format json --jq '<jq-filter>'`
  - Regex mask: `^gh project item-list\s+2\s+--owner\s+justewg(?:\s+.+)?$`
  - UI mask: `gh project item-list`
- Префикс: `gh project item-edit`
  - Шаблон: `gh project item-edit --id <item-id> --project-id PVT_kwHOAPt_Q84BPyyr --field-id <field-id> --single-select-option-id <option-id>`
  - Regex mask: `^gh project item-edit(?:\s+.+)?$`
  - UI mask: `gh project item-edit`
- Префикс: `gh project field-list`
  - Шаблон: `gh project field-list 2 --owner justewg --format json`
  - Regex mask: `^gh project field-list\s+2\s+--owner\s+justewg(?:\s+.+)?$`
  - UI mask: `gh project field-list`

## Локальная проверка
- Префикс: `node --check`
  - Шаблон: `node --check <file.js>`
  - Regex mask: `^node\s+--check\s+.+$`
  - UI mask: `node --check`

## Принцип ограничений
- Для операций удаления, сложных merge/rebase/cherry-pick и потенциально деструктивных действий требуется отдельное подтверждение.
- Для минимизации confirm-шумов избегаем shell-chain команд (`&&`, `;`, heredoc) и используем только отдельные вызовы `scripts/codex/run.sh`.
