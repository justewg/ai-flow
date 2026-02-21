# COMMAND_TEMPLATES.md
## Шаблоны команд и префиксы авто-разрешений

Назначение:
- зафиксировать стабильные шаблоны команд, которые используются в проектном flow;
- минимизировать лишние подтверждения в интерфейсе Codex;
- расширять список вручную по мере необходимости.

Как используем:
- команды из списка ниже считаются стандартным потоком разработки;
- если нужен новый тип команды, сначала добавляем его сюда, затем начинаем использовать;
- стараемся вызывать команды в одном и том же формате (без случайных вариаций).

## Git (стандартный flow)
- Префикс: `git add`
  - Шаблон: `git add <path...>`
- Префикс: `git commit`
  - Шаблон: `git commit -m "<message>"`
- Префикс: `git push`
  - Шаблон: `git push origin development`
- Префикс: `git fetch`
  - Шаблон: `git fetch origin`
- Префикс: `git pull`
  - Шаблон: `git pull --ff-only origin main`
- Префикс: `git merge`
  - Шаблон: `git merge --ff-only main`

## GitHub CLI (PR)
- Префикс: `gh pr list`
  - Шаблон: `gh pr list --repo justewg/planka --state open --base main --head development --json number,url,title`
- Префикс: `gh pr view`
  - Шаблон: `gh pr view <number> --repo justewg/planka --json number,state,url,title,headRefName,baseRefName --jq '.'`
- Префикс: `gh pr create`
  - Шаблон: `gh pr create --repo justewg/planka --base main --head development --title "<title>" --body "<body>"`
- Префикс: `gh pr edit`
  - Шаблон: `gh pr edit <number> --repo justewg/planka --title "<title>" --body "<body>"`

## GitHub CLI (Project)
- Префикс: `gh project item-list`
  - Шаблон: `gh project item-list 2 --owner justewg --limit 100 --format json --jq '<jq-filter>'`
- Префикс: `gh project item-edit`
  - Шаблон: `gh project item-edit --id <item-id> --project-id PVT_kwHOAPt_Q84BPyyr --field-id <field-id> --single-select-option-id <option-id>`
- Префикс: `gh project field-list`
  - Шаблон: `gh project field-list 2 --owner justewg --format json`

## Локальная проверка
- Префикс: `node --check`
  - Шаблон: `node --check <file.js>`

## Принцип ограничений
- Для операций удаления, сложных merge/rebase/cherry-pick и потенциально деструктивных действий требуется отдельное подтверждение.
