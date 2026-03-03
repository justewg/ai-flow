# Ops Bot + Status Dashboard

## Что это
Локальный сервис `scripts/codex/ops_bot_service.js`, который дает:
- web dashboard: `GET /ops/status`
- JSON snapshot: `GET /ops/status.json`
- Telegram webhook: `POST /telegram/webhook[/<secret>]`
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
curl -sS -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/setWebhook" \
  -d "url=https://planka.ewg40.ru/telegram/webhook/${OPS_BOT_WEBHOOK_SECRET}" \
  -d "secret_token=${OPS_BOT_TG_SECRET_TOKEN}"
```

Проверка:
```bash
curl -sS "https://api.telegram.org/bot${TG_BOT_TOKEN}/getWebhookInfo"
```

## Диагностика
- PM2 logs:
  - `.tmp/codex/pm2/ops_bot.out.log`
  - `.tmp/codex/pm2/ops_bot.err.log`
- Health:
  - `scripts/codex/run.sh ops_bot_pm2_health`
- Snapshot sanity:
  - `scripts/codex/run.sh status_snapshot | jq .`

## Безопасность
- Не открывать сервис наружу напрямую, только через nginx.
- Обязательно использовать `OPS_BOT_WEBHOOK_SECRET`.
- Для Telegram включить `OPS_BOT_TG_SECRET_TOKEN`.
- Ограничить чаты через `OPS_BOT_ALLOWED_CHAT_IDS`.
