# ISSUE-371 smoke clean rerun after flow hardening

Дата: 2026-03-12

## Что проверяется

- daemon после flow-hardening сам подхватывает задачу из `Todo` без ручного доталкивания;
- fixed-input runner покрывает `issue`/`pr`/`project`/`log`/`runtime` операции без новых approval prompts на вариации аргументов;
- flow доходит по цепочке `issue-backed task -> development -> PR development->main`.

## Что сделано в этой repo-side дельте

- добавлен этот smoke-отчёт как минимальный tracked-артефакт clean rerun по `ISSUE-371`;
- собраны live-evidence из `daemon.log`, `watchdog.log` и `status_snapshot` по текущему запуску `ISSUE-371`;
- в текущем прогоне явно использованы fixed-input команды runner-а:
  - `run.sh issue_view`;
  - `run.sh pr_list_open`;
  - `run.sh project_status_runtime list`;
  - `run.sh status_snapshot`;
  - `run.sh log_summary`.

## Что подтверждено по текущему rerun до финализации

- в `2026-03-12T19:52:24Z` daemon применил отложенный runtime-status для `ISSUE-371`: в `daemon.log` есть `Updated ISSUE-371: Status=Todo, Flow=Backlog`, `RUNTIME_PROJECT_STATUS_APPLIED=1` и `RUNTIME_PROJECT_STATUS_TARGET=ISSUE-371`;
- в `2026-03-12T20:07:23Z` daemon без ручного вмешательства заклеймил issue-backed item `PVTI_lAHOAPt_Q84BPyyrzgnU7As`: `CLAIMED_TASK_ID=ISSUE-371`, `CLAIMED_ISSUE_NUMBER=371`, `CLAIMED_FROM_STATUS=Todo`, `Updated ... Status=In Progress, Flow=In Progress`;
- в `2026-03-12T20:10:43Z` watchdog запустил executor для той же задачи: `EXECUTOR_STARTED=1`, `EXECUTOR_TASK_ID=ISSUE-371`, `EXECUTOR_ISSUE_NUMBER=371`;
- `run.sh status_snapshot` на `2026-03-12T20:14:09Z` показывает рабочее состояние clean rerun: `overall_status=WORKING`, `daemon.state=EXECUTOR_RUNNING`, `watchdog.state=HEALTHY`, `executor.state=RUNNING`, `open_pr_count=0`;
- `run.sh pr_list_open` вернул `[]`, то есть перед `task_finalize` у `development -> main` нет висящего review PR, и smoke идёт по чистому rerun-сценарию;
- `run.sh issue_view` вернул `number=371`, `state=OPEN`, `title="[SMOKE] clean rerun after flow hardening"`, а `run.sh project_status_runtime list` вернул `RUNTIME_PROJECT_STATUS_QUEUE_ABSENT=1`, что подтверждает штатный доступ к issue/runtime операциям через fixed-input runner;
- в текущем прогоне перечисленные fixed-input команды выполнились без дополнительных approval prompts на вариации аргументов.

## Зачем нужна отдельная tracked-дельта

- `task_finalize` требует непустые `commit_message.txt` и `stage_paths.txt`, поэтому для smoke нужен отдельный repo-side артефакт;
- дельта ограничена одним документом, чтобы проверить именно clean rerun `task branch -> development -> PR development->main`, не смешивая его с нерелевантными изменениями.

## Локальные проверки перед финализацией

- `.flow/shared/scripts/run.sh issue_view`
- `.flow/shared/scripts/run.sh pr_list_open`
- `.flow/shared/scripts/run.sh project_status_runtime list`
- `.flow/shared/scripts/run.sh status_snapshot`
- `.flow/shared/scripts/run.sh log_summary`

## Что вне scope

- пользовательские untracked-файлы и локально изменённый submodule `.flow/shared` не входят в `ISSUE-371` и в коммит не включаются;
- post-merge cleanup и auto-close issue проверяются уже после публикации review PR и не фиксируются этой минимальной repo-side дельтой.
