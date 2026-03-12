# ISSUE-369 smoke issue-backed task flow rerun

Дата: 2026-03-12

## Что проверяется

- smoke стартует только через issue-backed item в `Project v2`, без draft task;
- fixed-input runner закрывает `gh`/`git`/project шаги без новых approval prompts на вариации аргументов;
- daemon сам подхватывает задачу из `Todo` и доводит её до review PR без ручного доталкивания.

## Что сделано в этой repo-side дельте

- добавлен этот smoke-отчёт как минимальный tracked-артефакт rerun по `ISSUE-369`;
- зафиксировано, что rerun опирается на уже находящуюся в `development` flow-дельту:
  - `e70fb98` с hardening `task_finalize` и approval-dispatch для fixed-input runner;
  - `e819d2f` с issue-backed helper для project flow;
- просмотрены live runtime-логи `daemon` и `watchdog` по `ISSUE-369`, чтобы подтвердить автоматический claim и запуск executor без ручного вмешательства.

## Что подтверждено по текущему rerun

- в `2026-03-12T19:18:23Z` `daemon.log` зафиксировал автоматический claim `ISSUE-369` из `Todo` с `CLAIMED_ITEM_ID=PVTI_lAHOAPt_Q84BPyyrzgnUzek` и `CLAIMED_ISSUE_NUMBER=369`, что соответствует issue-backed project item;
- сразу после claim `watchdog` выполнил `SOFT_DAEMON_TICK`, а затем в `2026-03-12T19:18:36Z` зафиксирован `EXECUTOR_STARTED=1`, `EXECUTOR_TASK_ID=ISSUE-369` и `EXECUTOR_ISSUE_NUMBER=369`;
- активный runtime-state содержит `daemon_active_task=ISSUE-369`, `daemon_active_issue_number=369` и `pr_head=development`, `pr_base=main`, то есть flow идёт по ожидаемой цепочке `Todo -> In Progress -> executor -> review PR`;
- в git-дельте для `ISSUE-369` нет новых flow-скриптов или обходных команд: smoke rerun использует уже влитый fixed-input путь через `run.sh` и последующий `task_finalize`.

## Локальные проверки перед финализацией

- `bash -n .flow/shared/scripts/run.sh .flow/shared/scripts/daemon_tick.sh .flow/shared/scripts/task_finalize.sh`
- `git diff --check`

## Что вне scope

- live GitHub evidence после публикации PR и после merge (`Review`, auto-close issue, cleanup branch) не хранится в git-дельте и проверяется уже по результату `task_finalize` и состоянию PR;
- нерелевантные пользовательские untracked-файлы в рабочем дереве не входят в `ISSUE-369` и не затрагиваются.
