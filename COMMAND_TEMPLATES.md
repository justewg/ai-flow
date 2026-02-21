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

Модель применения:
- `Префикс` — человекочитаемая короткая маска команды.
- `Шаблон` — пример формы команды.
- `Regex mask` — авторитетный паттерн allowlist, который мы редактируем руками.
- Я выполняю команды только в рамках allowlist-масок из этого файла.

## Git (стандартный flow)
- Префикс: `git add`
  - Шаблон: `git add <path...>`
  - Regex mask: `^git add(?:\s+.+)?$`
- Префикс: `git commit`
  - Шаблон: `git commit -m "<message>"`
  - Regex mask: `^git commit(?:\s+.+)?$`
- Префикс: `git push`
  - Шаблон: `git push origin development`
  - Regex mask: `^git push(?:\s+origin\s+development)?$`
- Префикс: `git fetch`
  - Шаблон: `git fetch origin`
  - Regex mask: `^git fetch(?:\s+origin)?$`
- Префикс: `git pull`
  - Шаблон: `git pull --ff-only origin main`
  - Regex mask: `^git pull(?:\s+--ff-only\s+origin\s+(?:main|development))?$`
- Префикс: `git merge`
  - Шаблон: `git merge --ff-only main`
  - Regex mask: `^git merge\s+--ff-only\s+main$`

## GitHub CLI (PR)
- Префикс: `gh pr list`
  - Шаблон: `gh pr list --repo justewg/planka --state open --base main --head development --json number,url,title`
  - Regex mask: `^gh pr list(?:\s+.+)?$`
- Префикс: `gh pr view`
  - Шаблон: `gh pr view <number> --repo justewg/planka --json number,state,url,title,headRefName,baseRefName --jq '.'`
  - Regex mask: `^gh pr view\s+\d+(?:\s+--repo\s+justewg/planka)?(?:\s+.+)?$`
- Префикс: `gh pr create`
  - Шаблон: `gh pr create --repo justewg/planka --base main --head development --title "<title>" --body "<body>"`
  - Regex mask: `^gh pr create(?:\s+.+)?$`
- Префикс: `gh pr edit`
  - Шаблон: `gh pr edit <number> --repo justewg/planka --title "<title>" --body "<body>"`
  - Regex mask: `^gh pr edit\s+\d+\s+--repo\s+justewg/planka(?:\s+.+)?$`

## GitHub CLI (Project)
- Префикс: `gh project item-list`
  - Шаблон: `gh project item-list 2 --owner justewg --limit 100 --format json --jq '<jq-filter>'`
  - Regex mask: `^gh project item-list\s+2\s+--owner\s+justewg(?:\s+.+)?$`
- Префикс: `gh project item-edit`
  - Шаблон: `gh project item-edit --id <item-id> --project-id PVT_kwHOAPt_Q84BPyyr --field-id <field-id> --single-select-option-id <option-id>`
  - Regex mask: `^gh project item-edit(?:\s+.+)?$`
- Префикс: `gh project field-list`
  - Шаблон: `gh project field-list 2 --owner justewg --format json`
  - Regex mask: `^gh project field-list\s+2\s+--owner\s+justewg(?:\s+.+)?$`

## Локальная проверка
- Префикс: `node --check`
  - Шаблон: `node --check <file.js>`
  - Regex mask: `^node\s+--check\s+.+$`

## Принцип ограничений
- Для операций удаления, сложных merge/rebase/cherry-pick и потенциально деструктивных действий требуется отдельное подтверждение.
