# ISSUE-368 smoke finalize-detach and approval-dispatch rerun

Дата: 2026-03-12

## Что проверяется

- success-path executor-а для `ISSUE-368`, где финализация должна дойти до `task_finalize` без self-kill и итогового `rc=143`;
- daemon-claim новой задачи из `Status=Todo` без ручного запуска и без привязки к старому review-контексту;
- fixed-input runner после toolkit hardening не требует новых approval prompts для `gh`/`git` вариаций, которые вызываются через `run.sh` и `task_finalize`.

## Что сделано в этой дельте

- добавлен этот smoke-отчёт как минимальный repo-side артефакт rerun по `ISSUE-368`;
- gitlink `/.flow/shared` обновлён до toolkit commit `296fb98`, который поверх `fe893c3` включает:
  - commit `7a593e1` с восстановлением `issue_number` из поля `Task ID` (`ISSUE-<n>`) в `scripts/daemon_tick.sh`, чтобы daemon не терял claim-path, когда Project API отдаёт пустой `content.number`;
  - commit `296fb98` с реализацией fixed-input команды `project_add_issue` в `scripts/run.sh`, уже описанной в `README.md` и `COMMAND_TEMPLATES.md`;
- зафиксировано, что базовая часть smoke опирается на toolkit commit `fe893c3` (`harden finalize reset and dispatch approvals`), который закрывает detach/reset success-path и approval-dispatch hardening для fixed-input runner.

## Что должно подтвердиться по итогам финализации

- daemon сам подхватывает `ISSUE-368` из `Todo` и сохраняет корректный `issue_number`, даже если номер issue пришлось восстановить из `Task ID`;
- executor завершает рабочий прогон через `task_finalize`, а wrapper не падает на success-path с `rc=143`;
- финализация идёт по цепочке `issue-368 -> development -> PR development -> main`;
- создаётся только один итоговый PR `development -> main`, и он переводится в `ready for review` без новых approval prompts на fixed-input `gh/git` шагах.

## Проверки

- просмотрены live runtime-логи daemon/watchdog/executor по `ISSUE-368` и подтверждён автоматический claim из `Todo` в текущем rerun;
- выполнены `bash -n .flow/shared/scripts/daemon_tick.sh` и `bash -n .flow/shared/scripts/run.sh`;
- выполнен `git -C .flow/shared diff --check`;
- выполнены два jq smoke-теста на fallback `Task ID -> issue_number` для GraphQL и `project item-list`, оба вернули `368`;
- проверено, что `run.sh help` содержит `project_add_issue`.

## Что вне scope

- детальные GitHub runtime evidence после публикации PR и после merge не входят в git-дельту репозитория и проверяются по Issue, PR и runtime-логам;
- нерелевантные пользовательские untracked-файлы в рабочем дереве не входят в `ISSUE-368` и не затрагиваются.
