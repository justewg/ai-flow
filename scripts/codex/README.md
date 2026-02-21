# scripts/codex

Стабильные wrapper-команды для снижения confirm-шума в Codex VSCode.

## Рекомендуемый вход (один префикс)
- `scripts/codex/run.sh <command>`

Команды:
- `scripts/codex/run.sh help`
- `scripts/codex/run.sh pr_list_open`
- `scripts/codex/run.sh pr_view`
- `scripts/codex/run.sh pr_create`
- `scripts/codex/run.sh pr_edit`
- `scripts/codex/run.sh commit_push`
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

## Команды
- `dev_commit_push.sh "message" <path...>`
  - `git add` + `git commit` + `git push origin development`
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

## Подготовка
Скрипты должны быть исполняемыми:

```bash
chmod +x scripts/codex/*.sh
```
