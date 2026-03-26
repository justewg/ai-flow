# PL-075 Disposable Worktree Runtime Plan

## Зачем это нужно

Текущий authoritative runtime checkout на VPS одновременно используется как:

- база для `sync_branches`;
- рабочее дерево executor;
- место, где daemon/watchdog читают dirty-state;
- локальный источник branch/review residue после blocker/rework/merge.

Из-за этого даже при корректном GitHub-результате (`PR merged`, `Issue Done`) authoritative checkout может оставаться грязным и требовать ручного `git reset --hard` / `git clean -fd`.

## Цель

Перевести automation на модель, где:

- authoritative checkout используется только как стабильная база и control-plane;
- каждая claim-задача получает отдельный disposable worktree;
- executor, коммиты, PR и rework живут только внутри task worktree;
- cleanup после merge/abort/review не требует ручного вмешательства в основной runtime checkout.

## Канонический execution model

### 1. Authoritative checkout

Authoritative runtime checkout:

- держится синхронным с `origin/<head-branch>`;
- не используется для пользовательских правок задачи;
- может содержать только toolkit/runtime state, но не task diff.

### 2. Task worktree

На каждый claim daemon materialize-ит:

- отдельный worktree path;
- отдельную task branch;
- task-local metadata (`task_id`, `issue_number`, `head_branch`, `created_at`, `base_commit`).

Именно этот worktree становится:

- рабочим каталогом executor;
- источником `git status`;
- местом коммитов и PR-операций.

### 3. Cleanup

После `Done`, `aborted`, `release`, `superseded`, `executor_failed unrecoverable` или `merge complete` daemon:

- снимает task-local locks/state;
- удаляет disposable worktree;
- очищает task branch/runtime metadata;
- возвращается в clean authoritative checkout без task residue.

## Принципы безопасности

1. Authoritative checkout нельзя автоматически `reset --hard`, если есть признаки живой незавершённой локальной работы.
2. Auto-heal допустим только в явно безопасном состоянии:
   - нет `active_task_id`;
   - нет live executor pid;
   - нет открытого task worktree для незавершённой задачи;
   - нет pending PR action, который ещё должен читать локальный diff.
3. Dirty-gate должен смотреть в task worktree активной задачи, а не в authoritative checkout.
4. Review/rework не должны превращать authoritative checkout в carrier старого diff.

## Разбиение на задачи

### PL-075

Issue: `#462`

Нужно описать runtime contract:

- layout каталогов task worktree;
- naming branch/worktree;
- lifecycle state machine;
- кто владеет cleanup;
- какие команды работают в authoritative checkout, а какие только в task worktree.

### PL-076

Issue: `#463`

Нужно внедрить:

- materialize disposable worktree на claim;
- запуск executor внутри него;
- isolated branch/commit/PR path;
- корректный rework/review resume внутри того же task worktree.

### PL-077

Issue: `#464`

Нужно внедрить:

- safe self-heal authoritative checkout;
- guarded cleanup после merge/abort/release;
- защиту от ручного residue, если GitHub уже консистентен, а локальный task worktree остался.

### PL-078

Issue: `#465`

Нужно подтвердить:

- `Todo -> claim -> review -> merge -> cleanup`;
- `blocker -> reply -> resume`;
- `executor fail -> retry/release`;
- stale worktree cleanup;
- отсутствие residue в authoritative checkout после завершения.

## Что не делать

- Не включать безусловный `git reset --hard` на каждый dirty-state.
- Не использовать authoritative checkout как обычное рабочее дерево задачи после внедрения disposable model.
- Не смешивать Android/product задачи с rollout этого hardening-track.

## Ожидаемый результат

Следующие issue-backed задачи должны выполняться так, чтобы:

- на VPS не приходилось вручную чистить authoritative checkout;
- review/rework не оставляли tracked residue в базе runtime;
- следующий `Todo` можно было безопасно брать сразу после завершения предыдущей задачи.
