# AI Flow Env Checklist

## Цель

Этот чек-лист нужен, чтобы не смешивать host/platform env и project env.

Для машинной проверки используй:

```bash
.flow/shared/scripts/run.sh env_audit --profile <profile>
```

Для `docker-hosted` и `linux-hosted` семантика должна быть такой:

- platform env:
  - `/var/sites/.ai-flow/config/ai-flow.platform.env`
- project env:
  - `/var/sites/.ai-flow/config/<profile>.flow.env`

Для текущего проекта `planka` это означает:

- platform env:
  - `/var/sites/.ai-flow/config/ai-flow.platform.env`
- project env:
  - `/var/sites/.ai-flow/config/planka.flow.env`

## Platform Env

Platform env содержит только host-level и platform-level настройки.

### Обязательные по смыслу

- `AI_FLOW_ROOT_DIR`
  - пример: `/var/sites/.ai-flow`
- `FLOW_HOST_RUNTIME_MODE`
  - пример: `linux-docker-hosted`

### Обязательные, если используется host-level public contour

- `OPS_BOT_PUBLIC_BASE_URL`
  - пример: `https://aiflow.ewg40.ru`

### Обязательные, если включён debug API

- `OPS_BOT_DEBUG_ENABLED=1`
- `OPS_BOT_DEBUG_BEARER_TOKEN=<long-random-token>`

### Нормальные host-level defaults

- `GH_APP_PM2_APP_NAME=ai-flow-gh-app-auth`
- `OPS_BOT_PM2_APP_NAME=ai-flow-ops-bot`

### Опциональные, но допустимые

- `OPS_BOT_DEBUG_DEFAULT_LINES`
- `OPS_BOT_DEBUG_MAX_LINES`
- `OPS_BOT_DEBUG_MAX_BYTES`

## Project Env

Project env содержит только binding конкретного consumer-project.

### Обязательные

- `PROJECT_PROFILE`
  - пример: `planka`
- `GITHUB_REPO`
  - пример: `justewg/planka`
- `FLOW_BASE_BRANCH`
  - пример: `main`
- `FLOW_HEAD_BRANCH`
  - пример: `development`
- `PROJECT_OWNER`
- `PROJECT_NUMBER`
- `PROJECT_ID`
- `DAEMON_GH_PROJECT_TOKEN`
- `GH_APP_INTERNAL_SECRET`
- `GH_APP_ID`
- `GH_APP_INSTALLATION_ID`
- `GH_APP_PRIVATE_KEY_PATH`
- `AI_FLOW_ROOT_DIR`
  - пример: `/var/sites/.ai-flow`
- `CODEX_STATE_DIR`
  - пример: `/var/sites/.ai-flow/state/planka`
- `FLOW_STATE_DIR`
  - пример: `/var/sites/.ai-flow/state/planka`
- `FLOW_LOGS_DIR`
  - пример: `/var/sites/.ai-flow/logs/planka`
- `FLOW_RUNTIME_LOG_DIR`
  - пример: `/var/sites/.ai-flow/logs/planka/runtime`
- `FLOW_PM2_LOG_DIR`
  - пример: `/var/sites/.ai-flow/logs/planka/pm2`
- `FLOW_HOST_RUNTIME_MODE`
  - пример: `linux-docker-hosted`
- `GH_APP_BIND`
  - обычно `127.0.0.1`
- `GH_APP_PORT`
  - обычно `8787`
- `GH_APP_TOKEN_SKEW_SEC`
  - обычно `300`
- `DAEMON_GH_AUTH_TIMEOUT_SEC`
  - обычно `8`
- `OPS_BOT_BIND`
  - обычно `127.0.0.1`
- `OPS_BOT_PORT`
  - обычно `8790`
- `OPS_BOT_WEBHOOK_PATH`
  - обычно `/telegram/webhook`
- `OPS_BOT_REMOTE_STATE_DIR`
  - канонически: `/var/sites/.ai-flow/state/ops-bot/remote`
- `OPS_BOT_REMOTE_SNAPSHOT_TTL_SEC`
- `OPS_BOT_REMOTE_SUMMARY_TTL_SEC`

### Полный стандартный contract

- `GH_APP_OWNER`
- `GH_APP_REPO`
- `GH_APP_PM2_USE_DEFAULT`
- `OPS_BOT_USE_DEFAULT`
- `OPS_BOT_REFRESH_SEC`
- `OPS_BOT_CMD_TIMEOUT_MS`
- `FLOW_LAUNCHD_NAMESPACE`
- `WATCHDOG_DAEMON_LABEL`
- `WATCHDOG_DAEMON_INTERVAL_SEC`

### Опциональные project-level ключи

- `DAEMON_TG_BOT_TOKEN`
- `DAEMON_TG_CHAT_ID`
- `DAEMON_TG_REMINDER_SEC`
- `DAEMON_TG_GH_DNS_REMINDER_SEC`
- `DAEMON_TG_DIRTY_REMINDER_SEC`
- `DAEMON_GH_TOKEN_FALLBACK_ENABLED`
- `DAEMON_GH_TOKEN`
- `DAEMON_GH_AUTH_TOKEN_URL`
- `EXECUTOR_CODEX_BYPASS_SANDBOX`
- `GH_APP_PM2_USE_DEFAULT`
- `OPS_BOT_USE_DEFAULT`
- `OPS_BOT_TG_BOT_TOKEN`
- `OPS_BOT_WEBHOOK_SECRET`
- `OPS_BOT_TG_SECRET_TOKEN`
- `OPS_BOT_ALLOWED_CHAT_IDS`
- `OPS_BOT_REFRESH_SEC`
- `OPS_BOT_CMD_TIMEOUT_MS`
- `OPS_REMOTE_STATUS_PUSH_*`
- `OPS_REMOTE_SUMMARY_PUSH_*`
- `WATCHDOG_*`

## Что не должно жить в Platform Env

Эти ключи project-specific и им не место в `ai-flow.platform.env`:

- `PROJECT_PROFILE`
- `DAEMON_GH_PROJECT_TOKEN`
- `GH_APP_INTERNAL_SECRET`
- `GH_APP_ID`
- `GH_APP_INSTALLATION_ID`
- `GH_APP_PRIVATE_KEY_PATH`
- `CODEX_STATE_DIR`
- `FLOW_STATE_DIR`
- `FLOW_LOGS_DIR`
- `FLOW_RUNTIME_LOG_DIR`
- `FLOW_PM2_LOG_DIR`
- `OPS_BOT_PORT`
- `OPS_BOT_BIND`
- `OPS_BOT_REMOTE_STATE_DIR`

## Что не должно жить в Project Env

Эти ключи host/platform-specific и их лучше держать в `ai-flow.platform.env`:

- `OPS_BOT_PUBLIC_BASE_URL`
- `OPS_BOT_DEBUG_ENABLED`
- `OPS_BOT_DEBUG_BEARER_TOKEN`
- `OPS_BOT_DEBUG_DEFAULT_LINES`
- `OPS_BOT_DEBUG_MAX_LINES`
- `OPS_BOT_DEBUG_MAX_BYTES`
- `GH_APP_PM2_APP_NAME`
- `OPS_BOT_PM2_APP_NAME`

## Лишнее и legacy, что надо вычищать

Если эти ключи/значения есть в новых env, это признак старой схемы:

- любые пути с `/private/...`
- любые пути с `~/Library/...`
- любые `LaunchAgents` пути
- `OPS_BOT_REMOTE_STATE_DIR=.flow/state/ops-bot/remote`
  - legacy default; для host-root канон теперь `/var/sites/.ai-flow/state/ops-bot/remote`
- platform-level пути вида:
  - `~/.config/planka-automation/openai.env`
  - их надо переводить на `~/.config/ai-flow/openai.env`
- host-level service names вида:
  - `planka-gh-app-auth`
  - `planka-ops-bot`
  - в platform-defaults они должны быть `ai-flow-gh-app-auth` и `ai-flow-ops-bot`

## Быстрая ручная проверка

### Platform env

Проверить, что там нет project binding:

```bash
grep -E '^(PROJECT_PROFILE|DAEMON_GH_PROJECT_TOKEN|GH_APP_ID|GH_APP_INSTALLATION_ID|GH_APP_PRIVATE_KEY_PATH|CODEX_STATE_DIR|FLOW_STATE_DIR|FLOW_LOGS_DIR|FLOW_RUNTIME_LOG_DIR|FLOW_PM2_LOG_DIR)=' /var/sites/.ai-flow/config/ai-flow.platform.env
```

Команда должна вернуть пусто.

### Project env

Проверить, что там нет host-level debug/public ingress defaults:

```bash
grep -E '^(OPS_BOT_PUBLIC_BASE_URL|OPS_BOT_DEBUG_ENABLED|OPS_BOT_DEBUG_BEARER_TOKEN|OPS_BOT_DEBUG_DEFAULT_LINES|OPS_BOT_DEBUG_MAX_LINES|OPS_BOT_DEBUG_MAX_BYTES|GH_APP_PM2_APP_NAME|OPS_BOT_PM2_APP_NAME)=' /var/sites/.ai-flow/config/planka.flow.env
```

В идеале для строгой схемы команда тоже должна вернуть пусто.

### Legacy path check

```bash
grep -E '/private/|~/Library|LaunchAgents|planka-automation' /var/sites/.ai-flow/config/ai-flow.platform.env /var/sites/.ai-flow/config/planka.flow.env
```

Команда должна вернуть пусто.

## Что сейчас считать нормой для `planka`

- `planka` в путях workspace/docker/profile — это нормально:
  - `/var/sites/.ai-flow/workspaces/planka`
  - `/var/sites/.ai-flow/config/planka.flow.env`
  - `/var/sites/.ai-flow/docker/planka`
- `ai-flow` в host-level сущностях — это канон:
  - `/var/sites/.ai-flow/config/ai-flow.platform.env`
  - `https://aiflow.ewg40.ru`
  - `ai-flow-gh-app-auth`
  - `ai-flow-ops-bot`
