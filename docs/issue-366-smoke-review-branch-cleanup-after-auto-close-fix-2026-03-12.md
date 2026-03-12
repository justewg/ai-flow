# ISSUE-366 smoke review-branch cleanup after auto-close fix

Дата: 2026-03-12

## Что проверяется

- fresh smoke-задача `ISSUE-366`, взятая daemon из `Todo` после публикации cleanup-fix в toolkit commit `5b2a241`;
- создание отдельной task-ветки `issue-366` от актуальной `development`;
- полный путь `task-branch -> development -> PR development -> main` без лишних review/task PR;
- race-сценарий, где workflow может auto-close Issue раньше, чем daemon завершит cleanup review task-ветки;
- автоматическое удаление merged remote-ветки `origin/issue-366` без ручного recovery после merge.

## Что сделано в этой repo-side дельте

- создана отдельная task-ветка `issue-366` от текущей `development`;
- добавлен этот smoke-отчёт как единственный tracked-артефакт текущего прогона;
- repo-side дельта намеренно ограничена одним документом, чтобы проверить cleanup review branch context после auto-close fix без дополнительных изменений в коде или runtime-конфиге;
- зафиксировано, что shared toolkit в репозитории уже указывает на commit `5b2a241b6057b515e431e651841827fe408e525a`, в котором опубликован нужный cleanup-fix.

## Что должно подтвердиться по итогам финализации и merge

- daemon удерживает активную задачу `ISSUE-366` и не требует ручного восстановления review-контекста;
- `task_finalize` коммитит tracked-документ в `issue-366`, затем fast-forward переносит дельту в `development`;
- создаётся ровно один PR с head `development` и base `main`;
- после merge workflow закрывает Issue `#366` и переводит project item в `Done`;
- daemon автоматически очищает merged review/task branch `origin/issue-366`, даже если auto-close Issue происходит раньше cleanup-шага.

## Что вне scope

- live GitHub/daemon/watchdog evidence после merge не входит в git-дельту репозитория и проверяется по PR, Issue и runtime-логам;
- нерелевантные пользовательские untracked-файлы в рабочем дереве не входят в `ISSUE-366` и не затрагиваются.
