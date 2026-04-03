# GraphQL Audit

Дата: `2026-03-31`

## Scope

Аудит покрывает:

- явные вызовы `gh api graphql` в runtime/tooling/CI;
- косвенные GraphQL-вызовы через `gh project item-*` и `gh project field-list`;
- daemon/runtime пути, которые реально блокируют обработку задач при GraphQL rate limit;
- текущую телеметрию и её пробелы.

Аудит не пытается оценить скрытые GraphQL-вызовы внутри `gh pr *` / `gh issue *`, потому что в коде нет собственного wrapper-а с caller-тегами для этих команд. Их надо считать отдельной непрозрачной зоной расхода.

## Главное

1. Самый дорогой consumer сейчас не executor и не operator tooling, а `daemon_tick`.
2. Критический hotspot: `PROJECT_ITEM_LIST_FALLBACK` в daemon. Он срабатывает именно тогда, когда после полного GraphQL-скана очередь `Todo` пуста, и добавляет ещё один GraphQL-heavy `gh project item-list`.
3. В idle-режиме daemon сейчас может жечь примерно `5` project-GraphQL вызовов на тик:
   - `1` на `fields`
   - `3` на `items` при `project_items_limit=250`
   - `1` fallback `gh project item-list`
4. Именно этот паттерн уже виден в прод-логах: repeated `WAIT_GITHUB_RATE_LIMIT_STAGE=PROJECT_ITEM_LIST_FALLBACK` при пустой очереди.
5. `Review -> resume` тоже сейчас зависит от полного project-read path, поэтому GraphQL limit блокирует даже уже известную задачу с новым comment.
6. Полезная телеметрия уже есть только у daemon:
   - rate-limit окна в `graphql_rate_stats.log`
   - `WAIT_GITHUB_RATE_LIMIT_*`
   Но нет:
   - per-caller counters,
   - per-query counters,
   - unified audit trail для operator/manual tooling,
   - выделения direct GraphQL vs indirect `gh project *`.

## Inventory

### Direct GraphQL callers

| Caller | File | Flow stage | Purpose | Requests per invocation | Cacheability | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `daemon_tick: fetch_project_fields_json` | [`.flow/shared/scripts/daemon_tick.sh`](/private/var/sites/PLANKA/.flow/shared/scripts/daemon_tick.sh) | Main queue read | Read `Status` field options | `1` | High | Поле/опции почти статичны; не нужно читать каждый тик |
| `daemon_tick: fetch_project_items_paginated` | [`.flow/shared/scripts/daemon_tick.sh`](/private/var/sites/PLANKA/.flow/shared/scripts/daemon_tick.sh) | Main queue read | Read project items for claim selection | `ceil(project_items_limit/100)`; сейчас обычно `3` | Medium | При `project_items_limit=250` делает `3` page queries на тик |
| `daemon_tick: find_project_item_status_by_id` | [`.flow/shared/scripts/daemon_tick.sh`](/private/var/sites/PLANKA/.flow/shared/scripts/daemon_tick.sh) | Active-task reconcile | Read one item status by known item id | `1` | Medium | Можно кэшировать коротким TTL или обновлять событиями |
| `daemon_tick: addProjectV2ItemById` | [`.flow/shared/scripts/daemon_tick.sh`](/private/var/sites/PLANKA/.flow/shared/scripts/daemon_tick.sh) | Dirty-gate recovery | Add issue to project | `1` mutation | No | Редкий путь, но дорогой и mutation |
| `project_set_status: fetch_project_fields_only` | [`.flow/shared/scripts/project_set_status.sh`](/private/var/sites/PLANKA/.flow/shared/scripts/project_set_status.sh) | Status/Flow update | Resolve field ids/options | `1` | High | Подходит под долговременный metadata cache |
| `project_set_status: fetch_project_initial_with_items` | [`.flow/shared/scripts/project_set_status.sh`](/private/var/sites/PLANKA/.flow/shared/scripts/project_set_status.sh) | Status/Flow update | Resolve item id by task/issue | `1` | Medium | Можно пропускать при cache hit по `task_id -> item_id` |
| `project_set_status: fetch_project_items_page` | [`.flow/shared/scripts/project_set_status.sh`](/private/var/sites/PLANKA/.flow/shared/scripts/project_set_status.sh) | Status/Flow update | Continue project item scan past 100 | `0..50` pages | Medium | В cold path worst-case масштабируется по размеру project |
| `project_set_status: updateProjectV2ItemFieldValue` | [`.flow/shared/scripts/project_set_status.sh`](/private/var/sites/PLANKA/.flow/shared/scripts/project_set_status.sh) | Status/Flow update | Set `Status` | `1` mutation | No | Сейчас status и flow пишутся двумя отдельными mutation |
| `project_set_status: updateProjectV2ItemFieldValue` | [`.flow/shared/scripts/project_set_status.sh`](/private/var/sites/PLANKA/.flow/shared/scripts/project_set_status.sh) | Status/Flow update | Set `Flow` | `1` mutation | No | Вторая отдельная mutation |
| `next_task` | [`.flow/shared/scripts/next_task.sh`](/private/var/sites/PLANKA/.flow/shared/scripts/next_task.sh) | Operator/manual | Pick next `Planned` task | `1` | Medium | Сейчас режет project до первых `100` items |
| `project_add_task: verify_status_flow` | [`.flow/shared/scripts/project_add_task.sh`](/private/var/sites/PLANKA/.flow/shared/scripts/project_add_task.sh) | Draft task creation | Verify final `Status/Flow` | `1` per verify | Low | Может повторяться до `4` раз за invocation |
| `scripts/ci/project_set_status.sh` | [`scripts/ci/project_set_status.sh`](/private/var/sites/PLANKA/scripts/ci/project_set_status.sh) | CI/deploy | Duplicate of shared `project_set_status` logic | same as shared | same as shared | Дублирует тот же GraphQL pattern вместо reuse shared helper |

### Indirect GraphQL callers via `gh project *`

| Caller | File | Flow stage | Purpose | Requests per invocation | Cacheability | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `run_project_item_list_fallback` | [`.flow/shared/scripts/daemon_tick.sh`](/private/var/sites/PLANKA/.flow/shared/scripts/daemon_tick.sh) | Main queue read fallback | Fetch project items through `gh project item-list` | `1` command, internally GraphQL-heavy | Low | Текущий прод-hotspot; именно он бьёт rate limit |
| `run.sh project_item_view` | [`.flow/shared/scripts/run.sh`](/private/var/sites/PLANKA/.flow/shared/scripts/run.sh) | Operator/manual | Lookup one project item by issue/task | `1` command | Medium | Сейчас читает до `250` items, потом фильтрует локально |
| `run.sh project_item_list` | [`.flow/shared/scripts/run.sh`](/private/var/sites/PLANKA/.flow/shared/scripts/run.sh) | Operator/manual | Dump/filter project items | `1` command | Low/Medium | Может быть дорого при большом `limit` |
| `project_add_task: item-create` | [`.flow/shared/scripts/project_add_task.sh`](/private/var/sites/PLANKA/.flow/shared/scripts/project_add_task.sh) | Draft task creation | Create project item | `1` command | No | CLI internal transport не прозрачен |
| `project_add_task: field-list` | [`.flow/shared/scripts/project_add_task.sh`](/private/var/sites/PLANKA/.flow/shared/scripts/project_add_task.sh) | Draft task creation | Resolve field ids/options | `1` command | High | Можно кэшировать |
| `project_add_task: item-edit` text field | [`.flow/shared/scripts/project_add_task.sh`](/private/var/sites/PLANKA/.flow/shared/scripts/project_add_task.sh) | Draft task creation | Set `Task ID` text field | `1` command | No | |
| `project_add_task: item-edit` single-select | [`.flow/shared/scripts/project_add_task.sh`](/private/var/sites/PLANKA/.flow/shared/scripts/project_add_task.sh) | Draft task creation | Set `Scope` / `Priority` / `Status` / `Flow` | `4` commands minimum | No | При verify-fail добавляет ещё `6` item-edit повторов |

## Cost model

### 1. Daemon idle tick with empty queue

Текущий path:

1. `fetch_project_fields_json` -> `1`
2. `fetch_project_items_paginated` with `project_items_limit=250` -> `3`
3. `run_project_item_list_fallback` -> `1`

Итого: примерно `5` GraphQL-bearing requests per idle tick.

При тике раз в минуту это порядка `300` запросов в час`+`любой дополнительный шум от review/status paths.

### 2. `project_set_status` cold path

Если item id не в cache:

1. fields + first page -> `1`
2. extra pages -> `0..N`
3. mutation `Status` -> `1`
4. mutation `Flow` -> `1`

Итого: `3..(3+N)` direct GraphQL requests.

При cache hit по `task_id -> item_id`:

1. fields-only -> `1`
2. mutation `Status` -> `1`
3. mutation `Flow` -> `1`

Итого: `3`.

### 3. `project_add_task`

Минимум:

1. `gh project item-create` -> `1`
2. `gh project field-list` -> `1`
3. `gh project item-edit --text` -> `1`
4. `gh project item-edit` x4 -> `4`
5. `verify_status_flow` direct GraphQL -> `1`

Итого минимум: `8` GraphQL-bearing requests.

Worst-case with all retry loops:

- ещё `3` verify,
- ещё `6` extra `item-edit` на `Status/Flow`.

Итого worst-case: `17`.

## What is actually burning the limit now

Прод-логи показывают не `PROJECT_QUERY_GRAPHQL` как основной runtime hotspot, а именно:

- `WAIT_GITHUB_RATE_LIMIT_STAGE=PROJECT_ITEM_LIST_FALLBACK`
- `WAIT_GITHUB_RATE_LIMIT_CALL=PROJECT_ITEM_LIST`

Это значит:

- основной перерасход сейчас приходит из fallback path после основного queue scan;
- even when there is no task to claim, daemon всё равно делает дорогой fallback project list;
- review-resume тоже страдает, потому что daemon до обработки уже известных review tasks доходит только после общего project-read loop.

## Existing telemetry

Что уже есть:

- `daemon_tick.sh` пишет `WAIT_GITHUB_RATE_LIMIT_*`
- ведётся `graphql_rate_stats.log` с окнами:
  - `requests`
  - `duration_sec`
  - `stage`
  - `start_utc`
  - `end_utc`
- `log_summary.sh` умеет агрегировать эти окна

Чего нет:

- per-caller counters (`daemon.project_query`, `daemon.project_item_fallback`, `project_set_status`, `project_add_task`, `next_task`, `run.sh project_item_view`, etc.)
- distinction `direct graphql` vs `indirect gh project`
- operator/Codex audit trail
- executor-side GraphQL telemetry
- per-task correlation (`task_id`, `issue_number`, `comment_id`)

## Audit design to add

### P0

1. Ввести единый wrapper для всех явных `gh api graphql` вызовов.
   Интерфейс:
   - `graphql_call <caller> <stage> <cacheability> -- gh api graphql ...`
   Писать в новый лог:
   - `<log-dir>/runtime/graphql_audit.log`

   Поля:
   - `ts`
   - `caller`
   - `stage`
   - `mode=direct`
   - `task_id`
   - `issue_number`
   - `project_item_id`
   - `cacheability`
   - `outcome=success|rate_limit|auth|error`
   - `duration_ms`
   - `query_family`

2. Ввести аналогичный wrapper для `gh project item-list|item-edit|item-create|field-list`.
   Поля те же, но:
   - `mode=indirect_cli_project`
   - `command_family=item-list|item-edit|item-create|field-list`

3. Убрать `PROJECT_ITEM_LIST_FALLBACK` из обычного idle tick.
   Это первый кандидат на резкое снижение расхода.

4. Развязать `review-resume` от полного project queue read.
   Если reply уже известен и task уже известна, resume path не должен зависеть от очередного глобального `project item list`.

### P1

1. Кэшировать metadata project fields/options отдельно от item queue.
2. Сделать short-TTL cache для full project item snapshot.
3. В `project_set_status` хранить и использовать `task_id -> item_id`, чтобы холодный full scan был редким исключением.
4. Ужать `project_add_task`:
   - reuse cached field metadata,
   - не verify-ить GraphQL после каждого набора edits без backoff strategy,
   - возможно batch/reduce number of edits where CLI allows.

### P2

1. Дедуплицировать `scripts/ci/project_set_status.sh` и shared `project_set_status.sh`.
2. Добавить audit rollup в `log_summary.sh`:
   - top callers
   - total calls
   - rate-limit hits by caller
   - average calls per daemon tick

## Immediate compression opportunities

| Priority | Change | Why |
| --- | --- | --- |
| P0 | Remove `PROJECT_ITEM_LIST_FALLBACK` from idle tick | Это текущий observed hotspot в проде |
| P0 | Resume review task without global queue read | Свободные human-needed задачи иначе будут вечно зависеть от общего GraphQL лимита |
| P0 | Cache project field metadata | Сейчас лишний static read на каждом queue/status path |
| P1 | Cache `task_id -> item_id` everywhere | Убирает full item scan из `project_set_status` |
| P1 | Replace `next_task` single-page `100` query with paginated/cached path | Иначе и blind spot, и лишний будущий расход |
| P1 | Instrument operator wrappers | Сейчас расход в ручной/Codex работе почти не виден |

## Practical conclusion

Если ничего не менять, система и дальше будет жить по циклу:

1. daemon idle/review loop делает full project scan;
2. при пустой очереди делает ещё и fallback item-list;
3. упирается в GraphQL limit;
4. не может обработать даже уже известный review reply;
5. после reset лимита повторяет тот же паттерн.

Первый осмысленный шаг — не “ещё сильнее терпеть лимит”, а убрать fallback из normal tick и ввести per-caller audit logging, чтобы следующий расход был виден не как один общий `WAIT_GITHUB_RATE_LIMIT`, а как конкретная таблица по caller-ам.
