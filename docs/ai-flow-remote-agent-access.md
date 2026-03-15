# AI Flow Remote Agent Access

## Зачем это нужно

Публичный debug surface (`/health`, `/ops/status.json`, `/ops/debug/*`) закрывает большую часть диагностики, но не всё.

Для некоторых разборов всё ещё нужны host-local данные:

- docker/compose contract и env wiring;
- nginx config presence;
- git/symlink drift внутри authoritative workspace;
- короткие runtime log tails;
- локальный state/layout, который не должен становиться публичным API.

Для этого вводится optional remote-agent access contour:

- отдельный Linux user, по умолчанию `aiflow`;
- только SSH по ключу;
- forced-command gateway;
- sudo allowlist только на read-only probe path;
- без membership в `docker` group;
- audit log всех accepted/denied команд;
- без shell и без произвольных путей.

## Что это не должно делать

Это не:

- shell-доступ к хосту;
- generic file reader;
- generic command runner;
- постоянный operator/root backdoor.

Доступ должен ограничиваться только каноническим `remote_probe` kit.

## Компоненты

### 1. Отдельный user

- Linux user: `aiflow`
- рекомендуется: key-only SSH
- пароль по умолчанию `locked`
- опциональный break-glass пароль можно задать только явно (`--password-mode interactive`)

### 2. Forced-command gateway

Устанавливается host-level wrapper:

- `${AI_FLOW_ROOT_DIR}/bin/ai-flow-remote-agent-gateway`

Это не отдельный TCP-порт и не отдельный сетевой daemon.

Это обычный SSH forced-command wrapper:

- ключ лежит в `~aiflow/.ssh/authorized_keys`;
- у записи ключа есть префикс `command="...ai-flow-remote-agent-gateway --forced-command ..."`;
- при `ssh aiflow@host <probe-subcommand>` OpenSSH не даёт shell, а запускает именно gateway;
- gateway валидирует allowlisted probe subcommand и передаёт его дальше в `remote_probe`.

Он:

- читает `SSH_ORIGINAL_COMMAND`;
- принимает только allowlisted probe subcommands;
- пишет audit line;
- ре-энтрится через `sudo -n ... --sudo-probe ...`;
- дальше запускает repo-local:
  - `/.flow/shared/scripts/run.sh remote_probe ...`

### 3. Sudoers allowlist

Устанавливается snippet:

- `/etc/sudoers.d/ai-flow-remote-agent`

Смысл:

- `aiflow` может выполнить только:
  - `${AI_FLOW_ROOT_DIR}/bin/ai-flow-remote-agent-gateway --sudo-probe *`
- interactive `sudo` shell не выдаётся
- `aiflow` не должен состоять в `docker` group, потому что это почти эквивалент root-доступа

### 4. Audit log

Записывается в:

- `${AI_FLOW_ROOT_DIR}/logs/remote-agent/access.log`

Формат line-based:

- UTC timestamp
- accepted / denied
- Linux user
- `SSH_CONNECTION`
- нормализованный `SSH_ORIGINAL_COMMAND`

## Какие команды разрешены

Только fixed allowlist из `remote_probe`:

- `semantically_overqualified_runtime_snapshot_env_audit_bundle_v1`
- `semantically_overqualified_runtime_log_tail_bundle_v1 [--lines N]`
- `semantically_overqualified_docker_compose_contract_surface_v1`
- `semantically_overqualified_ops_bot_debug_gate_surface_v1`
- `semantically_overqualified_nginx_ingress_surface_v1`
- `semantically_overqualified_workspace_git_surface_v1`

Никаких произвольных путей и произвольных shell-команд.

## Установка

Под root:

```bash
cd /var/sites/.ai-flow/workspaces/planka
./.flow/shared/scripts/run.sh remote_agent_access_bootstrap \
  --runtime-user <runtime-user> \
  --agent-user aiflow \
  --ai-flow-root /var/sites/.ai-flow \
  --workspace-path /var/sites/.ai-flow/workspaces/planka \
  --password-mode locked
```

Если не передавать `--authorized-key-file`, bootstrap по умолчанию попробует взять публичный ключ оператора, который запускал `sudo`, из:

- `~<SUDO_USER>/.ssh/aiflow_remote_agent.pub`

Что делает bootstrap:

- создаёт user `aiflow`, если его нет;
- если на хосте есть `docker` group, убирает `aiflow` из неё;
- ставит `passwd -l aiflow`, если не выбран interactive password mode;
- устанавливает gateway в `${AI_FLOW_ROOT_DIR}/bin/`;
- создаёт audit log path;
- пишет sudoers allowlist;
- при наличии `--authorized-key-file` добавляет key в `~aiflow/.ssh/authorized_keys` как forced-command entry.

## Пример использования

После установки:

```bash
ssh aiflow@host semantically_overqualified_runtime_snapshot_env_audit_bundle_v1 | jq .
```

Или:

```bash
ssh aiflow@host semantically_overqualified_runtime_log_tail_bundle_v1 --lines 120 | jq .
```

## Rollback / Disable

Самый короткий disable path:

```bash
passwd -l aiflow
rm -f /etc/sudoers.d/ai-flow-remote-agent
```

Опционально потом:

```bash
rm -f /var/sites/.ai-flow/bin/ai-flow-remote-agent-gateway
```

И убрать managed key из:

- `~aiflow/.ssh/authorized_keys`

## Рекомендации по безопасности

- использовать только отдельный user;
- не давать этому user обычный shell-workflow;
- не добавлять этого user в `docker` group;
- не публиковать generic file-read endpoints;
- не смешивать probe tier и recovery tier;
- recovery actions (`docker compose up`, `nginx reload`, `systemctl`, etc.) держать отдельным контуром и не включать в этот gateway;
- хранить break-glass доступ отдельно у оператора (`<runtime-user>`/root), а не как постоянный повседневный password-login `aiflow`.

## Связь с bootstrap и docker-hosted deployment

Это optional feature.

Она не заменяет:

- интерактивную работу прямо на VPS;
- публичный debug API;
- обычный bootstrap `host_bootstrap` / `docker_bootstrap`.

Но в общей схеме self-hosted ai-flow это важный слой:

- remote monitoring / diagnosis со стороны внешнего AI-agent;
- без расширения публичного surface до опасного “read any file / run any command”.
