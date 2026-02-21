# PL-021 - Telegram push-уведомления о merge PR в main

## Цель
Получать пуш на мобильник после каждого merge PR в `main`.

## Реализация
- Базовый Telegram-канал уведомлений реализован через GitHub Actions и secrets:
  - `TG_BOT_TOKEN`
  - `TG_CHAT_ID`
- Дальнейшее расширение сценариев уведомлений вынесено в `PL-022`.

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
2. Сделать тестовый merge в `main`.
3. Убедиться, что от бота приходит уведомление.
