# Архитектура платформенного решения

## Слои системы

| Слой | Назначение | Канонические элементы |
| --- | --- | --- |
| Control plane | Выбор задач, статусы, review feedback и merge-сигналы | GitHub Project v2, Issue, PR, комментарии, `Status/Flow` |
| Runtime plane | Подхват задачи, выполнение, ожидание ответа, recovery | `daemon_loop`, `watchdog_loop`, `executor_*`, `task_ask`, `task_finalize` |
| Toolkit plane | Переиспользуемые entrypoint-команды и bootstrap/migration сценарии | `.flow/shared/scripts/run.sh`, `flow-init.sh`, `flow_configurator`, `profile_init`, `create_migration_kit` |
| Ops plane | Наблюдаемость, health-check, статусы, Telegram/web dashboard | `status_snapshot`, `log_summary`, `ops_bot_*`, `gh_app_auth_*` |
| Delivery plane | Preview/prod deploy, post-merge закрытие, docs publish | `.github/workflows/*`, self-hosted runner `planka-deploy`, Reunite publish job |

## Базовая схема взаимодействия

1. GitHub Project переводит задачу в `Todo`.
2. Daemon клеймит задачу и переводит ее в `In Progress`.
3. Executor реализует дельту и может уйти в `WAIT_USER_REPLY` или `WAIT_REVIEW_FEEDBACK`.
4. `task_finalize` оформляет `development -> main` PR и переводит карточку в `Review`.
5. Merge в `main` запускает post-merge workflows: deploy, project auto-close, уведомления и publish web-docs.

## Почему архитектура разделена именно так

- Control plane остается в GitHub и не дублируется локальным state.
- Runtime-plane отвечает только за выполнение и восстановление, а не за выбор бизнес-приоритета.
- Toolkit-plane позволяет переносить flow между проектами без форка bash-логики.
- Ops-plane отделяет диагностику и публичный status surface от daemon/executor.
- Delivery-plane держит публикации и merge-автоматику в reproducible workflow.

## Стабильные точки входа

- `.flow/shared/scripts/run.sh <command>`
- `bash <(curl -fsSL https://raw.githubusercontent.com/justewg/ai-flow/main/flow-init.sh) --profile <name>`
- `python3 scripts/flow_docs/build_flow_docs.py`
