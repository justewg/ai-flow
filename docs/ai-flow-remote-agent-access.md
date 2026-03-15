# AI Flow Remote Agent Access v2

## Назначение

Remote Agent v2 даёт внешний read-only diagnostic access без shell-доступа, без `docker`-прав и без чтения secrets/env напрямую.

Каноническая цепочка:

`SSH key -> Match User aiflow -> ForceCommand -> immutable gateway -> immutable helper -> sanitized snapshots`

## Trust Boundary

Root-trusted runtime path вынесен из mutable repo:

- gateway:
  - `/usr/local/sbin/ai-flow-remote-agent-v2-gateway`
- helper:
  - `/usr/local/libexec/ai-flow/remote-agent-v2-helper`
- diagnostics publisher:
  - `/usr/local/libexec/ai-flow/ai-flow-diagnostics-publish`

Repo-скрипты используются только как source для root-only bootstrap и не считаются runtime trust anchor.

## Diagnostics Layer

Remote Agent v2 не читает:

- raw env files;
- raw docker logs;
- raw config excerpts;
- repo-local `.flow/config/flow.env`.

Он читает только:

- sanitized snapshots в:
  - `/var/lib/ai-flow/diagnostics/<profile>/`
- loopback-safe status surfaces, но только через root-owned publisher, а не напрямую из helper.

### Snapshot contract

- publisher interval по умолчанию: `15s`
- snapshot TTL: `2x interval`
- helper читает только последний опубликованный snapshot
- при stale snapshot helper возвращает degraded payload и не делает fallback к runtime
- max snapshot size: `256 KB`

## SSH Model

Используется отдельный user:

- `aiflow`

Ограничения задаются через `sshd_config.d`:

- `Match User aiflow`
- `AuthenticationMethods publickey`
- `PasswordAuthentication no`
- `PermitTTY no`
- `AllowTcpForwarding no`
- `X11Forwarding no`
- `PermitUserRC no`
- `PermitTunnel no`
- `ForceCommand /usr/local/sbin/ai-flow-remote-agent-v2-gateway`

В `authorized_keys` добавляется только operator public key с `restrict`.

## Sudo Model

`aiflow` не должен состоять в `docker` group.

Разрешён только один privileged path:

- `/usr/local/libexec/ai-flow/remote-agent-v2-helper --dispatch *`

Никаких:

- `docker`
- `docker compose`
- `journalctl`
- `systemctl`
- shell wrappers

## Probe Catalog

Текущие v2 probes:

- `runtime_snapshot_v2`
- `ops_health_v2`
- `runtime_log_tail_v2 [--lines N]`
- `compose_contract_metadata_v2`
- `nginx_ingress_metadata_v2`
- `workspace_git_metadata_v2`

Поддерживается только:

- `--profile <profile>`
- `--lines <1..200>` только для `runtime_log_tail_v2`

## Public / Secret Layout

Non-secret config:

- `/etc/ai-flow/public/platform.env`
- `/etc/ai-flow/public/projects/<profile>.env`

Secret authority:

- `/etc/ai-flow/secrets/platform/`
- `/etc/ai-flow/secrets/projects/<profile>/`

Diagnostics path не должен читать secret files и не должен возвращать plaintext values.

## Publisher

Publisher запускается отдельным `systemd` timer:

- `ai-flow-diagnostics-publish@<profile>.service`
- `ai-flow-diagnostics-publish@<profile>.timer`

Publisher:

- root-owned;
- детерминированный;
- пишет snapshots atomically;
- не вызывается helper-ом on-demand.

## HTTP Surfaces

Diagnostics HTTP surfaces должны быть только loopback-only:

- `127.0.0.1`

Через nginx наружу не проксируются:

- `/health`
- `/ops/status`
- `/ops/status.json`
- `/ops/debug/*`

Снаружи должны оставаться только non-diagnostic surfaces, если они нужны runtime contour.

## Установка

Под root:

```bash
cd /var/sites/.ai-flow/workspaces/<profile>
./.flow/shared/scripts/run.sh remote_agent_v2_bootstrap \
  --profile <profile> \
  --workspace-path /var/sites/.ai-flow/workspaces/<profile> \
  --ai-flow-root /var/sites/.ai-flow \
  --password-mode locked
```

Если не передавать `--authorized-key-file`, bootstrap по умолчанию ищет:

- `~<SUDO_USER>/.ssh/aiflow_remote_agent.pub`

## Пример использования

```bash
ssh -i ~/.ssh/aiflow_remote_agent aiflow@host runtime_snapshot_v2 --profile <profile> | jq .
```

```bash
ssh -i ~/.ssh/aiflow_remote_agent aiflow@host runtime_log_tail_v2 --profile <profile> --lines 80 | jq .
```

## Rollback / Kill Switch

Быстрый disable path:

```bash
passwd -l aiflow
rm -f /etc/sudoers.d/ai-flow-remote-agent-v2
rm -f /etc/ssh/sshd_config.d/ai-flow-remote-agent-v2.conf
systemctl daemon-reload
systemctl reload sshd
```

При необходимости дополнительно:

```bash
systemctl disable --now ai-flow-diagnostics-publish@<profile>.timer
rm -f /usr/local/sbin/ai-flow-remote-agent-v2-gateway
rm -f /usr/local/libexec/ai-flow/remote-agent-v2-helper
rm -f /usr/local/libexec/ai-flow/ai-flow-diagnostics-publish
```
