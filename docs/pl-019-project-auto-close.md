# PL-019 - Автозакрытие задач по merged PR

## Цель
После merge PR в `main` автоматически переводить связанные задачи `PL-xxx` в `Done` в GitHub Project.

## Как это работает
- Workflow: `.github/workflows/project-auto-close.yml`
- Trigger: `pull_request.closed` для ветки `main`
- Gate: срабатывает только если PR действительно `merged == true`
- Парсинг: ищет все `PL-[0-9]{3}` в `title` и `body` PR
- Действие: для каждого найденного ID вызывает `scripts/codex/project_set_status.sh <task-id> Done Done`

## Что нужно настроить в GitHub Secrets
- `PROJECT_AUTOMATION_TOKEN`

Требуемые права токена:
- `repo`
- `project` (read/write)

## Рекомендация по PR-текстам
Чтобы автозакрытие работало предсказуемо, держим ID задач в title/body PR в виде:
- `PL-018`
- `PL-019`

## Ограничения
- Workflow меняет только карточки в GitHub Project (`Status`, `Flow`).
- `TODO.md` и `CHANGELOG.md` остаются под контролем PR/коммитов (осознанно, чтобы не делать push из Action).
