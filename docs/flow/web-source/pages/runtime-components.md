# Основные runtime-компоненты

## Компоненты

| Компонент | Роль | Когда использовать |
| --- | --- | --- |
| `daemon` | Читает Project queue, клеймит `Todo`, ведет active/waiting/review context | Основной runtime цикла задачи |
| `watchdog` | Следит за зависанием daemon/executor и делает recovery | Когда нужен самовосстанавливающийся фон без ручного контроля |
| `executor` | Выполняет инженерную дельту и промежуточные шаги в task-cycle | После claim задачи демоном |
| `ops/status` | Отдает snapshot, summary и web/Telegram surface | Для диагностики и наблюдаемости |
| GitHub integration | Issue/PR/Project операции, auth-service, Telegram workflows | Для связи runtime с GitHub и post-merge автоматикой |

## Канонические команды runtime

| Задача | Команда |
| --- | --- |
| Один тик демона | `.flow/shared/scripts/run.sh daemon_tick` |
| Установка демона | `.flow/shared/scripts/run.sh daemon_install [label] [interval-sec]` |
| Статус демона | `.flow/shared/scripts/run.sh daemon_status [label]` |
| Один тик watchdog | `.flow/shared/scripts/run.sh watchdog_tick` |
| Статус watchdog | `.flow/shared/scripts/run.sh watchdog_status [label]` |
| Snapshot автоматики | `.flow/shared/scripts/run.sh status_snapshot` |
| Сводка по логам | `.flow/shared/scripts/run.sh log_summary [--hours N]` |
| Health GitHub auth | `.flow/shared/scripts/run.sh gh_app_auth_probe` |
| Health ops bot | `.flow/shared/scripts/run.sh ops_bot_pm2_health` |

## Контракты компонентов

### Daemon

- не берет новую задачу при открытом `development -> main` PR;
- уважает `Depends-On`, dirty-worktree gate и waiting/review контекст;
- фиксирует operational state в runtime state/logs.

### Watchdog

- не выбирает задачи, а только восстанавливает runtime;
- работает по escalation-уровням `soft -> medium -> hard`;
- не подменяет ручные решения пользователя по blocker/review feedback.

### Executor

- выполняет инженерную работу внутри уже выбранной задачи;
- при блокере пишет Issue-комментарий через `task_ask`;
- не считается завершением задачи до `task_finalize` и PR-сигнала review.

### Ops/status и GitHub integration

- `status_snapshot` и `log_summary` дают каноническую диагностику без ручного grep по логам;
- `ops_bot` публикует статус наружу;
- auth-service и project tokens отделяют Issue/PR-авторство от Project v2 операций.
