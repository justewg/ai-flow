# Remote Agent v2 Progress Report

## Назначение

Этот файл фиксирует фактический прогресс по `RA2-*` и служит каноническим подтверждением готовности после переноса `RA2-001..RA2-006` в отдельные GitHub Issues `#433..#438`.

Формат:

- что уже подтверждено;
- что сломалось;
- чем это подтверждено;
- какой следующий шаг.

## RA2-001

### Статус

`Done`

### GitHub Issue

`#433`

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
- secret authority переведена на финальный delivery contract:
  - root-owned
  - `0750` dirs / `0640` files для docker-hosted runtime group
  - без прямого read-path для `aiflow`

### Остаток

- open items по `RA2-001` отсутствуют

## RA2-002

### Статус

`Done`

### GitHub Issue

`#434`

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

`Done`

### GitHub Issue

`#435`

### Подтверждено

- `ssh -i ~/.ssh/aiflow_remote_agent aiflow@127.0.0.1 runtime_snapshot_v2 --profile planka | jq .`
  возвращает рабочий sanitized snapshot
- `ssh -i ~/.ssh/aiflow_remote_agent aiflow@127.0.0.1 runtime_log_tail_v2 --profile planka --lines 20 | jq .`
  возвращает bounded sanitized log tail
- `ssh -i ~/.ssh/aiflow_remote_agent aiflow@127.0.0.1 'id'`
  возвращает `Command denied`

### Финальная модель

- enforcement идёт через managed запись в `~aiflow/.ssh/authorized_keys`:
  - `command="/usr/local/sbin/ai-flow-remote-agent-v2-gateway",restrict ...`
- `sshd_config.d` policy-layer исключён из канонической модели как brittle/non-deterministic слой

## RA2-004

### Статус

`Done`

### GitHub Issue

`#436`

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

- rotation playbook ещё не исполнен

### Подтверждено на VPS

- `PROJECT_PUBLIC_ENV_FILE=/etc/ai-flow/public/projects/planka.env`
- `PLATFORM_PUBLIC_ENV_FILE=/etc/ai-flow/public/platform.env`
- `PROJECT_SECRETS_ENV_FILE=/etc/ai-flow/secrets/projects/planka/runtime.env`
- `PLATFORM_SECRETS_ENV_FILE=/etc/ai-flow/secrets/platform/runtime.env`
- `OPENAI_ENV_FILE=/etc/ai-flow/secrets/platform/openai.env`
- `/etc/ai-flow/secrets/*` переведены на docker-hosted delivery contract:
  - dirs `0750`
  - files `0640`
  - group = runtime delivery group
- `compose_metadata.json` показывает:
  - `server_env_authority_wired=true`
  - `legacy_runtime_env_fallback=false`
  - `whole_home_mount_present=false`

## RA2-005

### Статус

`Done`

### GitHub Issue

`#437`

### Подтверждено

- ранний `ingress_metadata.json` ещё показывал старое состояние до nginx-cutover; фактическая проверка после reload подтверждает наружный `404`
- внешний diagnostics ingress на `aiflow.ewg40.ru` уже отрезан:
  - `https://aiflow.ewg40.ru/health` -> `404`
  - `https://aiflow.ewg40.ru/ops/status.json` -> `404`
  - `https://aiflow.ewg40.ru/ops/debug/runtime.json` -> `404`
- loopback surfaces продолжают работать:
  - `http://127.0.0.1:8790/health` -> `200`
  - `http://127.0.0.1:8790/ops/debug/runtime.json` доступен только по bearer token

## RA2-006

### Статус

`Done`

### GitHub Issue

`#438`

### Уже есть

- negative scenarios определены архитектурно и в runbook
- legacy v1 toolkit entrypoints переведены в disabled mode:
  - `run.sh remote_agent_access_bootstrap`
  - `run.sh remote_probe`
  - direct `remote_agent_access_bootstrap.sh`
  - direct `remote_probe.sh`
  - direct `remote_agent_gateway.sh`
- server-side legacy v1 artifacts удалены:
  - `/var/sites/.ai-flow/bin/ai-flow-remote-agent-gateway`
  - `/etc/sudoers.d/ai-flow-remote-agent`

### Подтверждено на VPS

- `ssh -i ~/.ssh/aiflow_remote_agent aiflow@127.0.0.1 'id'`
  - `Command denied`
- `ssh -i ~/.ssh/aiflow_remote_agent aiflow@127.0.0.1 runtime_snapshot_v2 --profile planka | jq '.snapshot_stale,.profile'`
  - `false`
  - `"planka"`
- `ssh -i ~/.ssh/aiflow_remote_agent aiflow@127.0.0.1 runtime_log_tail_v2 --profile planka --lines 999`
  - `Invalid lines`
- `ssh -i ~/.ssh/aiflow_remote_agent aiflow@127.0.0.1 not_a_real_probe`
  - `Command denied`
- `sudo -u aiflow docker ps`
  - permission denied to Docker socket
- `sudo -u aiflow cat /etc/ai-flow/secrets/platform/runtime.env`
  - `Permission denied`

### Ещё нет

- отдельных open items по v2 cutover больше нет
