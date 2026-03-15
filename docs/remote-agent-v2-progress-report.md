# Remote Agent v2 Progress Report

## Назначение

Этот файл фиксирует фактический прогресс по `RA2-*`, пока GitHub Project board недоступен для нормального update из-за GraphQL rate limit.

Формат:

- что уже подтверждено;
- что сломалось;
- чем это подтверждено;
- какой следующий шаг.

## RA2-001

### Статус

`Done`

### Подтверждено

- созданы:
  - `/etc/ai-flow`
  - `/etc/ai-flow/public`
  - `/etc/ai-flow/secrets`
  - `/var/lib/ai-flow/diagnostics/planka`
- установлены immutable binaries:
  - `/usr/local/sbin/ai-flow-remote-agent-v2-gateway`
  - `/usr/local/libexec/ai-flow/remote-agent-v2-helper`
- создан `~aiflow/.ssh/authorized_keys`
- поднят `ai-flow-diagnostics-publish@planka.timer`

### Исправленные дефекты

- bootstrap host parsing bug в `OPS_BOT_PUBLIC_BASE_URL`
- mode для `/etc/ai-flow/secrets` ужесточён до `0700`

### Остаток

- отдельный caveat по `sshd` policy-layer вынесен в `RA2-003`

## RA2-002

### Статус

`Done`

### Подтверждено

- publisher пишет snapshots в `/var/lib/ai-flow/diagnostics/planka`
- размеры snapshot-файлов находятся сильно ниже `256 KB`
- `runtime_snapshot.json` и metadata snapshots создаются регулярно
- `systemd` publisher service завершает запуск с `status=0/SUCCESS`
- `runtime_snapshot_v2` и `runtime_log_tail_v2` работают при прямом вызове helper

### Подтверждено данными

- `runtime_snapshot.json` содержит:
  - `publisher_interval_sec=15`
  - `snapshot_ttl_sec=30`
  - `snapshot_stale=false`
- `compose_metadata.json` содержит:
  - `platform_env_wired=true`
  - `whole_home_mount_present=false`

### Остаток

- stale/oversize negative paths переходят в `RA2-006`

## RA2-003

### Статус

`In Progress`, функционально работает с caveat

### Подтверждено

- `ssh -i ~/.ssh/aiflow_remote_agent aiflow@127.0.0.1 runtime_snapshot_v2 --profile planka | jq .`
  возвращает рабочий sanitized snapshot
- `ssh -i ~/.ssh/aiflow_remote_agent aiflow@127.0.0.1 runtime_log_tail_v2 --profile planka --lines 20 | jq .`
  возвращает bounded sanitized log tail
- `ssh -i ~/.ssh/aiflow_remote_agent aiflow@127.0.0.1 'id'`
  возвращает `Command denied`

### Что пришлось сделать

- `sshd_config.d` policy-layer остался ineffective на живом хосте:
  - `SSHD_POLICY_EFFECTIVE=0`
  - `sshd -T -C ...` не показывает ожидаемый `ForceCommand`
- поэтому enforcement сейчас идёт через managed запись в `~aiflow/.ssh/authorized_keys`:
  - `command="/usr/local/sbin/ai-flow-remote-agent-v2-gateway",restrict ...`

### Остаток

- понять, можно ли дожать effective `Match User + ForceCommand` на данном distro/config layout
- до этого считать policy-layer caveat задокументированным, но не блокирующим v2 probe path

## RA2-004

### Статус

`In Progress`

### Уже сделано

- bootstrap создаёт:
  - `/etc/ai-flow/public/platform.env`
  - `/etc/ai-flow/public/projects/<profile>.env`
  - `/etc/ai-flow/secrets/platform`
  - `/etc/ai-flow/secrets/projects/<profile>`
- `docker_bootstrap` переведён на первичное wiring runtime через:
  - `/etc/ai-flow/public/platform.env`
  - `/etc/ai-flow/public/projects/<profile>.env`
  - `/etc/ai-flow/secrets/platform/runtime.env`
  - `/etc/ai-flow/secrets/projects/<profile>/runtime.env`
  - `/etc/ai-flow/secrets/platform/openai.env`
  с fallback на legacy `/var/sites/.ai-flow/config/*.env` только для migration/bootstrap
- publisher `compose_metadata.json` теперь должен явно показывать:
  - какие env authority paths реально подключены
  - `server_env_authority_wired=true|false`
  - `legacy_runtime_env_fallback=true|false`

### Ещё не сделано

- новый compose/env wiring ещё не прогнан на VPS через rerender
- rotation playbook ещё не исполнен

## RA2-005

### Статус

`Planned`

### Подтверждено как открытый риск

- `ingress_metadata.json` показывает:
  - `diagnostics_exposed_externally=true`
  - `ops_debug=true`

### Следствие

- внешний diagnostics ingress ещё не закрыт
- `loopback-only` модель пока не доведена

## RA2-006

### Статус

`Planned`

### Уже есть

- negative scenarios определены архитектурно и в runbook

### Ещё нет

- реального VPS negative test run
- cutover report
- disable legacy v1 contour
