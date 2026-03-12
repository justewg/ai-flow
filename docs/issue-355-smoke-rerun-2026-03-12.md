# ISSUE-355 smoke rerun report

Дата: 2026-03-12

## Что проверялось

- повторный smoke после live-fix wave для ai-flow layout refactor;
- путь `daemon -> executor -> task_finalize -> PR` для новой задачи после merge `ISSUE-352`;
- отсутствие смешения нового smoke-прогона со старой head-веткой предыдущей задачи.

## Что обнаружено в live runtime

- daemon взял `ISSUE-355` автоматически сразу после закрытия review-контекста по `ISSUE-352`;
- executor стартовал для `ISSUE-355`, но первый прогон завершился blocker-комментарием в Issue;
- локальный flow profile всё ещё держал `FLOW_HEAD_BRANCH=issue-352-rerun`, поэтому новый smoke-прогон был привязан к head-ветке прошлой задачи;
- repo-side tracked дельты под `ISSUE-355` на момент старта не существовало, а значит для успешного `task_finalize` требовалась отдельная рабочая ветка и новая smoke-дельта.

## Что сделано в этой дельте

- добавлен этот smoke-report как repo-side артефакт `ISSUE-355`;
- в `.flow/config/flow.sample.env` уточнено, что `FLOW_HEAD_BRANCH` обязан указывать на активную task-ветку, потому что от него зависят branch-mismatch checks, `dev_commit_push` и выбор head branch для PR;
- локальный runtime был переведён на отдельную ветку `issue-355` вне git-дельты репозитория, чтобы финализация не переиспользовала head предыдущего smoke.

## Что подтверждает rerun

- проблема прошлого прогона была не в tracked repo-коде PLANKA, а в live runtime binding на старую head-ветку;
- для новых smoke-задач после merge предыдущего PR нужно обновлять `FLOW_HEAD_BRANCH` синхронно с task-веткой;
- после отделения новой ветки `task_finalize` может формировать отдельный PR без смешения с `ISSUE-352`.

## Проверки

- просмотрены текущие `flow-state` inputs и daemon/executor state для `ISSUE-355`;
- проверены live логи daemon/executor и подтвержден blocker первого прогона с `EXECUTOR_EXIT_CODE=2`;
- проверено отсутствие открытого PR по `ISSUE-355` перед финализацией;
- проверено, что repo-side дельта ограничена `.flow/config/flow.sample.env` и этим отчётом.

## Что вне scope

- локальные `.flow/config/flow.env` и `.flow/config/profiles/planka.env` не входят в repo-side PR и менялись только для live runtime rebinding;
- host-level shared runtime/state cleanup вне git-дерева PLANKA не входит в эту дельту.
