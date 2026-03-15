# Ops Bot + Status Dashboard

## Что это
Локальный сервис `.flow/shared/scripts/ops_bot_service.js`, который дает:
- health endpoint: `GET /health`
- web dashboard: `GET /ops/status`
- JSON snapshot: `GET /ops/status.json`
- debug snapshot: `GET /ops/debug/runtime.json`
- debug log-summary: `GET /ops/debug/log-summary.json?hours=6`
- debug log tails: `GET /ops/debug/logs/<daemon|watchdog|executor|graphql-rate>?lines=120`
- Telegram webhook: `POST /telegram/webhook[/<secret>]`
- runtime ingest endpoint: `POST /ops/ingest/status` (опционально, для split-runtime)
- summary ingest endpoint: `POST /ops/ingest/log-summary` (опционально, для split-runtime `/summary`)
- команды в чате: `/status`, `/summary [hours]`, `/help`, `/status_page`

`/status` в Telegram теперь возвращает не один snapshot, а сводку по всем известным проектам/рантаймам на этом контуре автоматики. Каждый проект выводится отдельным блоком `<blockquote><code>...</code></blockquote>`.

Источник данных статуса: `.flow/shared/scripts/status_snapshot.sh` (только локальные файлы `.flow/state/codex/*`, без обязательного вызова GitHub API).

Важно: у ops-bot есть два разных контура, и они могут использоваться одновременно.
- Local contour: сам процесс `ops_bot_service.js` на текущем хосте (`OPS_BOT_BIND/OPS_BOT_PORT`, PM2, локальный health/status).
- Public/remote contour: внешний status/webhook server с HTTPS ingress + Telegram webhook + optional ingest endpoints (`OPS_BOT_PUBLIC_BASE_URL`, nginx, `OPS_REMOTE_*` push с другого runtime).

В split-runtime модели daemon/watchdog могут работать на локальном Mac, а публичный Telegram/webhook/status-page жить на сервере. Тогда используются оба контура одновременно: локальный runtime формирует snapshot/summary, а серверный public ops-bot принимает их через ingest и отвечает в Telegram/webhook.

Важно для multi-project режима: remote ingest теперь хранится раздельно по `source/profile/repo` в `.flow/state/ops-bot/remote/<source>/...`, поэтому `planka`, `favs` и следующие consumer-project не перетирают друг друга. `/ops/status` и `/ops/status.json` показывают не только effective snapshot, но и список всех известных remote sources.

## Локальный запуск
```bash
.flow/shared/scripts/run.sh status_snapshot
.flow/shared/scripts/run.sh ops_bot_start
.flow/shared/scripts/run.sh ops_bot_health
```

PM2:
```bash
.flow/shared/scripts/run.sh ops_bot_pm2_start
.flow/shared/scripts/run.sh ops_bot_pm2_health
.flow/shared/scripts/run.sh ops_bot_pm2_status
.flow/shared/scripts/run.sh ops_bot_pm2_restart
.flow/shared/scripts/run.sh ops_bot_pm2_stop
```

## Рекомендуемые env
```bash
OPS_BOT_BIND=127.0.0.1
OPS_BOT_PORT=8790
OPS_BOT_WEBHOOK_PATH=/telegram/webhook
OPS_BOT_WEBHOOK_SECRET=<long-random-path-secret>
OPS_BOT_TG_SECRET_TOKEN=<long-random-header-secret>
OPS_BOT_ALLOWED_CHAT_IDS=<your_chat_id>
OPS_BOT_PUBLIC_BASE_URL=https://ops.example.com  # public status/webhook server URL
OPS_BOT_DEBUG_ENABLED=1
OPS_BOT_DEBUG_BEARER_TOKEN=<long-random-bearer-token>
# TG_BOT_TOKEN=... (или OPS_BOT_TG_BOT_TOKEN)
```

### Debug surface для удалённой диагностики

Если automation уже живёт на VPS и ты хочешь читать её state/tails из внешнего чата без SSH, можно включить read-only debug API:

```bash
OPS_BOT_DEBUG_ENABLED=1
OPS_BOT_DEBUG_BEARER_TOKEN=<long-random-bearer-token>
OPS_BOT_DEBUG_DEFAULT_LINES=120
OPS_BOT_DEBUG_MAX_LINES=400
OPS_BOT_DEBUG_MAX_BYTES=262144
```

Тогда появляются дополнительные routes:

- `GET /ops/debug/runtime.json`
  - расширенный runtime payload: текущий effective `status_snapshot`, root paths и список доступных логов.
- `GET /ops/debug/log-summary.json?hours=6`
  - JSON-обёртка над `log_summary`, удобна для remote analysis.
- `GET /ops/debug/logs/<name>?lines=<n>`
  - allowlist только для:
    - `daemon`
    - `watchdog`
    - `executor`
    - `graphql-rate`
  - ответ возвращается в JSON с `text`, `lines_returned`, `truncated`, `path`.
  - содержимое проходит через базовое redaction правил для известных secret/token значений.

Пример запроса:

```bash
curl -fsS \
  -H "Authorization: Bearer ${OPS_BOT_DEBUG_BEARER_TOKEN}" \
  http://127.0.0.1:8790/ops/debug/runtime.json | jq .
```

### Split runtime (локальная автоматика + удаленный HTTPS бот)
Если daemon/watchdog работают на локальном Mac, а ops-bot/webhook на сервере:

На сервере (ops-bot):
```bash
OPS_BOT_INGEST_ENABLED=1
OPS_BOT_INGEST_PATH=/ops/ingest/status
OPS_BOT_INGEST_SECRET=<shared-secret>
OPS_BOT_SUMMARY_INGEST_PATH=/ops/ingest/log-summary
OPS_BOT_SUMMARY_INGEST_SECRET=<shared-secret>
OPS_BOT_REMOTE_STATE_DIR=.flow/state/ops-bot/remote
OPS_BOT_REMOTE_SNAPSHOT_TTL_SEC=600
OPS_BOT_REMOTE_SUMMARY_TTL_SEC=1200
```

На локальном рантайме (daemon-loop):
```bash
OPS_REMOTE_STATUS_PUSH_ENABLED=1
OPS_REMOTE_STATUS_PUSH_URL=https://ops-runtime.example.com/ops/ingest/status
OPS_REMOTE_STATUS_PUSH_SECRET=<shared-secret>
OPS_REMOTE_STATUS_SOURCE=planka
OPS_REMOTE_SUMMARY_PUSH_ENABLED=1
OPS_REMOTE_SUMMARY_PUSH_URL=https://ops-runtime.example.com/ops/ingest/log-summary
OPS_REMOTE_SUMMARY_PUSH_SECRET=<shared-secret>
OPS_REMOTE_SUMMARY_PUSH_HOURS=1,6,24
OPS_REMOTE_SUMMARY_PUSH_MIN_INTERVAL_SEC=300
```

Проверка push вручную:
```bash
.flow/shared/scripts/run.sh ops_remote_status_push
.flow/shared/scripts/run.sh ops_remote_summary_push
```

После этого серверный `/ops/status.json` начнет отдавать удаленный snapshot, если локальные серверные state-файлы пустые (`UNKNOWN`), а `/summary` в Telegram будет использовать удаленный summary bundle вместо пустых server-local логов. Если ingest идет от нескольких consumer-project, dashboard покажет их отдельными source-блоками.

## Nginx интеграция
Идея: nginx принимает публичный трафик и проксирует в локальный сервис `127.0.0.1:8790`.

Пример location-блоков:
```nginx
# dashboard + JSON status
location /ops/ {
  proxy_pass http://127.0.0.1:8790;
  proxy_http_version 1.1;
  proxy_set_header Host $host;
  proxy_set_header X-Real-IP $remote_addr;
  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto $scheme;
}

# telegram webhook (path secret в URL)
location /telegram/webhook/ {
  proxy_pass http://127.0.0.1:8790;
  proxy_http_version 1.1;
  proxy_set_header Host $host;
  proxy_set_header X-Real-IP $remote_addr;
  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto $scheme;
}

# protected debug API
location /ops/debug/ {
  if ($http_authorization != "Bearer ${ops_debug_bearer_token}") {
    return 401;
  }
  proxy_pass http://127.0.0.1:8790;
  proxy_http_version 1.1;
  proxy_set_header Host $host;
  proxy_set_header X-Real-IP $remote_addr;
  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto $scheme;
}
```

## Регистрация webhook в Telegram
После публикации URL:
```bash
.flow/shared/scripts/run.sh ops_bot_webhook_register register
```

Проверка:
```bash
.flow/shared/scripts/run.sh ops_bot_webhook_register info
```

## Диагностика
- PM2 logs:
  - `<log-dir>/pm2/ops_bot.out.log`
  - `<log-dir>/pm2/ops_bot.err.log`
- Health:
  - `.flow/shared/scripts/run.sh ops_bot_pm2_health`
- Snapshot sanity:
  - `.flow/shared/scripts/run.sh status_snapshot | jq .`
- Debug API:
  - `GET /ops/debug/runtime.json`
  - `GET /ops/debug/log-summary.json?hours=6`
  - `GET /ops/debug/logs/daemon?lines=200`

## Smoke-checklist rollout (manual)
1. Проверить prereq: `node -v`, `pm2 -v`, `jq --version`.
2. Проверить конфиг env (`OPS_BOT_*`) и секреты webhook (`OPS_BOT_WEBHOOK_SECRET`, `OPS_BOT_TG_SECRET_TOKEN`).
3. Запустить/обновить сервис в PM2: `.flow/shared/scripts/run.sh ops_bot_pm2_start`.
4. Проверить PM2-статус: `.flow/shared/scripts/run.sh ops_bot_pm2_status` (ожидается `PM2_STATUS=online`, иначе exit code `1`).
5. Проверить health: `.flow/shared/scripts/run.sh ops_bot_pm2_health` (ожидается exit code `0` и JSON `status=ok`; при неготовности процесса/endpoint — exit code `1`).
6. Проверить endpoint-ы через nginx/public URL:
   - `GET /health`
   - `GET /ops/status`
   - `GET /ops/status.json`
7. Проверить устойчивость snapshot/log-summary к неполным локальным данным:
   - `.flow/shared/scripts/run.sh status_snapshot | jq .overall_status` (команда не падает при отсутствующих `.flow/state/codex/*`, подставляет defaults);
   - `.flow/shared/scripts/run.sh log_summary --hours 1` (команда не падает при отсутствующих логах, использует пустые snapshot-файлы).
8. Проверить webhook:
   - зарегистрировать webhook: `.flow/shared/scripts/run.sh ops_bot_webhook_register register`;
   - проверить webhook info: `.flow/shared/scripts/run.sh ops_bot_webhook_register info`;
   - `POST /telegram/webhook/<secret>` с валидным `X-Telegram-Bot-Api-Secret-Token`;
   - невалидный JSON в webhook дает `400 BAD_REQUEST`;
   - payload > 1 MiB дает `413 PAYLOAD_TOO_LARGE`;
   - update без Telegram-команды обрабатывается безопасно (`200`, `command_handled=false`);
   - отправить в Telegram команды `/help`, `/status`, `/summary 6`, `/status_page`.
9. Проверить логи PM2: `<log-dir>/pm2/ops_bot.out.log`, `<log-dir>/pm2/ops_bot.err.log` (нет необработанных ошибок).

## Безопасность
- Не открывать сервис наружу напрямую, только через nginx.
- Обязательно использовать `OPS_BOT_WEBHOOK_SECRET`.
- Для Telegram включить `OPS_BOT_TG_SECRET_TOKEN`.
- Ограничить чаты через `OPS_BOT_ALLOWED_CHAT_IDS`.
