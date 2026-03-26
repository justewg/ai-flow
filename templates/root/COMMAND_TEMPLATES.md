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
- приоритет: сначала canonical-команды из `.flow/shared/scripts/*.sh`; `scripts/codex/*.sh` считаются legacy compatibility wrapper.

Модель применения:
- `Префикс` — человекочитаемая короткая маска команды.
- `Шаблон` — пример формы команды.
- `Regex mask` — авторитетный паттерн allowlist, который мы редактируем руками.
- `UI mask` — короткий префикс для кнопки `Yes, and don't ask again...` в Codex VSCode.
- Я выполняю команды только в рамках allowlist-масок из этого файла.

## Wrapper-first (рекомендуемый режим)
- Canonical entrypoint: `.flow/shared/scripts/run.sh`
  - Шаблон: `.flow/shared/scripts/run.sh <command>`
  - Поддерживаемые команды: `help`, `clear`, `write`, `append`, `copy`, `dispatch`, `issue_create`, `issue_view`, `issue_comment`, `issue_close`, `sync_branches`, `pr_list`, `pr_list_open`, `pr_view`, `pr_create`, `pr_edit`, `pr_merge`, `commit_push`, `git_ls_remote_heads`, `git_delete_branch`, `project_add_task`, `project_add_issue`, `project_item_list`, `project_item_view`, `project_set_status`, `project_status_runtime`, `log_summary`, `log_tail_executor`, `log_tail_daemon_executor`, `log_tail_all`, `status_snapshot`, `next_task`, `onboarding_audit`, `bootstrap_repo`, `create_migration_kit`, `apply_migration_kit`, `daemon_tick`, `daemon_loop`, `daemon_install`, `daemon_uninstall`, `daemon_status`, `watchdog_tick`, `watchdog_loop`, `watchdog_install`, `watchdog_uninstall`, `watchdog_status`, `executor_reset`, `runtime_clear_active`, `runtime_clear_waiting`, `runtime_clear_review`, `executor_start`, `executor_tick`, `executor_build_prompt`, `task_ask`, `daemon_check_replies`, `task_finalize`
- Legacy compatibility wrapper: `scripts/codex/run.sh`
  - Шаблон: `scripts/codex/run.sh <command>`
  - Regex mask: `^scripts/codex/run\.sh(?:\s+.+)?$`
  - UI mask: `scripts/codex/run.sh`
- Canonical helper: `.flow/shared/scripts/dev_commit_push.sh`
  - Шаблон: `.flow/shared/scripts/dev_commit_push.sh "<message>" <path...>`
- Legacy compatibility wrapper: `scripts/codex/dev_commit_push.sh`
  - Шаблон: `scripts/codex/dev_commit_push.sh "<message>" <path...>`
  - Regex mask: `^scripts/codex/dev_commit_push\.sh(?:\s+.+)?$`
  - UI mask: `scripts/codex/dev_commit_push.sh`
- Canonical helper: `.flow/shared/scripts/pr_list_open.sh`
  - Шаблон: `.flow/shared/scripts/pr_list_open.sh`
- Legacy compatibility wrapper: `scripts/codex/pr_list_open.sh`
  - Шаблон: `scripts/codex/pr_list_open.sh`
  - Regex mask: `^scripts/codex/pr_list_open\.sh$`
  - UI mask: `scripts/codex/pr_list_open.sh`
- Canonical helper: `.flow/shared/scripts/pr_view.sh`
  - Шаблон: `.flow/shared/scripts/pr_view.sh <pr-number>`
- Legacy compatibility wrapper: `scripts/codex/pr_view.sh`
  - Шаблон: `scripts/codex/pr_view.sh <pr-number>`
  - Regex mask: `^scripts/codex/pr_view\.sh\s+\d+$`
  - UI mask: `scripts/codex/pr_view.sh`
- Canonical helper: `.flow/shared/scripts/pr_create.sh`
  - Шаблон: `.flow/shared/scripts/pr_create.sh <title-file> <body-file>`
- Legacy compatibility wrapper: `scripts/codex/pr_create.sh`
  - Шаблон: `scripts/codex/pr_create.sh <title-file> <body-file>`
  - Regex mask: `^scripts/codex/pr_create\.sh(?:\s+.+){2,}$`
  - UI mask: `scripts/codex/pr_create.sh`
- Canonical helper: `.flow/shared/scripts/pr_edit.sh`
  - Шаблон: `.flow/shared/scripts/pr_edit.sh <pr-number> <title-file> <body-file>`
- Legacy compatibility wrapper: `scripts/codex/pr_edit.sh`
  - Шаблон: `scripts/codex/pr_edit.sh <pr-number> <title-file> <body-file>`
  - Regex mask: `^scripts/codex/pr_edit\.sh\s+\d+(?:\s+.+){2,}$`
  - UI mask: `scripts/codex/pr_edit.sh`
- Canonical helper: `.flow/shared/scripts/project_set_status.sh`
  - Шаблон: `.flow/shared/scripts/project_set_status.sh <task-id|project-item-id> <status-name> [flow-name]`
- Legacy compatibility wrapper: `scripts/codex/project_set_status.sh`
  - Шаблон: `scripts/codex/project_set_status.sh <task-id|project-item-id> <status-name> [flow-name]`
  - Regex mask: `^scripts/codex/project_set_status\.sh(?:\s+.+){2,3}$`
  - UI mask: `scripts/codex/project_set_status.sh`
- Canonical helper: `.flow/shared/scripts/task_ask.sh`
  - Шаблон: `.flow/shared/scripts/task_ask.sh <question|blocker> <message-file>`
- Legacy compatibility wrapper: `scripts/codex/task_ask.sh`
  - Шаблон: `scripts/codex/task_ask.sh <question|blocker> <message-file>`
  - Regex mask: `^scripts/codex/task_ask\.sh\s+(?:question|blocker)\s+.+$`
  - UI mask: `scripts/codex/task_ask.sh`
- Canonical helper: `.flow/shared/scripts/daemon_check_replies.sh`
  - Шаблон: `.flow/shared/scripts/daemon_check_replies.sh`
- Legacy compatibility wrapper: `scripts/codex/daemon_check_replies.sh`
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
  - Шаблон: `gh pr list --repo <owner>/<repo> --state open --base main --head development --json number,url,title`
  - Regex mask: `^gh pr list(?:\s+.+)?$`
  - UI mask: `gh pr list`
- Префикс: `gh pr view`
  - Шаблон: `gh pr view <number> --repo <owner>/<repo> --json number,state,url,title,headRefName,baseRefName --jq '.'`
  - Regex mask: `^gh pr view\s+\d+(?:\s+--repo\s+[^\\s]+)?(?:\s+.+)?$`
  - UI mask: `gh pr view`
- Префикс: `gh pr create`
  - Шаблон: `gh pr create --repo <owner>/<repo> --base main --head development --title "<title>" --body "<body>"`
  - Regex mask: `^gh pr create(?:\s+.+)?$`
  - UI mask: `gh pr create`
- Префикс: `gh pr edit`
  - Шаблон: `gh pr edit <number> --repo <owner>/<repo> --title "<title>" --body "<body>"`
  - Regex mask: `^gh pr edit\s+\d+\s+--repo\s+[^\\s]+(?:\s+.+)?$`
  - UI mask: `gh pr edit`

## GitHub CLI (Project)
- Префикс: `gh project item-list`
  - Шаблон: `gh project item-list <project-number> --owner <owner> --limit 100 --format json --jq '<jq-filter>'`
  - Regex mask: `^gh project item-list\s+\d+\s+--owner\s+[^\\s]+(?:\s+.+)?$`
  - UI mask: `gh project item-list`
- Префикс: `gh project item-edit`
  - Шаблон: `gh project item-edit --id <item-id> --project-id <project-id> --field-id <field-id> --single-select-option-id <option-id>`
  - Regex mask: `^gh project item-edit(?:\s+.+)?$`
  - UI mask: `gh project item-edit`
- Префикс: `gh project field-list`
  - Шаблон: `gh project field-list <project-number> --owner <owner> --format json`
  - Regex mask: `^gh project field-list\s+\d+\s+--owner\s+[^\\s]+(?:\s+.+)?$`
  - UI mask: `gh project field-list`

## Локальная проверка
- Префикс: `node --check`
  - Шаблон: `node --check <file.js>`
  - Regex mask: `^node\s+--check\s+.+$`
  - UI mask: `node --check`

## Принцип ограничений
- Для операций удаления, сложных merge/rebase/cherry-pick и потенциально деструктивных действий требуется отдельное подтверждение.
- Для минимизации confirm-шумов избегаем shell-chain команд (`&&`, `;`, heredoc) и используем только отдельные вызовы `.flow/shared/scripts/run.sh` или legacy wrapper `scripts/codex/run.sh`.
- В интерактивном Codex-режиме `gh issue create/view/comment/close`, `gh pr list/merge/view`, `git ls-remote --heads`, `git branch -D`, `gh project item-add/item-list`, `project_set_status` должны идти через fixed-input команды `run.sh` + `dispatch`, а не прямыми CLI-вызовами с плавающими аргументами.
- Жёсткое правило: для GitHub flow-операций не спрашивать пользователя отдельно, «можно ли» создать temp/body/input файлы и передать их wrapper-команде. Подготовка аргументов в файлы и вызов fixed-input wrapper — часть обычного выполнения задачи.
- Просмотр runtime-логов daemon/watchdog/executor должен идти через `run.sh log_tail_*`, а не через прямые `/bin/bash -lc ... tail ...`.
- Очистка служебных `.flow/state/*` runtime-файлов должна идти через `run.sh runtime_clear_*` и `executor_reset`, а не через прямые `truncate`.
