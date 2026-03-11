# Ops Bot + Status Dashboard

## Что это
Локальный сервис `.flow/scripts/ops_bot_service.js`, который дает:
- health endpoint: `GET /health`
- web dashboard: `GET /ops/status`
- JSON snapshot: `GET /ops/status.json`
- Telegram webhook: `POST /telegram/webhook[/<secret>]`
- runtime ingest endpoint: `POST /ops/ingest/status` (опционально, для split-runtime)
- summary ingest endpoint: `POST /ops/ingest/log-summary` (опционально, для split-runtime `/summary`)
- команды в чате: `/status`, `/summary [hours]`, `/help`, `/status_page`

Источник данных статуса: `.flow/scripts/status_snapshot.sh` (только локальные файлы `.flow/state/codex/*`, без обязательного вызова GitHub API).

Важно: у ops-bot есть два разных контура, и они могут использоваться одновременно.
- Local contour: сам процесс `ops_bot_service.js` на текущем хосте (`OPS_BOT_BIND/OPS_BOT_PORT`, PM2, локальный health/status).
- Public/remote contour: внешний status/webhook server с HTTPS ingress + Telegram webhook + optional ingest endpoints (`OPS_BOT_PUBLIC_BASE_URL`, nginx, `OPS_REMOTE_*` push с другого runtime).

В split-runtime модели daemon/watchdog могут работать на локальном Mac, а публичный Telegram/webhook/status-page жить на сервере. Тогда используются оба контура одновременно: локальный runtime формирует snapshot/summary, а серверный public ops-bot принимает их через ingest и отвечает в Telegram/webhook.

## Локальный запуск
```bash
.flow/scripts/run.sh status_snapshot
.flow/scripts/run.sh ops_bot_start
.flow/scripts/run.sh ops_bot_health
```

PM2:
```bash
.flow/scripts/run.sh ops_bot_pm2_start
.flow/scripts/run.sh ops_bot_pm2_health
.flow/scripts/run.sh ops_bot_pm2_status
.flow/scripts/run.sh ops_bot_pm2_restart
.flow/scripts/run.sh ops_bot_pm2_stop
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
# TG_BOT_TOKEN=... (или OPS_BOT_TG_BOT_TOKEN)
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
OPS_BOT_REMOTE_SNAPSHOT_TTL_SEC=600
OPS_BOT_REMOTE_SUMMARY_TTL_SEC=1200
```

На локальном рантайме (daemon-loop):
```bash
OPS_REMOTE_STATUS_PUSH_ENABLED=1
OPS_REMOTE_STATUS_PUSH_URL=https://ops-runtime.example.com/ops/ingest/status
OPS_REMOTE_STATUS_PUSH_SECRET=<shared-secret>
OPS_REMOTE_STATUS_SOURCE=macbook-local
OPS_REMOTE_SUMMARY_PUSH_ENABLED=1
OPS_REMOTE_SUMMARY_PUSH_URL=https://ops-runtime.example.com/ops/ingest/log-summary
OPS_REMOTE_SUMMARY_PUSH_SECRET=<shared-secret>
OPS_REMOTE_SUMMARY_PUSH_HOURS=1,6,24
OPS_REMOTE_SUMMARY_PUSH_MIN_INTERVAL_SEC=300
```

Проверка push вручную:
```bash
.flow/scripts/run.sh ops_remote_status_push
.flow/scripts/run.sh ops_remote_summary_push
```

После этого серверный `/ops/status.json` начнет отдавать удаленный snapshot, если локальные серверные state-файлы пустые (`UNKNOWN`), а `/summary` в Telegram будет использовать удаленный summary bundle вместо пустых server-local логов.

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
```

## Регистрация webhook в Telegram
После публикации URL:
```bash
.flow/scripts/run.sh ops_bot_webhook_register register
```

Проверка:
```bash
.flow/scripts/run.sh ops_bot_webhook_register info
```

## Диагностика
- PM2 logs:
  - `.flow/logs/pm2/ops_bot.out.log`
  - `.flow/logs/pm2/ops_bot.err.log`
- Health:
  - `.flow/scripts/run.sh ops_bot_pm2_health`
- Snapshot sanity:
  - `.flow/scripts/run.sh status_snapshot | jq .`

## Smoke-checklist rollout (manual)
1. Проверить prereq: `node -v`, `pm2 -v`, `jq --version`.
2. Проверить конфиг env (`OPS_BOT_*`) и секреты webhook (`OPS_BOT_WEBHOOK_SECRET`, `OPS_BOT_TG_SECRET_TOKEN`).
3. Запустить/обновить сервис в PM2: `.flow/scripts/run.sh ops_bot_pm2_start`.
4. Проверить PM2-статус: `.flow/scripts/run.sh ops_bot_pm2_status` (ожидается `PM2_STATUS=online`, иначе exit code `1`).
5. Проверить health: `.flow/scripts/run.sh ops_bot_pm2_health` (ожидается exit code `0` и JSON `status=ok`; при неготовности процесса/endpoint — exit code `1`).
6. Проверить endpoint-ы через nginx/public URL:
   - `GET /health`
   - `GET /ops/status`
   - `GET /ops/status.json`
7. Проверить устойчивость snapshot/log-summary к неполным локальным данным:
   - `.flow/scripts/run.sh status_snapshot | jq .overall_status` (команда не падает при отсутствующих `.flow/state/codex/*`, подставляет defaults);
   - `.flow/scripts/run.sh log_summary --hours 1` (команда не падает при отсутствующих логах, использует пустые snapshot-файлы).
8. Проверить webhook:
   - зарегистрировать webhook: `.flow/scripts/run.sh ops_bot_webhook_register register`;
   - проверить webhook info: `.flow/scripts/run.sh ops_bot_webhook_register info`;
   - `POST /telegram/webhook/<secret>` с валидным `X-Telegram-Bot-Api-Secret-Token`;
   - невалидный JSON в webhook дает `400 BAD_REQUEST`;
   - payload > 1 MiB дает `413 PAYLOAD_TOO_LARGE`;
   - update без Telegram-команды обрабатывается безопасно (`200`, `command_handled=false`);
   - отправить в Telegram команды `/help`, `/status`, `/summary 6`, `/status_page`.
9. Проверить логи PM2: `.flow/logs/pm2/ops_bot.out.log`, `.flow/logs/pm2/ops_bot.err.log` (нет необработанных ошибок).

## Безопасность
- Не открывать сервис наружу напрямую, только через nginx.
- Обязательно использовать `OPS_BOT_WEBHOOK_SECRET`.
- Для Telegram включить `OPS_BOT_TG_SECRET_TOKEN`.
- Ограничить чаты через `OPS_BOT_ALLOWED_CHAT_IDS`.
