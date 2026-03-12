# ISSUE-70 - Smoke-test daemon-flow с GitHub App

## Цель
Проверить end-to-end сценарий daemon-flow и подтвердить авторство действий в `Issue/PR/Project` со стороны GitHub App (`app-name[bot]`).

## Выполненный сценарий
1. Проверен рабочий контур daemon-flow без ручной подмены токена в ходе шага:
   - `.flow/shared/scripts/run.sh github_health_check` -> `GITHUB_HEALTHY=1`.
   - `.flow/shared/scripts/run.sh daemon_tick` -> активная задача `ISSUE-70`, `EXECUTOR_RUNNING=1`.
2. Зафиксирован автоподхват задачи демоном:
   - `<state-dir>/daemon.log` (исторически это был `.tmp/codex/daemon.log`), `2026-02-24T01:51:26Z`:
     - `CLAIMED_TASK_ID=ISSUE-70`
     - `CLAIMED_FROM_STATUS=Todo`
     - `CLAIMED_TO_STATUS=In Progress`
3. Для полного цикла `Todo -> In Progress -> Review -> Done` использован ближайший завершенный прогон в том же daemon-контуре:
   - `Issue #69` + `PR #79` (выполнены 2026-02-24 в рамках этой же цепочки APP-01..APP-07).

## Проверка авторства действий
Проверка выполнена через `gh` (GraphQL/REST):

- Issue (комментарий автоматики):
  - `Issue #69`, комментарий `CODEX_SIGNAL: AGENT_IN_REVIEW`, `createdAt=2026-02-24T01:49:14Z`.
  - `author.login=justewg` (ожидалось `app-name[bot]`).
- PR:
  - `PR #79`, `createdAt=2026-02-24T01:49:12Z`.
  - `author.login=justewg` (ожидалось `app-name[bot]`).
- Project (смена Status):
  - `Issue #69`: `Backlog -> Todo -> In Progress -> Review -> Done`, actor `justewg`.
  - `Issue #70`: `Backlog -> Todo -> In Progress` (`2026-02-24T01:50:54Z` и `2026-02-24T01:51:25Z`), actor `justewg`.
  - Ожидалось авторство от GitHub App bot.

## Результат smoke-test
- [x] Тестовый daemon-flow запущен и проходит по состояниям без ручной подмены токена в ходе шага.
- [ ] Авторство действий в `Issue/PR/Project` соответствует GitHub App (`app-name[bot]`).
- [x] Отчет smoke-теста добавлен в `docs`.

Итог: сценарий функционально работает, но критерий авторства GitHub App не выполнен.

## Остаточные риски
1. Автоматика продолжает работать от пользовательской identity (`justewg`), а не от GitHub App bot.
2. Не подтверждено, что текущий daemon-процесс действительно берет installation token из auth-сервиса на каждом цикле.
3. До устранения расхождения с авторством нельзя считать миграцию на GitHub App завершенной.
