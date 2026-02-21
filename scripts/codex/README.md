# scripts/codex

Стабильные wrapper-команды для снижения confirm-шума в Codex VSCode.

## Рекомендуемый вход (один префикс)
- `scripts/codex/run.sh <command>`

Команды:
- `scripts/codex/run.sh help`
- `scripts/codex/run.sh clear <key>`
- `scripts/codex/run.sh write <key> <value...>`
- `scripts/codex/run.sh append <key> <value...>`
- `scripts/codex/run.sh copy <key> <source-file>`
- `scripts/codex/run.sh sync_branches`
- `scripts/codex/run.sh pr_list_open`
- `scripts/codex/run.sh pr_view`
- `scripts/codex/run.sh pr_create`
- `scripts/codex/run.sh pr_edit`
- `scripts/codex/run.sh commit_push`
- `scripts/codex/run.sh project_add_task`
- `scripts/codex/run.sh project_set_status`

`run.sh` читает фиксированные файлы из `.tmp/codex/`:
- `pr_number.txt`
- `pr_title.txt`
- `pr_body.txt`
- `commit_message.txt`
- `stage_paths.txt`
- `project_task_id.txt`
- `project_status.txt`
- `project_flow.txt` (опционально)
- `project_new_task_id.txt`
- `project_new_title.txt`
- `project_new_scope.txt`
- `project_new_priority.txt`
- `project_new_status.txt` (опционально)
- `project_new_flow.txt` (опционально)

Ключи для `clear/write/append/copy`:
- `pr_number`, `pr_title`, `pr_body`
- `commit_message`, `stage_paths`
- `project_task_id`, `project_status`, `project_flow`
- `project_new_task_id`, `project_new_title`, `project_new_scope`, `project_new_priority`, `project_new_status`, `project_new_flow`

Поведение `write`/`append`:
- Поддерживаются escape-последовательности, например `\n` для многострочного текста.
- Если нужен буквальный `\n`, передавайте `\\n`.

## Рекомендация по снижению confirm-окон
- Не использовать `&&`, `;`, heredoc и цепочки команд для подготовки данных.
- Делать отдельные вызовы `scripts/codex/run.sh write/append/clear`.
- Затем отдельно вызывать `scripts/codex/run.sh <action>`.

## Команды
- `dev_commit_push.sh "message" <path...>`
  - `git add` + `git commit` + `git push origin development`
- `sync_branches.sh`
  - `fetch/pull/ff-merge/push` для выравнивания `main` и `development` после merge PR
- `pr_list_open.sh`
  - список открытых PR `development -> main`
- `pr_view.sh <pr-number>`
  - просмотр PR в фиксированном JSON-формате
- `pr_create.sh <title-file> <body-file>`
  - создание PR `development -> main`
- `pr_edit.sh <pr-number> <title-file> <body-file>`
  - обновление title/body PR
- `project_set_status.sh <task-id> <status-name> [flow-name]`
  - синхронное обновление полей `Status` и `Flow` карточки проекта
- `project_add_task.sh <task-id> <title-file> <scope> <priority> [status] [flow]`
  - создание карточки задачи в проекте с заполнением `Task ID`, `Scope`, `Priority`, `Status`, `Flow`

## Подготовка
Скрипты должны быть исполняемыми:

```bash
chmod +x scripts/codex/*.sh
```
