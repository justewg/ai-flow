# Remote Agent v2 Execution Plan

## Статус по факту

Ниже зафиксирован execution-plan для `RA2-001..RA2-006` и текущее состояние реализации.

Важно:

- задачи `RA2-001..RA2-006` синхронизированы в отдельные GitHub Issues `#433..#438`;
- их тела перенесены из этого плана, а статус по факту завершения выставлен как `Done`;
- каноническая детализация по-прежнему лежит в этом файле и в `TODO.md`.

## RA2-001

### GitHub Issue

`#433`

### Название

`RA2-001 Remote Agent v2: bootstrap immutable paths and server-side layout`

### Что должно быть сделано

- root-only bootstrap:
  - ставит immutable gateway/helper/publisher в `/usr/local`
  - создает `/etc/ai-flow/public`
  - создает `/etc/ai-flow/secrets`
  - создает `/var/lib/ai-flow/diagnostics/<profile>`
  - пишет sudoers fragment
- repo не входит в root trust boundary runtime-контура

### Что уже сделано

- реализован [remote_agent_v2_bootstrap.sh](/private/var/sites/PLANKA/.flow/shared/scripts/remote_agent_v2_bootstrap.sh)
- реализованы шаблоны immutable v2 компонентов
- обновлен [run.sh](/private/var/sites/PLANKA/.flow/shared/scripts/run.sh)
- обновлен runbook

### Текущий статус

`Done`

## RA2-002

### GitHub Issue

`#434`

### Название

`RA2-002 Remote Agent v2: add deterministic diagnostics publisher and snapshot store`

### Что должно быть сделано

- root-owned publisher через `systemd timer`
- sanitized snapshots в `/var/lib/ai-flow/diagnostics/<profile>`
- TTL = `2x interval`
- max snapshot size = `256 KB`
- helper читает только published snapshots

### Что уже сделано

- реализован [remote_agent_v2_publisher.sh](/private/var/sites/PLANKA/.flow/shared/scripts/remote_agent_v2_publisher.sh)
- реализованы [remote_agent_v2_publisher.service](/private/var/sites/PLANKA/.flow/shared/scripts/remote_agent_v2_publisher.service) и [remote_agent_v2_publisher.timer](/private/var/sites/PLANKA/.flow/shared/scripts/remote_agent_v2_publisher.timer)
- реализован atomic snapshot write и bounded snapshot size check

### Что ещё не сделано

- не проверено stale/oversize поведение end-to-end

### Текущий статус

`Done`

## RA2-003

### GitHub Issue

`#435`

### Название

`RA2-003 Remote Agent v2: cut SSH diagnostics over to immutable helper and loopback snapshots`

### Что должно быть сделано

- deterministic `authorized_keys` forced-command
- key-only `aiflow`
- immutable gateway вызывает immutable helper
- probes читают только sanitized snapshots
- shell/arbitrary command/file/docker path запрещены

### Что уже сделано

- реализован [remote_agent_v2_gateway.sh](/private/var/sites/PLANKA/.flow/shared/scripts/remote_agent_v2_gateway.sh)
- реализован [remote_agent_v2_helper.sh](/private/var/sites/PLANKA/.flow/shared/scripts/remote_agent_v2_helper.sh)
- helper работает только с fixed v2 probe names
- helper реализует degraded response для missing/stale/oversize snapshots

### Что ещё не сделано

- перейти от functional smoke к полному negative test suite

### Текущий статус

`Done`

## RA2-004

### GitHub Issue

`#436`

### Название

`RA2-004 Remote Agent v2: move public config and secrets into /etc/ai-flow authority`

### Что должно быть сделано

- `/etc/ai-flow/public/platform.env`
- `/etc/ai-flow/public/projects/<profile>.env`
- `/etc/ai-flow/secrets/platform`
- `/etc/ai-flow/secrets/projects/<profile>`
- diagnostics path не читает secrets

### Что уже сделано

- bootstrap готовит этот layout
- добавлен [ai-flow-server-secrets-layout.md](/private/var/sites/PLANKA/docs/ai-flow-server-secrets-layout.md)
- v2 docs зафиксировали separation model
- `docker_bootstrap.sh` переведён на первичное runtime wiring через `/etc/ai-flow/public/*` и `/etc/ai-flow/secrets/*` с fallback на legacy env authority только для migration/bootstrap
- publisher начал публиковать расширенный `compose_metadata.json` с явным признаком `server_env_authority_wired`

### Что ещё не сделано

- ротация prod secrets ещё не выполнена

### Текущий статус

`Done`

## RA2-005

### GitHub Issue

`#437`

### Название

`RA2-005 Remote Agent v2: remove external diagnostics ingress and keep loopback-only surfaces`

### Что должно быть сделано

- `/health`, `/ops/status`, `/ops/status.json`, `/ops/debug/*` не проксируются наружу
- diagnostics HTTP остаётся только на `127.0.0.1`
- снаружи остаются только non-diagnostic surfaces

### Что уже сделано

- docs и `TODO` переведены на v2 trust model
- docker-hosted runbook больше не считает публичный status/debug каноном
- `RA2-004` дал server-side config authority для runtime
- на VPS внешний diagnostics ingress уже отрезан; снаружи остался только runtime contour без status/debug surfaces

### Что ещё не сделано

- зафиксировать это в финальном cutover report и negative test run

### Текущий статус

`Done`

## RA2-006

### GitHub Issue

`#438`

### Название

`RA2-006 Remote Agent v2: run negative tests, disable legacy access, and document cutover`

### Что должно быть сделано

- negative tests:
  - no shell
  - no arbitrary command
  - no arbitrary file read
  - no docker
  - no secret leakage
  - no oversized output
- cutover на v2
- disable legacy remote-agent v1
- documented rollback/kill switch

### Что уже сделано

- negative scenarios описаны архитектурно и в runbook
- kill switch и rollback path задокументированы для v2
- legacy v1 toolkit entrypoints переведены в disabled mode; новый штатный путь только `remote_agent_v2_bootstrap` + SSH `aiflow`

### Текущий статус

`Done`

## Что реально уже протестировано

Протестировано только локально и статически:

- `bash -n` новых shell-скриптов
- `--help` / usage новых v2 entrypoints
- `git diff --check`
- создание и синхронизация `RA2-001..RA2-006` как GitHub Issues

Не протестировано пока:

- нет дополнительных open items по Remote Agent v2; дальнейшие проверки относятся уже к общему runtime smoke
