# Процессы и диаграммы

Этот раздел собирает канонические диаграммы flow и объясняет, как их читать в runtime-контексте.

## Карта процессов

### Task lifecycle

- `Backlog -> Todo -> In Progress -> Review -> Done` задает жизненный цикл карточки.
- Между `In Progress` и `Review` возможны ответвления `WAIT_USER_REPLY`, `WAIT_REVIEW_FEEDBACK`, `WAIT_DEPENDENCIES`, `WAIT_DIRTY_WORKTREE`.

### Issue -> development -> PR -> main

1. Задача стартует из GitHub Project.
2. Daemon/executor готовят дельту в рабочем цикле.
3. `task_finalize` оформляет или обновляет PR `development -> main`.
4. Merge в `main` запускает deploy, auto-close, post-merge уведомления и publish web-docs.

### Waiting / blocker / review paths

- `AGENT_QUESTION` и `AGENT_BLOCKER` переводят runtime в ожидание ответа.
- review feedback возвращает задачу из `Review` обратно в `In Progress`.
- dirty-worktree и dependency gates не дают silently продолжать выполнение.

### Migration / onboarding path

- новый проект проходит `flow-init` или `create_migration_kit -> do_migration.sh`;
- затем `flow_configurator`, `onboarding_audit`, `profile_init orchestrate`;
- после smoke `Todo -> In Progress` контур считается подключенным.

## Диаграммы

{{FLOW_PROCESS_DIAGRAMS}}

## Download-артефакты диаграмм

{{FLOW_DIAGRAM_DOWNLOADS}}
