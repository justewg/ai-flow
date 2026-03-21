# PL-052 Аудит Linux-host auth/ops runtime contour

Дата проверки: 2026-03-21

## Что проверялось

По задаче PL-052 нужно было подтвердить, что `gh_app_auth` и `ops_bot` уже оформлены как поддержанный Linux-host runtime contour:

- есть канонический run/install/status path для auth-service и ops-bot на VPS;
- есть restart-safe поведение после падения процесса и после reboot;
- не сломаны `/ops/status`, Telegram webhook и remote snapshot ingest;
- эксплуатационные ожидания для Linux-host зафиксированы в документации и tooling.

## Что подтверждено по коду и скриптам

### 1. `gh_app_auth` уже живёт как отдельный Linux-host runtime-компонент

Подтверждено в `.flow/shared/scripts/gh_app_auth_pm2_start.sh`, `.flow/shared/scripts/gh_app_auth_pm2_status.sh`, `.flow/shared/scripts/gh_app_auth_pm2_health.sh` и `.flow/shared/scripts/gh_app_auth_pm2_ecosystem.config.cjs`:

- штатный lifecycle идёт через PM2 (`start/restart/status/health/stop`);
- после старта выполняется `pm2 save --force`, то есть runtime contour готов к PM2 resurrect path;
- в ecosystem включены `autorestart: true`, `max_restarts`, `restart_delay`, `min_uptime`;
- health-check идёт через loopback `GET /health`;
- daemon/watchdog продолжают получать токен через локальный auth endpoint (`gh_app_auth_token.sh` и `GET /token`).

### 2. `ops_bot` уже живёт как отдельный Linux-host runtime-компонент

Подтверждено в `.flow/shared/scripts/ops_bot_pm2_start.sh`, `.flow/shared/scripts/ops_bot_pm2_status.sh`, `.flow/shared/scripts/ops_bot_pm2_health.sh` и `.flow/shared/scripts/ops_bot_pm2_ecosystem.config.cjs`:

- есть тот же PM2 lifecycle с `pm2 save --force`;
- включён auto-restart через PM2;
- health-check идёт через loopback `GET /health`;
- public contour отделён от local contour и предполагает nginx/HTTPS ingress поверх loopback bind.

### 3. Сохранены `/ops/status`, Telegram webhook и remote ingest

Подтверждено по `.flow/shared/scripts/ops_bot_service.js`, `.flow/shared/scripts/ops_remote_status_push.sh`, `.flow/shared/scripts/ops_remote_summary_push.sh`, `.flow/shared/scripts/ops_bot_webhook_register.sh` и `.flow/shared/docs/ops-bot-dashboard.md`:

- живы endpoint-ы `/ops/status`, `/ops/status.json`, `/health`, `/telegram/webhook`;
- сохранены ingress endpoint-ы `POST /ops/ingest/status` и `POST /ops/ingest/log-summary`;
- remote ingest хранится раздельно по `source/profile/repo`, то есть не ломает multi-project split-runtime;
- webhook registration/refresh оформлены отдельными штатными командами;
- `/summary` и remote summary bundle продолжают работать через ingest path.

### 4. Linux-host contour встроен в общий runtime toolkit

Подтверждено по `.flow/shared/scripts/profile_init.sh`, `.flow/shared/scripts/linux_host_codex_preflight.sh`, `.flow/shared/scripts/daemon_install.sh`, `.flow/shared/scripts/watchdog_install.sh`:

- `profile_init` уже знает host-level layout `.flow/systemd -> <AI_FLOW_ROOT_DIR>/systemd/<profile>`;
- `profile_init` шаблонизирует env для `GH_APP_*`, `OPS_BOT_*`, remote push и host-level state/log roots;
- Linux preflight знает `FLOW_HOST_RUNTIME_MODE=linux-hosted|linux-docker-hosted`, `CODEX_HOME`, `OPENAI_ENV_FILE`, VPN wrapper;
- daemon/watchdog уже умеют устанавливаться как `systemd` services, так что auth/ops contour живёт рядом с поддержанным Linux service-layer.

## Что подтверждено тестами и локальной верификацией

Запущены и успешно прошли:

1. `node --test .flow/shared/scripts/gh_app_auth_service.test.js`
   - результат: `2/2` pass.
2. `node --test .flow/shared/scripts/ops_bot_service.test.js`
   - результат: `9/9` pass.
   - покрыты webhook guards, ingest/status fallback, summary ingest, multi-source remote runtime, debug endpoints.
3. `bash -n` для runtime-скриптов:
   - `gh_app_auth_pm2_*`
   - `ops_bot_pm2_*`
   - `ops_remote_status_push.sh`
   - `ops_remote_summary_push.sh`
   - `ops_bot_webhook_register.sh`
   - `profile_init.sh`
   - `daemon_install.sh`
   - `watchdog_install.sh`
   - `linux_host_codex_preflight.sh`
   - результат: синтаксических ошибок нет.
4. Dry-run `profile_init install` с `FLOW_SERVICE_MANAGER=systemd`
   - результат: подтверждено, что Linux-host path строит host-level state/log layout и использует `.flow/systemd` как canonical service dir.

## Что подтверждено live-проверками в текущем Linux workspace

Дополнительно в этом шаге перепроверен живой contour из текущего workspace `/var/sites/.ai-flow/workspaces/planka`.

### 1. Auth-service реально отвечает и выдаёт installation token

Проверка:

- `env DAEMON_GH_ENV_FILE=/var/sites/.ai-flow/workspaces/planka/.flow/config/flow.env CODEX_STATE_DIR=/var/sites/.ai-flow/workspaces/planka/.flow/state FLOW_STATE_DIR=/var/sites/.ai-flow/workspaces/planka/.flow/state .flow/shared/scripts/run.sh gh_app_auth_probe`

Результат:

- `HEALTH_OK`
- `TOKEN_OK source=cache ...`

Это подтверждает, что daemon/watchdog в текущем контуре действительно могут получить токен через локальный auth endpoint.

### 2. Ops-bot loopback health жив

Проверка:

- `... .flow/shared/scripts/run.sh ops_bot_health`

Результат:

- `{"status":"ok","service":"ops-bot",...,"telegram_enabled":true,"ingest_enabled":false,...}`

Это подтверждает живой `/health` и Telegram-ready contour, но одновременно показывает, что ingest endpoint на текущем loopback-сервисе выключен.

### 3. Telegram webhook зарегистрирован, но есть live-сигнал о сетевой деградации

Проверка:

- `... .flow/shared/scripts/run.sh ops_bot_webhook_register info`

Результат:

- `WEBHOOK_INFO_OK=1`
- Telegram возвращает `last_error_message: "Connection timed out"` для зарегистрированного webhook URL.

То есть registration path жив, но end-to-end delivery нельзя считать полностью зелёной.

### 4. Remote snapshot ingest в текущем окружении не подтверждён

Проверки:

- `... .flow/shared/scripts/run.sh ops_remote_status_push`
- `... .flow/shared/scripts/run.sh ops_remote_summary_push`

Результат:

- `ops_remote_status_push` завершился с `OPS_REMOTE_PUSH_OK=0`, `HTTP_STATUS=404`, `{"error":"NOT_FOUND","message":"endpoint not found"}`;
- `ops_remote_summary_push` вернул `OPS_REMOTE_SUMMARY_PUSH_SKIPPED=DISABLED`.

Это означает, что acceptance-пункт про сохранение remote snapshot ingest в текущем live contour подтверждён по коду и тестам, но не подтверждён по фактическому runtime-состоянию.

### 5. Aggregated smoke ops-bot сейчас не зелёный

Проверка:

- `... .flow/shared/scripts/run.sh ops_bot_post_smoke_check`

Результат:

- `POST_SMOKE_RESULT=incidents`
- инциденты:
  - отсутствует `pm2` в текущем окружении;
  - public status page недоступна (`/ops/status(.json)` отдаёт `404`);
  - нет manual rollout comment file.

Дополнительное наблюдение:

- Telegram webhook сейчас зарегистрирован на `https://planka-dev.ewg40.ru/...`, а aggregated smoke проверяет public status surface на `https://aiflow.ewg40.ru/ops/status(.json)` и получает `404`.

Это выглядит как невыровненный public ingress / host placement contract для ops contour.

### 6. Preflight и direct host-status дают расходящиеся сигналы

Проверки:

- `... .flow/shared/scripts/run.sh profile_init preflight --profile planka`
- `... .flow/shared/scripts/run.sh daemon_status com.flow.codex-daemon.planka`
- `... .flow/shared/scripts/run.sh watchdog_status com.flow.codex-watchdog.planka`

Результат:

- `profile_init preflight` увидел `FLOW_HOST_RUNTIME_MODE=linux-docker-hosted`, `DAEMON_STATUS=RUNNING`, `WATCHDOG_STATUS=RUNNING`, но завершился с `PREFLIGHT_READY=0` из-за `CHECK_FAIL OPENAI_ENV_FILE=unresolved`;
- прямой `daemon_status` на этом хосте вернул `INSTALLED_NOT_LOADED` и `systemctl: command not found`;
- прямой `watchdog_status` вернул `NOT_INSTALLED`.

Это выглядит как ожидаемое расхождение между docker-hosted snapshot-based preflight и host-native `systemd`-проверкой, но для эксплуатационного runbook оно всё ещё остаётся источником путаницы.

## Что не удалось подтвердить в этом шаге

### 1. Полный reboot smoke на реальном VPS

В этой дельте не перепроверялся живой сценарий:

- VPS reboot;
- автоподъём PM2 после reboot через `pm2 resurrect`/startup;
- последующее успешное получение токена daemon/watchdog из уже поднятого auth-service;
- живой ответ webhook/status surface после reboot.

Причина: текущий workspace не даёт прямого доступа к реальному VPS runtime и не содержит сам факт reboot-smoke как локально воспроизводимый тест.

### 2. Полностью зелёный live Telegram/webhook/public-status smoke

Не переподтверждались:

- успешная доставка webhook без `last_error_message` в Telegram;
- публичный ответ `/ops/status` и `/ops/status.json` без `404`;
- ответ живым `/status` и `/summary` из Telegram-чата.

Часть live-проверок была запущена, но зелёного результата для публичного webhook/status contour в этом шаге не получено.

### 3. Документация ещё не полностью выровнена под Linux-host

Главный зазор найден в `.flow/shared/docs/flow-onboarding-quickstart.md` и `.flow/shared/docs/flow-onboarding-checklist.md`:

- quickstart всё ещё содержит старую формулировку, что service-layer “рассчитан на launchd”, а Linux — это временный/manual fallback;
- checklist и quickstart в основном описывают macOS-first path и не дают такого же явного канонического install/runbook для Linux-host auth/ops contour.

Это означает, что по коду и tooling PL-052 в основном реализована, но documentation acceptance закрыта не полностью.

### 4. PM2/reboot-safe lifecycle не подтверждён в текущем хостовом окружении

В коде есть всё необходимое для restart-safe path:

- `pm2 save --force`;
- `autorestart` в ecosystem;
- crash-test для auth-service.

Но в текущем окружении команда `pm2` отсутствует, поэтому именно здесь не удалось переподтвердить:

- `gh_app_auth_pm2_status`;
- `ops_bot_pm2_status`;
- crash/restart path через PM2;
- автоподъём после reboot.

## Итог

По состоянию репозитория PL-052 реализована по runtime-слою существенно больше, чем отражено в roadmap-статусе:

- `gh_app_auth` и `ops_bot` уже оформлены как отдельные Linux-host процессы с PM2 lifecycle и health-check;
- `/ops/status`, Telegram webhook и remote snapshot/summary ingest сохранены;
- Linux-host contour уже встроен в `profile_init` и соседний systemd-based runtime.

Но полностью закрытой задачу в текущей дельте считать рано по двум причинам:

1. не переподтверждён live reboot recovery auth/ops на реальном VPS;
2. текущие live-проверки показали operational gaps: `PREFLIGHT_READY=0`, `ops_remote_status_push=404`, `ops_bot_post_smoke_check=incidents`, direct host-status не совпадает со snapshot-based preflight;
3. onboarding quickstart/checklist в `.flow/shared` всё ещё частично описывают Linux как неканонический path.

Именно поэтому в `TODO.md` статус PL-052 переведён в `In Progress`, а не в `Done`.
