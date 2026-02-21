# PL-022 - Telegram сигналы на PR-ревью и post-merge статусы

## Цель
- Получать сигнал в Telegram, когда PR в `main` создан или обновлен (чтобы зайти на ревью).
- Получать финальный статус ключевых post-merge workflow, чтобы сразу видеть успешность деплоя и автозакрытия задач.

## Реализация
- PR review сигналы:
  - Workflow: `.github/workflows/notify-telegram-pr-review.yml`
  - Trigger: `pull_request` (`opened`, `reopened`, `synchronize`, `ready_for_review`, `edited`) для ветки `main`
  - В сообщении: action, PR номер/title, `PL-xxx`, ветки, автор, объем изменений, ссылка на PR

- Post-merge статусы:
  - Workflow: `.github/workflows/notify-telegram-main-merge.yml`
  - Trigger: `workflow_run.completed` для:
    - `Deploy Main to Hosting`
    - `Project Auto Close Tasks`
  - В сообщении: имя workflow, `success/fail`, branch, sha, связанные PR, ссылка на run

## Secrets
- `TG_BOT_TOKEN`
- `TG_CHAT_ID`

## Проверка
1. Открыть/обновить PR `development -> main` с `PL-022` в title/body и убедиться, что пришел сигнал на ревью.
2. Смёрджить PR и проверить два финальных уведомления по completed workflow:
   - `Deploy Main to Hosting`
   - `Project Auto Close Tasks`
3. Убедиться, что при ошибке в любом workflow приходит статус `FAIL`.
