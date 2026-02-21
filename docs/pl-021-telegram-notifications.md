# PL-021 - Telegram push-уведомления о merge PR в main

## Цель
Получать пуш на мобильник после каждого merge PR в `main`.

## Реализация
- Workflow: `.github/workflows/notify-telegram-main-merge.yml`
- Trigger: `pull_request.closed` для ветки `main`
- Gate: выполняется только при `merged == true`
- Формат сообщения:
  - номер и title PR
  - связанные задачи `PL-xxx` (из title/body PR)
  - автор PR и кто смержил
  - ссылка на PR и на run workflow

## Что нужно добавить в GitHub Secrets
- `TG_BOT_TOKEN` - токен из BotFather
- `TG_CHAT_ID` - chat id, куда слать уведомления

## Как получить TG_CHAT_ID для личного чата
1. Напиши боту `/start` в Telegram.
2. Выполни локально:
   ```bash
   curl -s "https://api.telegram.org/bot<TG_BOT_TOKEN>/getUpdates" | jq .
   ```
3. Возьми `message.chat.id` из ответа и положи это значение в `TG_CHAT_ID`.

## Проверка
1. Убедиться, что секреты сохранены в repo settings.
2. Сделать тестовый PR `development -> main` с `PL-021` в title/body.
3. После merge проверить:
   - run `Notify Telegram on Main Merge` зеленый;
   - на мобильник пришло сообщение от бота.
