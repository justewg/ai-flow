# PL-059 Server Runtime Smoke Report

## Purpose

Этот файл фиксирует live-evidence по `PL-059`: server-side smoke на 1-2 безопасных `Todo` задачах без ручного доталкивания локальным runtime.

## Preconditions

- authoritative runtime: VPS / docker-hosted `planka`
- local runtime: interactive-only, не забирает очередь
- Remote Agent v2: `Done`
- diagnostics ingress: loopback-only
- runtime env authority: `/etc/ai-flow/public` + `/etc/ai-flow/secrets`

## Smoke Scope

- daemon сам выбирает безопасную `Todo` карточку
- проходит минимум `Todo -> In Progress`
- целевой полный happy-path:
  - `Todo -> In Progress -> Review -> Done`
- без ручного recovery/reset state
- без локального claim с macOS runtime

## Batch 1

### Preflight

- дата прогона: `2026-03-12`
- источник evidence: `docs/issue-369-smoke-issue-backed-task-flow-rerun-2026-03-12.md`
- подтвержден issue-backed сценарий без draft task и без локального nudging
- активный runtime-state на момент rerun содержал `daemon_active_task=ISSUE-369`, `daemon_active_issue_number=369`, `pr_head=development`, `pr_base=main`
- по состоянию на фиксацию `PR #370` уже был в `ready for review`; текущая проверка через `run.sh pr_view` показывает `state=CLOSED`

### Candidate Todo

- issue / task id: `ISSUE-369` / `#369`
- почему считается безопасной: smoke-rerun ограничен одним tracked-артефактом-отчётом; flow-дельта уже находилась в `development`, без новых flow-скриптов и без ручных обходов
- issue-backed item: да, отдельная draft task не использовалась
- blocking dependencies: в rerun не зафиксированы

### Claim Evidence

- timestamp: `2026-03-12T19:18:23Z`
- daemon log excerpt:
  - `CLAIMED_ITEM_ID=PVTI_lAHOAPt_Q84BPyyrzgnUzek`
  - `CLAIMED_ISSUE_NUMBER=369`
  - `CLAIMED_TASK_ID=ISSUE-369`
  - claim выполнен daemon'ом из `Todo` без ручного вмешательства
- immediately after claim flow продолжил штатный переход в executor-stage

### Executor / Review Evidence

- branch: `development -> main`
- PR number: `#370`
- status transitions:
  - `Todo -> In Progress` подтвержден claim'ом daemon'а
  - `In Progress -> Review` подтвержден существованием review PR `#370`
- executor/watchdog excerpt:
  - `2026-03-12T19:18:36Z` зафиксирован `EXECUTOR_STARTED=1`
  - `EXECUTOR_TASK_ID=ISSUE-369`
  - `EXECUTOR_ISSUE_NUMBER=369`
  - итоговый PR создан без дополнительного локального manual nudging

### Result

- final status: review path достигнут; сейчас `Issue #369` и `PR #370` уже закрыты
- manual intervention required: нет
- regressions found:
  - в этом rerun не потребовалось новых recovery-действий со стороны локальной машины
  - позднее, уже на свежем batch `PL-059`, выяснилось, что stale waiting-context с `QUESTION_KIND=BLOCKER` после merge review PR не очищался автоматически и удерживал задачу в `Review`; post-merge auto-clear был завязан только на `REVIEW_FEEDBACK`. Этот дефект относится не к Batch 1, а к следующему smoke и закрыт отдельным toolkit fix.

## Batch 2

### Preflight

- дата прогона: `2026-03-15`
- `status_snapshot` (`2026-03-15T22:30:28Z`):
  - `overall_status=BLOCKED`
  - `daemon.state=BLOCKED_EXECUTOR_FAILED`
  - `watchdog.state=RECOVERY_ACTION_APPLIED`
  - `open_pr_count=0`
  - `dirty_worktree.blocking_todo=false`
  - `dependencies.blockers=""`
- текущий blocked-state возник уже после auto-claim и executor retry; блокер относится к provider/network contour, а не к выбору задачи daemon'ом

### Candidate Todo

- issue / task id: `PL-059` / `#429`
- почему считается безопасной: задача документационная, рабочая дельта ограничена smoke-отчётом; код/runtime приложения трогать не требуется
- нет `auto:ignore`: да, `run.sh issue_view` для `#429` вернул пустой список labels
- нет blocking dependencies: да, `status_snapshot` вернул пустое значение `dependencies.blockers`

### Claim Evidence

- timestamp: `2026-03-15T21:58:50Z`
- daemon log excerpt:
  - `Updated PVTI_lAHOAPt_Q84BPyyrzgnfr4o: Status=In Progress, Flow=In Progress`
  - `CLAIMED_TASK_ID=PL-059`
  - `CLAIMED_ISSUE_NUMBER=429`
  - `CLAIMED_FROM_STATUS=Todo`
  - `CLAIMED_TO_STATUS=In Progress`
- after claim:
  - `2026-03-15T21:58:51Z STATE=ACTIVE_TASK_CLAIMED`
  - `2026-03-15T21:58:57Z EXECUTOR_STARTED=1`
  - `2026-03-15T21:58:58Z STATE=EXECUTOR_STARTED`

### Executor / Review Evidence

- branch: PR-ветка не появилась; `pr_number.txt` пустой, `open_pr_count=0`
- PR number: не создан из-за падения executor до `task_finalize`
- status transitions:
  - подтвержден минимум `Todo -> In Progress`
  - подтвержден автоматический переход `claim -> executor_start`
  - после ответа пользователя `VPN исправлен, продолжай` daemon сам выполнил `EXECUTOR_RETRY_AFTER_USER_REPLY=1`
  - watchdog сам применил `MEDIUM_RESET_EXECUTOR` после `EXECUTOR_PID_DEAD`
- executor log excerpt:
  - `2026-03-15T21:59:06Z` первый запуск завершился `rc=1`
  - корневая ошибка: `403 Forbidden: Country, region, or territory not supported` на `https://api.openai.com/v1/responses`
  - `2026-03-15T22:29:24Z` daemon сам перезапустил executor после ответа в Issue
  - `2026-03-15T22:30:15Z` повторный запуск снова ушёл в `EXECUTOR_FAILED`, после чего daemon автоматически опубликовал blocker-comment и перевёл runtime в ожидание ответа

### Result

- final status: задача остаётся в `In Progress`; полный выход в `Review` на свежем batch не достигнут
- manual intervention required:
  - локальный manual nudging для claim/retry/recovery не потребовался
  - требуется platform-level fix для executor OpenAI contour
- regressions found:
  - `codex exec` на VPS/docker runtime падает с `403 Forbidden: Country, region, or territory not supported`, несмотря на повторный запуск после пользовательского ответа про VPN
  - `ops_remote_status_push` получает `404` на `https://planka-dev.ewg40.ru/ops/ingest/status`; это не помешало claim/executor flow, но лишило smoke внешнего telemetry-evidence

## Batch 3

### Preflight

- дата прогона: `2026-03-16`
- precondition fixes, пришедшие между Batch 2 и Batch 3:
  - `PL-050` закрыла VPS contour для `codex` / VPN / OpenAI;
  - `PL-051` закрепила single-runtime ownership, поэтому local checkout больше не конкурирует с server-side queue ownership;
  - authoritative runtime для `planka` остался на VPS / `docker-hosted`.

### Candidate Todo

- issue / task id: `ISSUE-427` / `#427`
- title: `Smoke: зафиксировать cutover docker-hosted runtime как рабочий контур`
- почему считается валидным smoke:
  - issue-backed item реально был взят server-side daemon'ом из `Todo`;
  - рабочая дельта касалась только authoritative runtime/cutover документации, без ручного queue surgery;
  - завершение шло через обычный `executor -> PR -> merge -> post-merge cleanup` path.

### Claim / Review / Merge Evidence

- issue state:
  - `#427` сейчас `closed`
  - `closed_at=2026-03-16T13:07:19Z`
  - `state_reason=completed`
- review PR:
  - `PR #440`
  - title: `docs: зафиксировать authoritative docker-hosted runtime для planka`
  - `merged=true`
  - `merged_at=2026-03-16T13:07:06Z`
- project state:
  - item `#427` сейчас `Status=Closed`, `Flow=Done`

### Result

- final status:
  - full authoritative issue-backed smoke path подтверждён:
    - `Todo -> In Progress -> Review -> merge -> Done`
- manual intervention required:
  - нет; после подготовки VPS contour и ownership contract queue path завершился штатно
- regressions found:
  - в этом batch уже не потребовалось ручное recovery/reset queue ownership между MacBook и VPS
  - внешний `ops/ingest/status` оставался вторичным non-blocking наблюдением, а не blocker'ом самого smoke path

## Final Verdict

- smoke complete:
  - минимальный smoke `Todo -> In Progress` подтверждён live-claim по `PL-059` (`2026-03-15T21:58:50Z`)
  - автономный issue-backed path до review PR подтверждён rerun'ом `ISSUE-369` с PR `#370`
  - полный authoritative happy-path подтверждён Batch 3 через `ISSUE-427 -> PR #440 -> merge -> Done`
- fully autonomous:
  - daemon сам выбирает issue-backed item из `Todo`
  - claim/executor/retry/watchdog recovery path проходит без локального manual nudging
  - после `PL-050` и `PL-051` authoritative VPS runtime проходит и полный merge/close cycle без вмешательства локального queue owner
- blockers discovered:
  - исторический blocker batch `2026-03-15`: host/container OpenAI contour для `codex exec` отдавал `403 Country, region, or territory not supported`; этот слой закрыт задачей `PL-050`
  - дополнительное наблюдение: внешний `ops/ingest/status` сейчас отвечает `404`, поэтому remote status push не даёт отдельного live-evidence
- follow-up tasks:
  - `PL-050` закрыта: VPS preflight для `codex` / VPN / OpenAI теперь зелёный (`PREFLIGHT_READY=1`)
  - `PL-053` можно считать закрытой: authoritative cutover и full smoke уже подтверждены
  - `PL-057` остаётся релевантным для нормализации ingress-модели, если нужен рабочий публичный endpoint для ops/status ingest
