# PL-075 Disposable Per-Task Worktree Runtime Contract

## Контекст

Текущий authoritative runtime checkout на VPS совмещает две роли:

- control-plane база для `daemon/watchdog`, `sync_branches`, `task_finalize`;
- обычное рабочее дерево executor.

Из-за этого blocker, review/rework и post-merge residue оставляют tracked diff в том же checkout, который потом пытается брать следующую задачу. Даже при корректном результате на GitHub (`PR merged`, `Issue Done`) рантайм может требовать ручной `git reset --hard` / `git clean -fd`.

`PL-075` фиксирует целевой contract, чтобы следующие задачи `PL-076..PL-078` реализовывали один и тот же lifecycle и safety model.

## Цель

Нужна модель, где:

- authoritative checkout используется только как control-plane база;
- каждая claim-задача materialize-ится в отдельный disposable worktree;
- executor, dirty-state, коммиты и rework живут только внутри task worktree;
- review path сохраняет незавершённую работу, но не загрязняет authoritative checkout;
- cleanup делает daemon по строгим guard-условиям и без потери локальной ценности.

## Термины

- `authoritative checkout` — основной runtime checkout profile, который владеет очередью и state-файлами.
- `task key` — канонический идентификатор задачи для branch/path/state.
- `task worktree` — disposable git worktree, созданный только для одной active/review задачи.
- `task branch` — отдельная ветка задачи, checkout-нутая в task worktree.
- `head branch` — рабочая интеграционная ветка flow, сейчас `FLOW_HEAD_BRANCH` (`development`).
- `base branch` — целевая ветка PR, сейчас `FLOW_BASE_BRANCH` (`main`).
- `task metadata` — runtime-файлы, по которым daemon может продолжить review/rework или безопасно выполнить cleanup.

## Канонический runtime contract

### 1. Authoritative checkout

Authoritative checkout обязан:

- оставаться синхронным с `origin/<head-branch>` и использоваться как control-plane база;
- хранить `.flow/state`, логи, queue ownership и shared git object store;
- не быть местом пользовательских правок executor по конкретной задаче;
- не использоваться как источник `git status` активной task-дельты;
- после завершения задачи возвращаться в состояние `no task diff`.

Допустимое содержимое authoritative checkout:

- toolkit/runtime state;
- service updates уровня `.flow/shared` и конфигурации runtime;
- временное control-plane действие daemon, которое не превращает checkout в carrier task diff.

Недопустимое содержимое authoritative checkout:

- незавершённый diff task-ветки;
- review/rework residue после открытого PR;
- tracked изменения, которые требуются для продолжения конкретной issue-задачи.

### 2. Task key, branch naming и path layout

`task key` строится так:

1. взять `Task ID` из project item, если он есть;
2. иначе взять `PL-xxx` из title issue;
3. иначе использовать `ISSUE-<number>`;
4. нормализовать в slug для путей и веток: lowercase ASCII, separator `-`, без пробелов.

Канонические имена:

- task branch: `task/<task-key>`;
- worktree path: `<workspace-root>.worktrees/<task-key>`;
- metadata dir: `<state-dir>/tasks/<task-key>/`.

Пример для `PL-075`:

- `task key`: `pl-075`;
- `task branch`: `task/pl-075`;
- `worktree path`: `<workspace-root>.worktrees/pl-075`;
- `metadata dir`: `<state-dir>/tasks/pl-075/`.

Почему так:

- branch и path детерминированы и переиспользуются при rework;
- worktree лежит вне authoritative checkout и не засоряет repo root;
- cleanup можно делать по одному `task key` без эвристик по случайным каталогам.

### 3. Task metadata

Для каждого materialized task worktree daemon хранит metadata минимум с такими полями:

- `task_id`;
- `task_key`;
- `issue_number`;
- `project_item_id`;
- `task_branch`;
- `head_branch`;
- `base_branch`;
- `worktree_path`;
- `base_commit` — commit authoritative checkout в момент materialize;
- `materialized_at`;
- `last_resumed_at`;
- `runtime_state` — `materialized|running|waiting_user|in_review|rework|merge_pending|aborted|merged|cleanup_pending|cleaned`;
- `pr_number`/`pr_url` при наличии;
- `executor_pid` и/или другой runtime ownership marker активного процесса.

Metadata — это источник правды для resume/cleanup. Наличие только каталога worktree без metadata не считается валидной активной задачей.

### 4. Ownership

Распределение ответственности фиксируется так:

- daemon владеет `claim`, `materialize`, lifecycle state, cleanup scheduling и terminal decisions;
- executor владеет только изменениями внутри task worktree и не удаляет worktree сам;
- `task_finalize`/review path используют task worktree как источник task diff, но не меняют ownership cleanup;
- watchdog может инициировать recovery только по правилам daemon и не должен удалять worktree с живой локальной ценностью.

Итог: worktree живёт дольше одного запуска executor, но всегда принадлежит одной задаче и одному daemon-owned lifecycle.

## Lifecycle

### Канонические переходы state machine

| From | Event | To | Примечание |
| --- | --- | --- | --- |
| `claiming` | worktree materialized | `materialized` | metadata и worktree согласованы |
| `materialized` | executor started | `running` | executor работает только в task worktree |
| `running` | blocker/question | `waiting_user` | worktree сохраняется для resume |
| `running` | task finalized / PR opened | `in_review` | review path не триггерит cleanup |
| `in_review` | review feedback rework | `rework` | используется тот же task branch/worktree |
| `rework` | executor resumed | `running` | без пересоздания task key |
| `in_review` | PR merged | `merged` | cleanup ещё не выполнен |
| `running` / `waiting_user` / `in_review` / `rework` | abort/release/superseded/unrecoverable fail | `aborted` | terminal reason фиксируется отдельно |
| `merged` / `aborted` | cleanup scheduled | `cleanup_pending` | daemon владеет удалением worktree |
| `cleanup_pending` | cleanup finished | `cleaned` | task residue локально удалён |

### 1. Claim

Daemon при выборе `Status=Todo`:

- резервирует `task_id`, `issue_number`, `project_item_id`;
- вычисляет `task key`;
- проверяет, что по этому `task key` нет другого active lifecycle;
- переводит карточку в `In Progress`;
- создаёт metadata skeleton со state `claiming`.

На этом этапе authoritative checkout ещё не становится рабочим деревом задачи.

### 2. Materialize

Daemon materialize-ит task worktree из authoritative checkout:

- синхронизирует authoritative control-plane базу с `origin/<head-branch>`;
- фиксирует `base_commit`;
- создаёт или переиспользует task branch `task/<task-key>`;
- создаёт worktree по пути `<workspace-root>.worktrees/<task-key>`;
- записывает metadata и ownership markers;
- запускает executor с `cwd=<task-worktree>`.

Materialize завершён только когда metadata и worktree согласованы. Если каталог создан, а metadata нет, cleanup имеет право удалить такой полусостоявшийся worktree как orphan.

### 3. Executor

Во время выполнения задачи:

- все `git status`, `git diff`, `git add`, `git commit`, локальные генерации файлов и временные артефакты относятся только к task worktree;
- dirty-gate смотрит только в active task worktree;
- authoritative checkout не участвует в проверке task diff и не блокирует очередь residue этой задачи;
- промежуточные коммиты живут в task branch.

### 4. Review

Когда дельта готова к ревью:

- daemon/`task_finalize` берут diff из task worktree;
- task branch остаётся каноническим местом незавершённой работы;
- интеграция в `head branch` и PR `head -> base` делается как отдельный control-plane шаг, но без превращения authoritative checkout в обычное рабочее дерево задачи;
- metadata переводится в `in_review`, worktree не удаляется.

Это ключевое правило: открытый review не означает cleanup. Worktree должен переживать ожидание review-feedback.

### 5. Rework

Если в `Review` приходит `REWORK`:

- daemon не создаёт новый task key и не пересоздаёт branch без причины;
- executor возобновляется в том же task worktree;
- новые коммиты продолжают task branch;
- после обновления дельты интеграция в `head branch` повторяется, а PR обновляется.

То есть review/rework path обязан быть resumable без потери локальной истории и без residue в authoritative checkout.

### 6. Merge

После merge PR:

- GitHub-side сигнал переводит карточку в terminal state;
- daemon помечает task lifecycle как `merged`;
- только после этого начинается cleanup task worktree и metadata.

Merge считается успешным завершением задачи, но не равен немедленному удалению локального состояния без guard-проверок.

### 7. Abort / Release / Superseded

Если задача снята с исполнения без merge:

- metadata переводится в `aborted` или другой terminal reason;
- daemon решает, нужна ли консервация branch/worktree для ручного разбора;
- автоматический cleanup допустим только если нет локальной ценности, которую нельзя восстановить из remote/metadata.

Если такой гарантии нет, daemon оставляет task lifecycle в `cleanup_blocked` и требует явного ручного решения.

### 8. Cleanup

После terminal state daemon:

- останавливает executor и снимает task-local locks;
- убеждается, что worktree больше не нужен для review/rework;
- удаляет task worktree;
- удаляет task-local metadata и ownership markers;
- удаляет task branch только если её содержимое уже safely preserved;
- возвращает authoritative checkout в состояние `ready for next claim`.

Cleanup owner всегда daemon. Executor не должен сам решать, что задачу можно физически удалить.

## Safe cleanup rules

Автоматическая очистка разрешена только если одновременно истинно всё ниже:

- нет `active_task_id` для этого `task key`;
- нет live `executor_pid`, привязанного к worktree;
- lifecycle находится в terminal state (`merged|aborted|released|superseded|unrecoverable_failed`);
- нет ожидания review-feedback или user reply;
- нет pending PR/update action, который ещё читает локальный diff;
- task branch либо уже интегрирована/сохранена в remote, либо локальная история признана disposable по явному правилу.

Cleanup обязан быть идемпотентным:

- повторный запуск не должен ломать соседние задачи;
- отсутствие каталога worktree не считается ошибкой, если metadata уже terminal;
- orphan metadata и orphan worktree должны безопасно доочищаться только по совпадающему `task key`.

### Матрица terminal cleanup-решений

| Terminal reason | Auto-cleanup | Почему |
| --- | --- | --- |
| `merged` | да | локальная ценность уже сохранена в целевой ветке/PR |
| `released` / `superseded` без локального уникального diff | да | worktree больше не нужен для resume |
| `aborted` с чистым или полностью disposable diff | да | незавершённая работа не теряется |
| `unrecoverable_failed`, но все commit-ы уже есть в remote | да | можно безопасно удалить локальный worktree |
| `aborted` с незакоммиченным diff | нет | нужен явный manual decision |
| metadata mismatch / потеря ownership | нет | auto-heal не может доказать безопасность |
| active review/rework wait | нет | lifecycle не terminal, cleanup запрещён |

## Границы auto-heal

Auto-heal разрешён:

- доудалить orphan worktree без metadata;
- доудалить metadata после уже завершённого cleanup;
- восстановить authoritative checkout до clean control-plane state, если нет активной задачи и нет локальной ценности task diff;
- пере-materialize task worktree для resume, если metadata жива и branch/history можно восстановить без потери локальной работы.

Auto-heal запрещён:

- делать `reset --hard` authoritative checkout, если есть признаки незавершённой локальной работы;
- удалять active/review worktree только потому, что GitHub уже показывает `Review`;
- silently пересоздавать task branch поверх локальных commit-ов, не зафиксированных в remote;
- считать authoritative checkout местом для cleanup task residue за счёт потери worktree-истории.

Если daemon не может доказать безопасность auto-heal, он обязан перейти в blocked/manual state, а не пытаться "починить" рантайм эвристикой.

## Матрица ответственности по каталогам и операциям

### Операции только в authoritative checkout

- queue scan;
- `sync_branches` и поддержание control-plane базы;
- чтение/запись `.flow/state`;
- materialize/remove worktree;
- финальное решение по cleanup и auto-heal;
- диагностика ownership/runtime health.

### Операции только в task worktree

- запуск executor;
- `git status`, `git diff`, `git add`, `git commit`;
- генерация task-артефактов;
- локальная проверка diff конкретной задачи;
- blocker/rework resume.

### Операции control-plane, но со ссылкой на task worktree

- `task_finalize`;
- review/update PR;
- перевод `In Progress -> Review`;
- merge/abort cleanup decisions.

Для этих шагов authoritative checkout может читать metadata и управлять git refs, но task diff источником остаётся именно task worktree.

## Что считается выполнением acceptance criteria

По итогам `PL-075` зафиксировано:

- authoritative checkout vs task worktree contract;
- lifecycle `claim -> materialize -> executor -> review/rework -> merge/abort -> cleanup`;
- branch naming, path layout и task metadata;
- cleanup ownership;
- safe cleanup rules;
- границы auto-heal.

## Вне scope `PL-075`

Эта задача не внедряет кодом:

- реальный `git worktree add/remove` path;
- модификацию `task_finalize`, который сейчас ещё опирается на authoritative checkout как на checkout `head branch`;
- self-heal implementation;
- smoke coverage.

Это работа следующих задач:

- `PL-076` — materialize executor в task worktree и review/rework resume;
- `PL-077` — guarded cleanup и self-heal;
- `PL-078` — smoke/recovery coverage.
