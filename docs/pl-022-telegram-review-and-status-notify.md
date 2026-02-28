# PL-022 - Telegram сигналы на PR-ревью и post-merge статусы

## Цель
- Получать сигнал в Telegram, когда PR в `main` создан или обновлен (чтобы зайти на ревью).
- Получать финальный статус ключевых post-merge workflow, чтобы сразу видеть успешность деплоя и автозакрытия задач.

## Реализация
- PR review сигналы:
  - Workflow: `.github/workflows/notify-telegram-pr-review.yml`
  - Trigger: `pull_request` (`opened`, `reopened`, `synchronize`, `ready_for_review`, `edited`) для ветки `main`
  - В сообщении (HTML): заголовок начинается с `💤/🚨` (в зависимости от необходимости реакции), дальше тип сигнала, ссылка `🔗 𝐏𝐑#<номер>`, компактный блок с задачами.
  - Вспомогательные поля (signal/action/time) вынесены в `blockquote + code`.
  - Убраны лишние поля: автор, направление веток, размер дельты.

- Post-merge статусы:
  - Workflow: `.github/workflows/notify-telegram-main-merge.yml`
  - Trigger: `workflow_run.completed` для:
    - `Deploy Main to Hosting`
    - `Project Auto Close Tasks`
  - В сообщении (HTML): заголовок начинается с `💤/🚨` и содержит `✅/❌` + имя workflow, отдельные блоки `CHECK NOW` и `Status` убраны; остаются ссылка на run и ссылка `𝐏𝐑#<номер>` при наличии PR.
  - Убраны `Repo` и `Linked PRs` (полный список).

- Issue-сигналы агента:
  - Workflow: `.github/workflows/notify-telegram-issue-signals.yml`
  - Сообщение унифицировано: заголовок с `💤/🚨` в первом символе, ссылка на Issue/комментарий, вспомогательный `blockquote + code`.

- Локальные daemon/watchdog-сигналы:
  - `scripts/codex/daemon_loop.sh`, `scripts/codex/watchdog_tick.sh`
  - Добавлены мнемоники статусов GitHub/Telegram (`🟢/🟡/🔴/⚪`) и вспомогательный блок в цитате.
  - Watchdog-уведомления переведены на тот же паттерн: `💤/🚨` в заголовке и без отдельного блока `CHECK NOW`.

## Secrets
- `TG_BOT_TOKEN`
- `TG_CHAT_ID`

## Проверка
1. Открыть/обновить PR `development -> main` с `PL-022` в title/body и убедиться, что пришел сигнал на ревью.
2. Смёрджить PR и проверить два финальных уведомления по completed workflow:
   - `Deploy Main to Hosting`
   - `Project Auto Close Tasks`
3. Убедиться, что при ошибке в любом workflow приходит статус `FAIL`.
