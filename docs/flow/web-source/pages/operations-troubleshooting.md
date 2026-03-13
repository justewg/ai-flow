# Ops, troubleshooting и runbooks

## Базовый набор диагностики

| Что проверить | Команда |
| --- | --- |
| Текущее состояние автоматики | `.flow/shared/scripts/run.sh status_snapshot` |
| История деградаций и пауз | `.flow/shared/scripts/run.sh log_summary --hours 6` |
| Доступность GitHub | `.flow/shared/scripts/run.sh github_health_check` |
| Auth-service | `.flow/shared/scripts/run.sh gh_app_auth_probe` |
| Ops bot | `.flow/shared/scripts/run.sh ops_bot_pm2_health` |
| Daemon | `.flow/shared/scripts/run.sh daemon_status` |
| Watchdog | `.flow/shared/scripts/run.sh watchdog_status` |

## Канонические runbook-направления

- GitHub App auth и hybrid token mode: `.flow/shared/docs/gh-app-daemon-integration-plan.md`
- Ops dashboard, webhook и split-runtime status surface: `.flow/shared/docs/ops-bot-dashboard.md`
- Self-hosted runner для preview/prod deploy: `docs/self-hosted-runner-deploy.md`
- Portability и rollback нового profile: `.flow/shared/docs/flow-portability-runbook.md`

## Частые operational states

| State | Что означает | Первый шаг |
| --- | --- | --- |
| `WAIT_OPEN_PR` | уже есть открытый `development -> main` PR | закрыть или домержить текущую review-дельту |
| `WAIT_DEPENDENCIES` | у карточки есть незакрытые `Depends-On` | проверить blockers в Issue body и Project |
| `WAIT_DIRTY_WORKTREE` | tracked-файлы мешают автоподхвату | очистить diff или использовать согласованный override path |
| `WAIT_GITHUB_OFFLINE` / `WAIT_GITHUB_RATE_LIMIT` | деградация GitHub API | проверить `github_health_check`, rate-limit и deferred runtime queue |
| `WAIT_AUTH_SERVICE` | auth-service не выдает token | проверить `gh_app_auth_*` и fallback policy |
| `WAIT_USER_REPLY` / `WAIT_REVIEW_FEEDBACK` | runtime ждет ответ пользователя | продолжить через Issue-comment/feedback flow |

## Deploy и publish

- Dev preview и prod deploy работают отдельными workflow.
- Web-docs publish тоже запускается post-merge из `main`.
- Для publish на Readocly Reunite нужны отдельные secrets, но сборка artifact выполняется всегда.
