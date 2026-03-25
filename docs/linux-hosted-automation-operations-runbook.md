# Runbook Linux-Hosted Automation

## Цель

Этот runbook фиксирует поддерживаемый эксплуатационный режим для одного profile, где есть:

- authoritative runtime на VPS, который владеет automation queue;
- локальный checkout на MacBook, который остаётся доступен для интерактивной работы и fallback.

Цель: сделать rollout, update, rollback и troubleshooting повторяемыми без reverse-engineering shell history.

## Каноническая схема

Для `planka` поддерживаемый production contour такой:

- authoritative runtime:
  - host: reg.ru VPS
  - mode: `linux-docker-hosted`
  - workspace: `/var/sites/.ai-flow/workspaces/planka`
  - docker root: `/var/sites/.ai-flow/docker/planka`
- local operator contour:
  - host: MacBook
  - mode: interactive checkout only
  - runtime role: `FLOW_AUTOMATION_RUNTIME_ROLE=interactive-only`

Ownership contract:

- the authoritative checkout must contain:
  - `FLOW_AUTOMATION_RUNTIME_ROLE=authoritative`
  - `FLOW_AUTHORITATIVE_RUNTIME_ID=<that checkout runtime id>`
- any secondary checkout for the same profile must contain:
  - `FLOW_AUTOMATION_RUNTIME_ROLE=interactive-only`

Ожидаемый результат:

- только authoritative VPS runtime может запускать фоновые `daemon/watchdog`;
- MacBook всё ещё можно использовать для ручной разработки, review и maintenance;
- `profile_init preflight` и `status_snapshot` должны явно показывать ownership summary.

## Ежедневная эксплуатация

### 1. Проверить владельца queue

На authoritative VPS checkout:

```bash
cd /var/sites/.ai-flow/workspaces/planka
./.flow/shared/scripts/run.sh profile_init preflight --profile planka
```

Ожидаемые сигналы:

- `FLOW_HOST_RUNTIME_MODE=linux-docker-hosted`
- `DAEMON_STATUS=RUNNING`
- `WATCHDOG_STATUS=RUNNING`
- `PREFLIGHT_READY=1`

Shortcut для статуса:

```bash
~/ops_status.sh
```

Штатный idle state:

- `overall_status=HEALTHY`
- `daemon_state=IDLE_NO_TASKS`

### 2. Обновить authoritative VPS runtime

```bash
~/refresh-ai-flow.sh
cd /var/sites/.ai-flow/workspaces/planka
./.flow/shared/scripts/run.sh profile_init preflight --profile planka
```

Если для обновления нужен compose refresh:

```bash
~/rerender-ai-flow-docker.sh
cd /var/sites/.ai-flow/docker/planka
docker compose --env-file .env -f docker-compose.yml restart daemon watchdog ops-bot gh-app-auth
```

### 3. Безопасно использовать MacBook

MacBook checkout можно использовать для:

- interactive coding;
- manual review and merge operations;
- docs and repository maintenance;
- emergency diagnostics.

Он не должен владеть queue, пока authoritative runtime находится на VPS. Перед локальным install/re-enable automation нужно убедиться, что в env по-прежнему:

```env
FLOW_AUTOMATION_RUNTIME_ROLE=interactive-only
```

## Cutover: MacBook -> VPS

Используй этот сценарий, когда queue owner переезжает с локальной automation на VPS.

1. Убедиться, что локальный checkout не содержит уникальных незапушенных runtime-изменений.
2. Configure the VPS runtime as authoritative:
   - `FLOW_AUTOMATION_RUNTIME_ROLE=authoritative`
   - `FLOW_AUTHORITATIVE_RUNTIME_ID=linux-docker-hosted@<host>:<workspace-path>`
3. Configure the MacBook checkout as:
   - `FLOW_AUTOMATION_RUNTIME_ROLE=interactive-only`
4. On the VPS:

```bash
~/refresh-ai-flow.sh
cd /var/sites/.ai-flow/workspaces/planka
./.flow/shared/scripts/run.sh profile_init preflight --profile planka
~/ops_status.sh
```

5. Прогнать smoke item из `Todo` и подтвердить:
   - `Todo -> In Progress -> Review -> Done`
   - no local queue claim from the MacBook
   - issue and project item close on the VPS-driven path

Reference evidence для `planka`:

- issue `#427`
- PR `#440`
- result: `merge -> Done`

## Rollback: VPS -> MacBook

Используй этот сценарий, когда VPS runtime недоступен или больше не должен владеть queue.

### Быстрый rollback

1. Stop background automation on the VPS:

```bash
cd /var/sites/.ai-flow/docker/planka
docker compose --env-file .env -f docker-compose.yml stop daemon watchdog
```

2. Change the MacBook checkout to authoritative:
   - `FLOW_AUTOMATION_RUNTIME_ROLE=authoritative`
   - `FLOW_AUTHORITATIVE_RUNTIME_ID=<mac runtime id>`
3. Ensure the VPS checkout no longer owns automation:
   - set it to `interactive-only`, or
   - keep `daemon/watchdog` stopped until a clean re-cutover.
4. On the MacBook run:

```bash
./.flow/shared/scripts/run.sh profile_init preflight --profile planka
```

5. Подтвердить, что новая `Todo`-карточка забирается только MacBook runtime.

### Возврат на VPS после rollback

Считать это новым cutover:

- refresh VPS toolkit/runtime;
- restore `authoritative` role on the VPS;
- move the MacBook back to `interactive-only`;
- repeat one smoke item.

## Checklist диагностики

### Daemon/watchdog

Симптомы:

- `ERROR_LOCAL_FLOW`
- `WAIT_BRANCH_SYNC`
- `WAIT_DIRTY_WORKTREE`
- `daemon_state` not progressing from `BOOTING`

Проверки:

```bash
~/ops_status.sh
tail -n 120 /var/sites/.ai-flow/logs/planka/runtime/daemon.log
tail -n 120 /var/sites/.ai-flow/logs/planka/runtime/executor.log
git -C /var/sites/.ai-flow/workspaces/planka status --short
```

Типовые действия:

- resolve tracked merge conflicts and commit them;
- align the authoritative workspace to `origin/development` if runtime history drifted;
- keep only `M .flow/shared` as the acceptable runtime-update exception for `linux-docker-hosted`.

### Auth / GitHub

Симптомы:

- GitHub API failures
- project operations failing
- auth token probe degraded

Проверки:

```bash
cd /var/sites/.ai-flow/workspaces/planka
./.flow/shared/scripts/run.sh github_health_check
./.flow/shared/scripts/gh_app_auth_token.sh >/dev/null
```

Типовые действия:

- refresh runtime after toolkit/auth changes;
- verify project token and GitHub App installation state;
- ensure the authoritative runtime uses the intended server-side repo SSH key.

### Ops/status

Симптомы:

- `OPS_REMOTE_PUSH_ERROR`
- local runtime healthy but external ingest noisy

Проверки:

```bash
curl -fsS http://127.0.0.1:8790/ops/status.json | jq '{overall_status,headline,daemon_state:.daemon.state}'
curl -fsS http://127.0.0.1:8790/health
```

Интерпретация:

- loopback `/ops/status.json` and `/health` are authoritative;
- remote ingest failures (`404`/`502`) are secondary unless the task explicitly depends on external telemetry.

### OpenAI / Codex

Симптомы:

- `403 Country, region, or territory not supported`
- rate-limit reconnect loops
- executor cannot complete provider calls

Проверки:

```bash
CODEX_HOME="$HOME/.codex-server-api" codex login status
cd /var/sites/.ai-flow/workspaces/planka
CODEX_HOME="$HOME/.codex-server-api" codex exec --skip-git-repo-check "Ответь ровно строкой OK"
```

Типовые действия:

- verify the VPN path is active before the executor run;
- avoid competing heavy Codex runs during automation smoke;
- retry after token-per-minute windows reset if the provider error is purely rate-limit based.

### VPN / OpenAI contour

Симптомы:

- OpenAI region errors
- SSH drops immediately after enabling VPN
- public IP does not switch

Проверки:

```bash
~/vpn.sh route-info
~/vpn.sh start
~/vpn.sh ip
echo "$SSH_CONNECTION"
ip route get "$(echo "$SSH_CONNECTION" | awk '{print $1}')"
```

Ожидаемый результат:

- the SSH client `/32` route stays on the original gateway;
- the public IP eventually switches to the VPN egress address.

## Критерий готовности operational mode

Linux-hosted operational mode считается оформленным, когда:

- authoritative VPS runtime проходит `profile_init preflight` с `PREFLIGHT_READY=1`;
- MacBook остаётся рабочим как `interactive-only`;
- cutover и rollback между MacBook и VPS задокументированы и воспроизводимы;
- troubleshooting начинается с этого документа, а не с shell archaeology.
