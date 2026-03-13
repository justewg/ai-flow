# ISSUE-388 Flow Initializer

Дата: 2026-03-13

## Что реализовано

- В `ai-flow` добавлен один канонический launcher `flow-init.sh`, пригодный для публикации как raw/bootstrap entrypoint:
  - `bash <(curl -fsSL https://raw.githubusercontent.com/justewg/ai-flow/main/flow-init.sh) --profile <name>`
- Launcher использует внутренний toolkit entrypoint `bootstrap_repo` и не требует source-project или migration kit.
- `bootstrap_repo` materialize-ит минимальный `.flow` layout в target repo:
  - подключает `/.flow/shared` как git-submodule в git-repo;
  - вне git worktree использует минимальный `git clone` fallback;
  - создаёт `.flow/config/`, `.flow/tmp/wizard/`, стартовый `COMMAND_TEMPLATES.md`;
  - вызывает `profile_init init`, который пишет безопасные `.flow/config/flow.sample.env` и `.flow/config/flow.env`.
- После bootstrap initializer:
  - запускает `flow_configurator questionnaire`, если доступен interactive tty;
  - иначе печатает один точный следующий шаг для запуска configurator;
  - дополнительно печатает явные handoff-команды для `onboarding_audit` и `profile_init orchestrate`.

## Граница с migration

- `initializer`:
  - первичное подключение flow в новый repo;
  - не переносит project-specific overlay, secrets или source bindings;
  - использует канонический toolkit bootstrap path.
- `migration kit`:
  - переносит уже существующий flow-контур из source-project;
  - разворачивает payload archive и repo overlay;
  - остаётся отдельным сценарием через `create_migration_kit` / `apply_migration_kit`.

## Обновлённый lifecycle

1. Выполнить initializer:
   `bash <(curl -fsSL https://raw.githubusercontent.com/justewg/ai-flow/main/flow-init.sh) --profile acme`
2. Если questionnaire не стартовал автоматически:
   `.flow/shared/scripts/run.sh flow_configurator questionnaire --profile acme`
3. Проверить readiness:
   `.flow/shared/scripts/run.sh onboarding_audit --profile acme`
4. Завершить orchestration:
   `.flow/shared/scripts/run.sh profile_init orchestrate --profile acme`

## Что проверено

- `bash -n` для новых shell entrypoint:
  - `.flow/shared/flow-init.sh`
  - `.flow/shared/scripts/bootstrap_repo.sh`
- Manual smoke на временном чистом git-repo:
  - первый запуск создаёт `/.flow/shared`, `.flow/config/flow.env`, `.flow/config/flow.sample.env`, `COMMAND_TEMPLATES.md`, `.flow/state` symlink;
  - повторный запуск остаётся идемпотентным и возвращает `SHARED_SUBMODULE_ACTION=reused`.

## Ограничения текущего MVP

- Верификация `node --test` для нового smoke-теста не выполнена, потому что в текущем shell отсутствует `node` в `PATH`.
- Для уже существующего non-canonical `/.flow/shared` standalone clone внутри git-repo initializer намеренно блокирует запуск и требует привести path к submodule-модели вручную.
