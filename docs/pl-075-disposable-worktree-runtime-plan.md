# PL-075 Disposable Task Worktree Runtime Contract

## Контекст

Live-инциденты `PL-067`/`PL-069` показали, что текущая модель, где authoritative checkout на VPS одновременно служит:

- control-plane базой для `sync_branches`;
- рабочим каталогом executor;
- источником dirty-gate;
- carrier'ом review/rework residue,

ломает runtime recovery. Даже когда GitHub уже консистентен (`PR merged`, `Issue Done`, `Fix-task closed`), authoritative checkout может остаться с merge residue, divergence или stale waiting state.

## Цель

Зафиксировать execution model, в которой:

- authoritative checkout используется только как stable control-plane clone;
- каждая claim-задача materialize-ится в отдельный disposable task worktree;
- executor, rework, commits и PR flow живут только внутри task worktree;
- cleanup task residue не требует ручного `git reset --hard` в authoritative checkout.

## Термины

### Authoritative checkout

Постоянный runtime clone профиля, из которого daemon:

- синхронизирует `main` и `development`;
- читает project/task state;
- materialize-ит task worktree;
- никогда не использует task diff как рабочее дерево.

### Task worktree

Одноразовый git worktree, привязанный к одной claim-задаче и существующий до terminal state этой задачи.

### Task key

Канонический идентификатор runtime execution unit:

`<profile>-<task-id>-issue-<issue-number>`

Пример:

`planka-PL-075-issue-462`

### Task branch

Изолированная ветка для task worktree:

`task/<task-id>-issue-<issue-number>-<slug>`

Пример:

`task/pl-075-issue-462-disposable-worktree-runtime`

## Path layout

Disposable worktree не живёт внутри authoritative checkout. Канонический layout:

```text
<HOST_STATE_DIR>/task-worktrees/<task-key>/
  repo/                  # git worktree root
  meta/
    task.env             # canonical metadata
    task.json            # structured state snapshot
    executor.pid
    cleanup.lock
  logs/
    executor.log
    cleanup.log
```

Для `planka` это означает путь вида:

```text
/var/sites/.ai-flow/state/planka/task-worktrees/planka-PL-075-issue-462/
```

Authoritative checkout остаётся в:

```text
/var/sites/.ai-flow/workspaces/planka
```

## Canonical metadata

Каждый task worktree обязан иметь `meta/task.env` со следующими полями:

- `TASK_KEY`
- `TASK_ID`
- `ISSUE_NUMBER`
- `PROFILE`
- `BASE_BRANCH`
- `HEAD_BRANCH`
- `TASK_BRANCH`
- `TASK_SLUG`
- `WORKTREE_PATH`
- `BASE_COMMIT`
- `CLAIMED_AT`
- `CLAIMED_BY_RUNTIME_ID`
- `EXECUTION_MODE`
- `PR_NUMBER` (пусто до открытия PR)
- `STATE`

`meta/task.json` дублирует эти данные в machine-readable виде и добавляет:

- `review_comment_id`
- `blocker_comment_id`
- `last_executor_exit_code`
- `cleanup_started_at`
- `cleanup_finished_at`
- `terminal_reason`

## Runtime contract

### Authoritative checkout разрешено

- `git fetch origin`
- `sync_branches`
- чтение backlog/project state
- `git worktree add/remove`
- bootstrap runtime metadata
- safe self-heal только в явно безопасных состояниях

### Authoritative checkout запрещено

- task edits
- `git add/commit` task diff
- PR branch publishing
- dirty-gate against unrelated historical task residue
- review/rework patch application

### Task worktree разрешено

- executor edits
- tests/lint
- `git add/commit`
- task branch push
- PR create/update
- review/rework resume
- dirty-gate и blocker analysis только для активной задачи

## Lifecycle

Канонический lifecycle:

```text
claim
  -> materialize
  -> executor_running
  -> review_wait
  -> rework_requested
  -> executor_running
  -> review_wait
  -> merged
  -> cleanup
  -> released
```

Альтернативные terminal paths:

```text
claim -> materialize -> executor_failed -> cleanup -> released
claim -> materialize -> blocked_wait_user -> executor_running -> ...
claim -> materialize -> superseded -> cleanup -> released
claim -> materialize -> aborted -> cleanup -> released
```

## Ownership

### Daemon владеет

- claim/release задачи;
- materialize task worktree;
- запись canonical metadata;
- открытие cleanup phase;
- удаление worktree после safe terminal decision;
- reconciliation между GitHub state и local runtime state.

### Executor владеет

- кодовыми правками только внутри `repo/`;
- commit/push/PR path для task branch;
- локальными test artifacts внутри task worktree;
- update `last_executor_exit_code` и task-local logs.

### Watchdog владеет

- обнаружением stale executor pid/lock;
- сигналом, что task worktree сиротский;
- cleanup только если daemon подтверждает safe terminal state;
- never performs task merge/rebase logic самостоятельно.

## Safe cleanup rules

Cleanup task worktree разрешён только если одновременно выполняется одно из terminal conditions:

1. PR merged и issue закрыта.
2. Issue/Project item переведены в `Done` или `Closed` без активного rework.
3. Task помечена `superseded` и новая claim уже authoritative.
4. Executor завершился unrecoverable failure, пользователь явно выбрал `ABORT`/`IGNORE`.
5. Daemon восстановилась после crash и task metadata показывает, что live executor/push/PR action уже отсутствуют.

Cleanup запрещён, если:

- есть живой `executor.pid`;
- открыт незавершённый PR и task в review/rework;
- есть локальный task diff без commit и ещё нет terminal decision;
- daemon не может доказать, что именно этот worktree больше не нужен текущей задаче.

## Terminal cleanup matrix

| Terminal state | Что остаётся | Что удаляется | Кто инициирует |
| --- | --- | --- | --- |
| `merged` | issue/pr metadata, final logs | `repo/`, temp locks, pid | daemon |
| `closed_without_merge` | final reason, logs | `repo/`, task branch ref on runtime side | daemon |
| `superseded` | pointer на новый task key | старый `repo/`, stale locks | daemon |
| `executor_failed_recoverable` | worktree и metadata | ничего | никто, task resumes |
| `executor_failed_unrecoverable` | logs, terminal reason | `repo/` после explicit decision | daemon |
| `aborted_by_user` | final logs | `repo/`, pending local locks | daemon |
| `daemon_restart_mid_task` | весь worktree | ничего до reconciliation | daemon/watchdog |

## Review and rework semantics

- Review comments, blocker replies и rework не создают новый authoritative diff.
- Если задача уже имеет materialized worktree, resume обязан происходить в том же `TASK_KEY`.
- Новый fix-task issue не должен materialize-ить новый authoritative residue; он либо:
  - продолжает существующий task worktree,
  - либо помечает исходный worktree `superseded` и создаёт новый `TASK_KEY` с явной связью в metadata.

## Dirty-gate contract

- Dirty-gate анализирует только активный task worktree.
- Authoritative checkout считается dirty-blocker только если в нём есть runtime-level drift, не связанный с task worktree materialization.
- Service issue про dirty worktree не создаётся повторно, если signature уже привязана к тому же `TASK_KEY` и worktree отсутствует/очищен.

## Safe self-heal boundaries

PL-075 фиксирует только policy:

- authoritative checkout можно auto-heal'ить только при `no active task`, `no live executor`, `no task worktree awaiting review/rework`;
- task worktree можно reattach/reconcile после restart по `meta/task.env` и `executor.pid`;
- unconditional `git reset --hard` в authoritative checkout запрещён.

Реализация policy остаётся в `PL-077`.

## Acceptance criteria

`PL-075` считается завершённой, когда зафиксированы:

- branch naming pattern;
- path layout disposable worktree;
- canonical metadata contract;
- lifecycle state machine;
- ownership cleanup между daemon/executor/watchdog;
- safe cleanup rules и terminal matrix;
- границы dirty-gate и safe self-heal;
- явное разделение операций authoritative checkout vs task worktree.

## Вне scope

Не входит в `PL-075`:

- реальная реализация `git worktree add/remove`;
- запуск executor внутри task worktree;
- auto-heal authoritative checkout;
- smoke/recovery tests новой модели.

Это scope задач `PL-076`, `PL-077`, `PL-078`.
