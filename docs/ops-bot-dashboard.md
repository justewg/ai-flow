# Ops Bot + Status Dashboard

## Что это
Локальный сервис `scripts/codex/ops_bot_service.js`, который дает:
- health endpoint: `GET /health`
- web dashboard: `GET /ops/status`
- JSON snapshot: `GET /ops/status.json`
- Telegram webhook: `POST /telegram/webhook[/<secret>]`
- runtime ingest endpoint: `POST /ops/ingest/status` (опционально, для split-runtime)
- команды в чате: `/status`, `/summary [hours]`, `/help`, `/status_page`

Источник данных статуса: `scripts/codex/status_snapshot.sh` (только локальные файлы `.tmp/codex/*`, без обязательного вызова GitHub API).

## Локальный запуск
```bash
scripts/codex/run.sh status_snapshot
scripts/codex/run.sh ops_bot_start
scripts/codex/run.sh ops_bot_health
```

PM2:
```bash
scripts/codex/run.sh ops_bot_pm2_start
scripts/codex/run.sh ops_bot_pm2_health
scripts/codex/run.sh ops_bot_pm2_status
scripts/codex/run.sh ops_bot_pm2_restart
scripts/codex/run.sh ops_bot_pm2_stop
```

## Рекомендуемые env
```bash
OPS_BOT_BIND=127.0.0.1
OPS_BOT_PORT=8790
OPS_BOT_WEBHOOK_PATH=/telegram/webhook
OPS_BOT_WEBHOOK_SECRET=<long-random-path-secret>
OPS_BOT_TG_SECRET_TOKEN=<long-random-header-secret>
OPS_BOT_ALLOWED_CHAT_IDS=<your_chat_id>
OPS_BOT_PUBLIC_BASE_URL=https://planka.ewg40.ru
# TG_BOT_TOKEN=... (или OPS_BOT_TG_BOT_TOKEN)
```

### Split runtime (локальная автоматика + удаленный HTTPS бот)
Если daemon/watchdog работают на локальном Mac, а ops-bot/webhook на сервере:

На сервере (ops-bot):
```bash
OPS_BOT_INGEST_ENABLED=1
OPS_BOT_INGEST_PATH=/ops/ingest/status
OPS_BOT_INGEST_SECRET=<shared-secret>
OPS_BOT_REMOTE_SNAPSHOT_TTL_SEC=600
```

На локальном рантайме (daemon-loop):
```bash
OPS_REMOTE_STATUS_PUSH_ENABLED=1
OPS_REMOTE_STATUS_PUSH_URL=https://planka-dev.ewg40.ru/ops/ingest/status
OPS_REMOTE_STATUS_PUSH_SECRET=<shared-secret>
OPS_REMOTE_STATUS_SOURCE=macbook-local
```

Проверка push вручную:
```bash
scripts/codex/run.sh ops_remote_status_push
```

После этого серверный `/ops/status.json` начнет отдавать удаленный snapshot, если локальные серверные state-файлы пустые (`UNKNOWN`).

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
scripts/codex/run.sh ops_bot_webhook_register register
```

Проверка:
```bash
scripts/codex/run.sh ops_bot_webhook_register info
```

## Диагностика
- PM2 logs:
  - `.tmp/codex/pm2/ops_bot.out.log`
  - `.tmp/codex/pm2/ops_bot.err.log`
- Health:
  - `scripts/codex/run.sh ops_bot_pm2_health`
- Snapshot sanity:
  - `scripts/codex/run.sh status_snapshot | jq .`

## Smoke-checklist rollout (manual)
1. Проверить prereq: `node -v`, `pm2 -v`, `jq --version`.
2. Проверить конфиг env (`OPS_BOT_*`) и секреты webhook (`OPS_BOT_WEBHOOK_SECRET`, `OPS_BOT_TG_SECRET_TOKEN`).
3. Запустить/обновить сервис в PM2: `scripts/codex/run.sh ops_bot_pm2_start`.
4. Проверить PM2-статус: `scripts/codex/run.sh ops_bot_pm2_status` (ожидается `PM2_STATUS=online`, иначе exit code `1`).
5. Проверить health: `scripts/codex/run.sh ops_bot_pm2_health` (ожидается exit code `0` и JSON `status=ok`; при неготовности процесса/endpoint — exit code `1`).
6. Проверить endpoint-ы через nginx/public URL:
   - `GET /health`
   - `GET /ops/status`
   - `GET /ops/status.json`
7. Проверить устойчивость snapshot/log-summary к неполным локальным данным:
   - `scripts/codex/run.sh status_snapshot | jq .overall_status` (команда не падает при отсутствующих `.tmp/codex/*`, подставляет defaults);
   - `scripts/codex/run.sh log_summary --hours 1` (команда не падает при отсутствующих логах, использует пустые snapshot-файлы).
8. Проверить webhook:
   - зарегистрировать webhook: `scripts/codex/run.sh ops_bot_webhook_register register`;
   - проверить webhook info: `scripts/codex/run.sh ops_bot_webhook_register info`;
   - `POST /telegram/webhook/<secret>` с валидным `X-Telegram-Bot-Api-Secret-Token`;
   - невалидный JSON в webhook дает `400 BAD_REQUEST`;
   - payload > 1 MiB дает `413 PAYLOAD_TOO_LARGE`;
   - update без Telegram-команды обрабатывается безопасно (`200`, `command_handled=false`);
   - отправить в Telegram команды `/help`, `/status`, `/summary 6`, `/status_page`.
9. Проверить логи PM2: `.tmp/codex/pm2/ops_bot.out.log`, `.tmp/codex/pm2/ops_bot.err.log` (нет необработанных ошибок).

## Безопасность
- Не открывать сервис наружу напрямую, только через nginx.
- Обязательно использовать `OPS_BOT_WEBHOOK_SECRET`.
- Для Telegram включить `OPS_BOT_TG_SECRET_TOKEN`.
- Ограничить чаты через `OPS_BOT_ALLOWED_CHAT_IDS`.
