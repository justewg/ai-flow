# ISSUE-358 development-main flow rerun

Дата: 2026-03-12

## Что проверяется

- fresh smoke-задача `ISSUE-358`, поднятая из `Todo` автоматикой daemon;
- возврат к каноническому контракту финализации `task-branch -> development -> PR development -> main`;
- отсутствие повторного использования старой head-ветки после smoke по `ISSUE-355`;
- стандартный переход статусов `Todo -> In Progress -> Review -> Done` без ручного nudging после merge.

## Что сделано в этой repo-side дельте

- для smoke создана отдельная task-ветка `issue-358` от `development`;
- добавлен этот отчёт как минимальная tracked-документация прогона;
- рабочая дельта намеренно ограничена одним repo-side артефактом, чтобы `task_finalize` проверялся на чистом сценарии с feature-веткой.

## Что должно подтвердиться по итогам финализации

- коммит уходит сначала в `issue-358`;
- `task_finalize` fast-forward переносит дельту из `issue-358` обратно в `development`;
- открывается или обновляется только один PR с head `development` и base `main`;
- после merge post-merge автоматика переводит карточку `ISSUE-358` в `Done`.

## Что вне scope

- live runtime логи daemon/watchdog/executor не входят в git-дельту и проверяются отдельно по state/log артефактам;
- нерелевантные пользовательские untracked-файлы вне `ISSUE-358` не затрагиваются.
