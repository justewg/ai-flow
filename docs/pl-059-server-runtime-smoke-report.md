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

- `overall_status`: `DEGRADED` -> `WORKING`
- `daemon.state`: `WAIT_GITHUB_RATE_LIMIT` -> `EXECUTOR_STARTED`
- `watchdog.state`: `HEALTHY`
- `env_audit_status`: `ok`
- `open_pr_count`: `0`
- `active_task_id`: сначала пустой, затем claim подтверждён в daemon log
- `dirty_worktree.blocking_todo`: `false`

### Candidate Todo

- issue / task id: `PL-059` / issue `#429`
- почему считается безопасной: это штатная smoke-задача на проверку server-runtime контура, без продуктовой дельты вне automation/docs
- нет `auto:ignore`: подтверждено claim path
- нет blocking dependencies: daemon смог взять карточку после выхода из GraphQL rate-limit

### Claim Evidence

- timestamp: `2026-03-15T21:58:50Z`
- daemon log excerpt:
  - `CLAIMED_TASK_ID=PL-059`
  - `CLAIMED_ISSUE_NUMBER=429`
  - `CLAIMED_FROM_STATUS=Todo`
  - `CLAIMED_TO_STATUS=In Progress`
  - `STATE=ACTIVE_TASK_CLAIMED DETAIL=CLAIMED_TASK_ID=PL-059 | GITHUB_STATUS=OK;TELEGRAM_STATUS=SKIPPED`
  - `EXECUTOR_STARTED=1`
  - `EXECUTOR_TASK_ID=PL-059`
  - `EXECUTOR_ISSUE_NUMBER=429`
- status snapshot after claim:
  - `overall_status: WORKING`
  - `headline: Executor is processing the active task`
  - `daemon_state: EXECUTOR_STARTED`
  - `daemon_detail: EXECUTOR_STARTED=1 | GITHUB_STATUS=OK;TELEGRAM_STATUS=SKIPPED`

### Executor / Review Evidence

- branch: executor стартовал из `development`, daemon перед этим синхронизировал `main` и fast-forward`нул `development`
- PR number: не создан
- status transitions:
  - `Todo -> In Progress` подтверждено
  - дальше progress остановился на старте executor
- executor log excerpt:
  - `=== EXECUTOR_RUN_START task=PL-059 issue=429 ... ===`
  - `EXECUTOR_PROMPT_READY=1`
  - `EXECUTOR_CODEX_MODE=danger-full-access`
  - `ERROR: unexpected status 403 Forbidden: Country, region, or territory not supported, url: https://api.openai.com/v1/responses`
  - `=== EXECUTOR_RUN_FINISH task=PL-059 issue=429 rc=1 ... ===`

### Result

- final status: `PARTIAL PASS`
- manual intervention required: `yes`
- regressions found:
  - daemon/container git auth initially failed with `Permission denied (publickey)` even after switching to `/etc/ai-flow/secrets/projects/planka/repo-ssh`; runtime fix is to pin `~/.ssh/id_ed25519` and `known_hosts` via `GIT_SSH_COMMAND` instead of relying on default key discovery/agent behaviour.
  - после успешного claim/executor start VPS-side `codex` executor упал на OpenAI egress restriction: `403 Forbidden: Country, region, or territory not supported`; это уже не flow/runtime bug, а инфраструктурный blocker внешнего API-контура.

## Batch 2

### Preflight

- `overall_status`:
- `daemon.state`:
- `watchdog.state`:
- `env_audit_status`:
- `open_pr_count`:
- `active_task_id`:
- `dirty_worktree.blocking_todo`:

### Candidate Todo

- issue / task id:
- почему считается безопасной:
- нет `auto:ignore`:
- нет blocking dependencies:

### Claim Evidence

- timestamp:
- daemon log excerpt:
- status snapshot after claim:

### Executor / Review Evidence

- branch:
- PR number:
- status transitions:
- executor log excerpt:

### Result

- final status:
- manual intervention required:
- regressions found:

## Final Verdict

- smoke complete: `частично`
- fully autonomous: `нет`
- blockers discovered:
  - claim path, daemon loop, project status transition и executor start подтверждены на VPS
  - full executor/review path блокируется внешним OpenAI API restriction для VPS egress (`403 Country, region, or territory not supported`)
- follow-up tasks:
  - закрыть Linux-hosted OpenAI/VPN/egress contour в рамках `PL-050`
  - после этого повторить `PL-059` до `Review`/`Done`
