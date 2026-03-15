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

`In Progress`, функционально почти завершено

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

- повторный bootstrap после SSH reload fix
- подтверждение, что `Match User + ForceCommand` реально применился

## RA2-002

### Статус

`In Progress`, базовая функциональность подтверждена

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

- проверить stale/oversize negative paths

## RA2-003

### Статус

`Blocked`

### Что произошло

- `ssh -i ~/.ssh/aiflow_remote_agent aiflow@127.0.0.1 runtime_snapshot_v2 --profile planka`
  вернул:
  - `bash: runtime_snapshot_v2: command not found`
- `ssh ... 'id'` выполнился как обычный shell login

### Диагноз

- `sshd_config.d` fragment был установлен, но bootstrap не делал reload SSH daemon
- из-за этого `Match User + ForceCommand` не применился

### Исправление в коде

- bootstrap теперь:
  - делает reload `ssh`/`sshd`
  - проверяет effective policy через `sshd -T -C ...`

### Следующий шаг

- обновить toolkit на VPS
- повторно запустить `remote_agent_v2_bootstrap`
- снова проверить `ssh aiflow@127.0.0.1 ...`

## RA2-004

### Статус

`Planned`

### Уже сделано

- bootstrap создаёт:
  - `/etc/ai-flow/public/platform.env`
  - `/etc/ai-flow/public/projects/<profile>.env`
  - `/etc/ai-flow/secrets/platform`
  - `/etc/ai-flow/secrets/projects/<profile>`

### Ещё не сделано

- runtime на VPS ещё не переведён полностью на чтение server-side secret authority
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
