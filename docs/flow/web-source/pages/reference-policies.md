# Политики, runtime state и supported scenarios

## Approve / noise policy

- Канонический инженерный entrypoint: `.flow/shared/scripts/run.sh <command>`.
- Ручные ad-hoc вызовы `gh`, `git` и внутренних helper-скриптов должны оставаться исключением, а не нормой.
- Изменения задачи не считаются завершенными до заполнения commit/PR state и запуска `task_finalize`.
- Создание временных файлов и директорий (`mktemp`, `.flow/tmp`, `/tmp`, body-файлы для `gh`/workflow/helper-скриптов) не считается отдельным approval-событием и не должно выноситься на согласование само по себе.
- Если команда всё же требует approval, причиной считается внешнее действие в той же команде (например, `gh issue create`, `gh api`, сеть, запись вне sandbox), а не сам факт создания временного файла.
- Команды, которые потенциально требуют approval (`gh`, `git push`, сетевые вызовы, запись вне sandbox), нужно отделять от подготовки temp-файлов и локальных данных. Не склеивать их в один shell-кусок через `&&`, `;`, subshell и similar chaining, если это мешает сессионному approval.
- По умолчанию названия и описания новых задач, backlog-item и issue пишутся по-русски, если пользователь явно не просил английский текст.

## Runtime state и логи

- Runtime state хранится в `<state-dir>` и не подменяет GitHub Project как источник статусов задачи.
- `status_snapshot` и `log_summary` считаются каноническим интерфейсом для диагностики.
- Логи daemon/watchdog/executor и PM2 должны быть разведены по profile/log-root, а не смешаны между проектами.

## Shared toolkit и submodule policy

- Shared toolkit остается каноническим reusable слоем.
- Consumer-project не должен копировать toolkit-content в разрозненном виде, если достаточно `/.flow/shared`.
- Bootstrap/migration должны materialize именно тот layout, который ожидают `flow_configurator`, `profile_init` и runtime services.

## Supported scenarios

- issue-backed task flow через GitHub Project;
- review feedback cycle с возвратом `Review -> In Progress`;
- onboarding нового проекта;
- migration existing project в новый profile;
- ops/status publish и split-runtime диагностика;
- post-merge deploy и автоматическая публикация web-docs.

## Какие изменения во flow обязаны сопровождаться апдейтом docs-source

- изменение жизненного цикла задачи, состояний или ожиданий daemon/watchdog/executor;
- изменение канонических entrypoint-команд, bootstrap/configurator/migration path;
- изменение deploy/publish automation, которое влияет на `development -> main` или post-merge поведение;
- изменение supported scenarios, runbook или operational states;
- появление новой канонической подсистемы flow, которую надо отразить в структуре web-docs;
- изменение source mapping между repo-docs и web-секциями.

## Что обновлять при таких изменениях

1. Исходный runbook или markdown-источник, где появилась новая истина.
2. Соответствующую страницу в `docs/flow/web-source/pages/`, если меняется каноническое публичное описание.
3. `docs/flow/web-source/source-map.json`, если меняется mapping или состав generated sections.
4. `CHANGELOG.md`, если изменение фактически завершено и должно попасть в release delta.
