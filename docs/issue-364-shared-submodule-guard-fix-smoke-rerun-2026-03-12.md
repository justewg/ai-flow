# ISSUE-364 shared-submodule guard-fix smoke rerun

Дата: 2026-03-12

## Что проверяется

- fresh smoke-задача `ISSUE-364`, поднятая после перевода toolkit на git-submodule `/.flow/shared`;
- выполнение executor-пути через канонические entrypoint-скрипты `/.flow/shared/scripts/*`;
- guard-fix для stale project readback, который не должен отпускать active task, пока живой executor ещё работает;
- сохранение финального контракта `task-branch -> development -> PR development -> main`;
- cleanup merged task-ветки после merge финального PR.

## Что сделано в этой repo-side дельте

- создана отдельная task-ветка `issue-364` от актуальной `development`;
- добавлен этот smoke-отчёт как единственный tracked-артефакт текущего прогона;
- repo-side дельта намеренно ограничена одним документом, чтобы smoke проверял shared-submodule flow и guard-fix без вмешательства в код или runtime-конфиг;
- `ISSUE-363` зафиксирован как диагностический неуспешный прогон до guard-fix и не рассматривается как валидный smoke-результат.

## Что должно подтвердиться по итогам финализации и merge

- daemon удерживает активную задачу до завершения живого executor-процесса;
- executor работает через `/.flow/shared/scripts/*`, а не через legacy repo-local entrypoint;
- tracked-документ сначала коммитится в `issue-364`, после чего `task_finalize` fast-forward переносит дельту в `development`;
- открывается только один PR с head `development` и base `main`;
- после merge финального PR task-ветка `issue-364` очищается штатным cleanup-контуром.

## Что вне scope

- live daemon/watchdog/executor логи и runtime-state не входят в git-дельту репозитория и проверяются через flow-state/GitHub артефакты;
- нерелевантные пользовательские untracked-файлы в рабочем дереве не входят в `ISSUE-364` и не затрагиваются.
