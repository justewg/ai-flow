# scripts/codex

Стабильные wrapper-команды для снижения confirm-шума в Codex VSCode.

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

