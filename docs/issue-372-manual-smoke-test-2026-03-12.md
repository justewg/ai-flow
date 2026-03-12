# ISSUE-372 manual smoke test

Дата: 2026-03-12

## Что проверяется

- задача `ISSUE-372` проходит по полной issue-backed flow-цепочке до review PR;
- на этапе разработки executor задаёт блокирующий вопрос через `task_ask`;
- после неверного ответа блокер не снимается и flow требует повторного корректного ответа;
- после корректного ответа в формате `CODEX_MODE: REWORK` executor возобновляет работу и может дойти до `task_finalize`.

## Что сделано в этой repo-side дельте

- добавлен этот smoke-отчёт как минимальный tracked-артефакт для `ISSUE-372`;
- зафиксирована фактическая хронология blocker/rework сценария из комментариев `Issue #372`;
- отдельно подтверждено, что перед финализацией у `development -> main` нет открытого review PR.

## Что подтверждено по текущему прогону

- в `2026-03-12T20:35:23Z` flow опубликовал `AGENT_BLOCKER` с вопросом: как называется немецкая группа, известная по песне `Du Hast`;
- в `2026-03-12T20:36:04Z` пользователь ответил `Scorpions`, после чего в `2026-03-12T20:38:58Z` flow оставил задачу в blocker-состоянии и запросил отдельный `CODEX_MODE: REWORK`;
- в `2026-03-12T20:39:45Z` пользователь ответил `Rammstein`, но без префикса `CODEX_MODE: REWORK`, поэтому в `2026-03-12T20:40:41Z` flow снова не возобновил исполнение и повторно запросил корректный формат ответа;
- в `2026-03-12T20:44:57Z` пользователь отправил `CODEX_MODE: REWORK` и `Rammstein`, после чего в `2026-03-12T20:45:21Z` flow зафиксировал `AGENT_RESUMED`;
- `status_snapshot`, снятый в `2026-03-12T20:48:12Z`, показывает рабочее состояние прогона: `overall_status=WORKING`, `watchdog.state=HEALTHY`, `executor.state=RUNNING`, `active_issue=372`, `open_pr_count=0`;
- `.flow/shared/scripts/run.sh pr_list_open` вернул `[]`, то есть до `task_finalize` у `development -> main` нет открытого review PR и финализация может создать/обновить ровно один PR под эту задачу.

## Локальные проверки перед финализацией

- `gh issue view 372 --json comments --jq '.comments[] | [.createdAt, .author.login, (.body | gsub("\\n"; " "))] | @tsv'`
- `.flow/shared/scripts/run.sh pr_list_open`
- `.flow/shared/scripts/run.sh status_snapshot`

## Что вне scope

- содержимое нерелевантных untracked-файлов и локально изменённого submodule `.flow/shared` не входит в `ISSUE-372` и в коммит не включается;
- исправление возможных stale fixed-input state-файлов вне обязательных артефактов финализации не входит в этот smoke-прогон.
