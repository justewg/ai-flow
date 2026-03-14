# ISSUE-406 smoke issue-backed backlog default

Дата: 2026-03-14

## Что проверяется

- `project_add_issue` после `gh project item-add` синхронно переводит новую issue-backed карточку в `Status=Backlog`, `Flow=Backlog`;
- остаточные state-файлы `project_new_status.txt` и `project_new_flow.txt`, предназначенные для draft task, не влияют на issue-backed сценарий;
- временная защита через label `auto:ignore` остаётся вокруг линковки и не ломает дефолтную инициализацию.

## Что сделано в этой repo-side дельте

- добавлен автоматизированный regression/smoke тест [`run.test.js`](/Users/evgenykartavchenko/sites/PLANKA/.flow/shared/scripts/run.test.js), который поднимает изолированный sandbox-репозиторий с фейковыми `gh` и `project_set_status.sh`;
- зафиксирован этот smoke-отчёт как tracked-артефакт по `ISSUE-406`.

## Что подтверждено тестом

- `run.sh project_add_issue` читает `issue_number.txt` и линкует `https://github.com/acme/planka/issues/406` через `gh project item-add`;
- сразу после линковки вызывается `project_set_status.sh ISSUE-406 Backlog Backlog`;
- значения `Todo` и `Ready`, заранее записанные в `project_new_status.txt` и `project_new_flow.txt`, в вызов `project_set_status.sh` не попадают;
- при отсутствии исходной метки `auto:ignore` helper сначала добавляет её перед линковкой, а после успешной синхронизации снимает обратно.

## Локальные проверки

- `node --test .flow/shared/scripts/run.test.js`
- `bash -n .flow/shared/scripts/run.sh`

## Что вне scope

- live-проверка реального GitHub Project не входит в эту дельту: smoke зафиксирован изолированным тестом без сетевых вызовов;
- поведение `project_add_task` и прочих путей инициализации карточек не менялось.
