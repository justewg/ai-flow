# Конфигуратор и канонические entrypoint-команды

## Что входит в configurator surface

- `flow-init.sh` для первичного bootstrap нового repo;
- `bootstrap_repo` для materialize `.flow` и shared toolkit;
- `flow_configurator questionnaire` для заполнения `flow.env`;
- `onboarding_audit` для проверки окружения и overlay;
- `profile_init` для install/preflight/orchestration.

## Канонические команды

```bash
# 1. bootstrap нового проекта
bash <(curl -fsSL https://raw.githubusercontent.com/justewg/ai-flow/main/flow-init.sh) --profile acme

# 2. запуск configurator вручную
.flow/shared/scripts/run.sh flow_configurator questionnaire --profile acme

# 3. аудит readiness
.flow/shared/scripts/run.sh onboarding_audit --profile acme

# 4. финальная orchestration
.flow/shared/scripts/run.sh profile_init orchestrate --profile acme

# 5. ручной install/preflight path
.flow/shared/scripts/run.sh profile_init install --profile acme
.flow/shared/scripts/run.sh profile_init preflight --profile acme
```

## Supported scenarios

| Сценарий | Что использовать |
| --- | --- |
| `fresh_repo` | `flow-init.sh` -> `flow_configurator` -> `onboarding_audit` -> `profile_init orchestrate` |
| `partial_repo` | `flow_configurator` + `onboarding_audit` + адресное исправление missing checks |
| `rerun_reconfigure` | повторный `flow_configurator` с preview diff и повторный `preflight` |
| `migration_kit` | `create_migration_kit` / `do_migration.sh` / `apply_migration_kit` |

## Что configurator не должен делать

- переписывать вручную существующий docs corpus;
- хранить secret state вне `flow.env` и GitHub secrets;
- обходить toolkit entrypoint-команды прямыми ad-hoc скриптами;
- смешивать project-specific binding с hardcoded логикой в shared toolkit.
