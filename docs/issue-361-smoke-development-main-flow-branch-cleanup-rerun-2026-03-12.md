# ISSUE-361 development-main flow branch cleanup rerun

Дата: 2026-03-12

## Что проверяется

- fresh smoke-задача `ISSUE-361`, взятая из `Todo` в отдельную task-ветку `issue-361` от `development`;
- полный путь финализации `task-branch -> development -> PR development -> main` после shared-first runtime hardening;
- отсутствие лишних PR и сохранение контракта "один task -> один PR";
- автоматическая cleanup-проверка merged issue-ветки после merge PR в `main`.

## Что сделано в этой repo-side дельте

- создана отдельная task-ветка `issue-361` от актуальной `development`;
- добавлен этот smoke-отчёт как минимальный tracked-артефакт текущего прогона;
- рабочая дельта намеренно ограничена одним repo-side документом, чтобы проверить `task_finalize` и post-merge cleanup без дополнительных изменений в коде или runtime-конфиге.

## Что должно подтвердиться по итогам финализации и merge

- коммит сначала публикуется в `issue-361`;
- `task_finalize` fast-forward переносит tracked-дельту из `issue-361` обратно в `development`;
- открывается только один PR с head `development` и base `main`;
- после merge post-merge автоматика переводит карточку `ISSUE-361` в `Done`;
- merged task-ветка `issue-361` может быть автоматически очищена cleanup-механизмом review/runtime-контура без ручного git-вмешательства.

## Что вне scope

- live runtime state, daemon/watchdog/executor логи и удаление ветки на remote проверяются вне git-дельты репозитория;
- нерелевантные пользовательские untracked-файлы в рабочем дереве не входят в `ISSUE-361` и не затрагиваются.
