# PL-078 Disposable Runtime Smoke And Recovery Coverage

## Цель

После `PL-075..077` disposable runtime model считается пригодной к возврату automation только если её можно проверить повторяемым набором live-сценариев без ручного `git reset --hard` authoritative checkout.

Этот документ фиксирует:

- канонический smoke-plan;
- recovery-сценарии, которые обязательно должны быть пройдены;
- минимальный набор evidence, достаточный для приёмки;
- критерии, после которых можно снова пускать daemon в обычный `Todo`-цикл.

## Scope

Документ покрывает только runtime-plane:

- claim disposable task worktree;
- isolated executor run;
- review/rework resume в том же task worktree;
- guarded cleanup после merge/close/release;
- stale/restart recovery.

Документ не покрывает:

- Android product smoke;
- Linux-host bootstrap;
- manifest/APK publish flow.

## Предварительные условия

Перед прогоном smoke должны выполняться все условия:

1. `main` уже содержит merge `PL-075`, `PL-076`, `PL-077`.
2. authoritative runtime checkout на VPS чистый по `git status --short`.
3. daemon и watchdog стартуют без `ERROR_LOCAL_FLOW`.
4. dirty-gate включён только если он уже переведён на task worktree semantics; если нет, его можно держать выключенным на этот smoke batch.
5. в Project нет старых открытых service-issues, которые способны забрать active context (`DIRTY-GATE`, stale fix-task и т.п.).

## Канонические evidence-команды

Базовый снимок состояния:

```bash
~/ops_status.sh
tail -n 120 /var/sites/.ai-flow/logs/planka/runtime/daemon.log
tail -n 120 /var/sites/.ai-flow/logs/planka/runtime/executor.log
```

Проверка authoritative checkout:

```bash
cd /var/sites/.ai-flow/workspaces/planka
git status --short
git rev-parse --abbrev-ref HEAD
git rev-parse --short HEAD
```

Проверка disposable task worktree:

```bash
find /var/sites/.ai-flow/state/planka/task-worktrees -maxdepth 3 -type f | sort
find /var/sites/.ai-flow/state/planka/task-worktrees -maxdepth 3 -type d | sort
```

## Smoke matrix

### Scenario A: `Todo -> claim -> materialize -> executor`

Шаги:

1. Перевести новую issue-backed задачу в `Todo`.
2. Дождаться claim daemon.
3. Проверить, что появился disposable task worktree.
4. Проверить, что executor стартует в task repo, а не в authoritative checkout.

Ожидаемое evidence:

- `daemon.log` содержит:
  - `CLAIMED_TASK_ID=...`
  - `TASK_WORKTREE_KEY=...`
  - `TASK_WORKTREE_PATH=...`
  - `TASK_WORKTREE_BRANCH=...`
- `executor.log` содержит:
  - `EXECUTOR_TASK_WORKTREE_PATH=...`
- в authoritative checkout:
  - `git status --short` пустой
- в task worktree:
  - есть `repo/`, `meta/task.env`, `meta/task.json`

Критерий pass:

- task diff не появляется в `/var/sites/.ai-flow/workspaces/planka`;
- executor реально работает в `task-worktrees/.../repo`.

### Scenario B: `review -> user comment -> rework -> resume`

Шаги:

1. Дождаться PR из task branch.
2. Оставить review feedback.
3. Дождаться resume executor.

Ожидаемое evidence:

- task branch остаётся той же;
- `TASK_KEY` не меняется;
- daemon снова запускает executor для того же `TASK_WORKTREE_PATH`;
- новый authoritative residue не появляется.

Критерий pass:

- rework идёт в том же disposable worktree;
- daemon не materialize-ит новый task repo без явной supersede semantics.

### Scenario C: `merge -> cleanup -> release`

Шаги:

1. Смёржить review PR.
2. Дождаться terminal cleanup.

Ожидаемое evidence:

- `daemon_check_replies`/`daemon_tick` фиксируют terminal state;
- `TASK_WORKTREE_CLEANUP_DONE=1`;
- task worktree directory удаляется;
- active runtime files очищаются;
- `~/ops_status.sh` возвращается к `IDLE_NO_TASKS` или берёт следующий `Todo`.

Критерий pass:

- после merge не остаётся:
  - `daemon_active_*` по этой задаче;
  - task repo на диске;
  - грязного authoritative checkout.

### Scenario D: `review PR closed without merge`

Шаги:

1. Закрыть PR без merge либо вручную перевести issue в terminal non-merge path.
2. Дождаться cleanup.

Ожидаемое evidence:

- waiting/review context очищается;
- task worktree удаляется;
- remote task branch удаляется или явно логируется как already absent;
- daemon не остаётся в `WAIT_REVIEW_FEEDBACK`.

Критерий pass:

- terminal non-merge path не требует ручного reset authoritative checkout.

### Scenario E: `status mismatch release`

Шаги:

1. Во время активной задачи вручную перевести project item из `In Progress` в `Backlog`, `Todo` или `Done`.
2. Дождаться release path daemon.

Ожидаемое evidence:

- `ACTIVE_TASK_RELEASED_STATUS_MISMATCH=1`;
- `TASK_WORKTREE_CLEANUP_DONE=1`;
- active context очищен;
- daemon возвращается в обычный цикл.

Критерий pass:

- ручной статус-перевод не оставляет orphan worktree.

### Scenario F: `auto-ignore label`

Шаги:

1. Поставить ignore-label на active issue.
2. Дождаться release path.

Ожидаемое evidence:

- `ACTIVE_TASK_RELEASED_AUTO_IGNORE_LABEL=1`;
- cleanup task worktree;
- больше нет active/waiting/review residue для этой задачи.

Критерий pass:

- ignore path освобождает runtime без ручной чистки state.

### Scenario G: `executor still alive -> cleanup skipped`

Шаги:

1. Создать ситуацию, где terminal cleanup запрашивается, но executor process ещё жив.
2. Проверить guard.

Ожидаемое evidence:

- `TASK_WORKTREE_CLEANUP_SKIPPED=EXECUTOR_RUNNING`;
- worktree не удаляется преждевременно;
- после реального окончания executor cleanup может быть повторён безопасно.

Критерий pass:

- cleanup guard не убивает живой task runtime.

### Scenario H: `daemon restart during active task`

Шаги:

1. На активной задаче перезапустить daemon.
2. Дождаться reconciliation.

Ожидаемое evidence:

- daemon читает существующий active context;
- повторно использует уже materialized task worktree;
- не создаёт второй disposable repo для той же задачи;
- после restart продолжает executor/review path, а не уходит в broken `WAIT_USER_REPLY`.

Критерий pass:

- restart не порождает duplicate task worktree и не теряет active lifecycle.

## Recovery checklist

Если smoke пошёл не по happy-path, recovery допускается только в таком порядке:

1. Проверить `~/ops_status.sh`, `daemon.log`, `executor.log`.
2. Определить:
   - это active task problem;
   - waiting/review stale context;
   - task worktree cleanup problem;
   - authoritative checkout drift.
3. Использовать только runtime-safe команды:
   - `./.flow/shared/scripts/run.sh runtime_clear_waiting`
   - `./.flow/shared/scripts/run.sh runtime_clear_review`
   - `./.flow/shared/scripts/run.sh runtime_clear_active`
   - `./.flow/shared/scripts/run.sh executor_reset`
   - `./.flow/shared/scripts/run.sh task_worktree_cleanup <task-id> <issue-number> <reason>`
4. Не использовать `git reset --hard` authoritative checkout как первый recovery шаг.

## Acceptance

`PL-078` считается закрытой, когда подтверждены все пункты:

1. Пройден минимум один happy-path batch `Todo -> PR -> merge -> cleanup`.
2. Пройден минимум один `review/rework resume` batch в том же task worktree.
3. Пройден минимум один terminal non-merge cleanup path.
4. Подтверждён guard `cleanup skipped while executor alive`.
5. Подтверждён restart/reconcile сценарий без duplicate worktree.
6. После каждого сценария authoritative checkout остаётся чистым.
7. Для возврата automation в обычный режим не требуется ручной `git reset --hard` на VPS.

## Решение о возврате automation

Возвращать daemon в обычный `Todo`-режим для product-задач можно только после того, как:

- `Scenario A`, `B`, `C`, `H` подтверждены live;
- хотя бы один из `D/E/F` подтверждён как terminal release path;
- по всем этим сценариям есть сохранённый evidence в issue comments или в отдельном smoke-report.

До этого момента disposable runtime model считается реализованной, но ещё не подтверждённой эксплуатационно.
