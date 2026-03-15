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
  - daemon/container git auth initially failed with `Permission denied (publickey)` even after switching to `/etc/ai-flow/secrets/projects/planka/repo-ssh`; runtime fix is to pin `~/.ssh/id_ed25519` and `known_hosts` via `GIT_SSH_COMMAND` instead of relying on default key discovery/agent behaviour.

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

- smoke complete:
- fully autonomous:
- blockers discovered:
- follow-up tasks:
