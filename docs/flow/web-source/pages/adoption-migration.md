# Migration и init сценарии

## Когда нужен initializer, а когда migration kit

| Сценарий | Правильный entrypoint |
| --- | --- |
| Новый repo без существующего flow-контура | `flow-init.sh` |
| Перенос уже работающего consumer-project | `create_migration_kit` -> `do_migration.sh` |
| Частично materialized `.flow` в target repo | `bootstrap_repo`/repair path, затем `flow_configurator` |

## Migration path

1. В source project собрать migration kit:

```bash
.flow/shared/scripts/run.sh create_migration_kit --project acme --target-repo <HOME>/sites/acme-app
```

2. В target repo запустить launcher:

```bash
.flow/migration/do_migration.sh
```

3. После materialize-пути завершить конфигурацию:

```bash
.flow/shared/scripts/run.sh flow_configurator questionnaire --profile acme
.flow/shared/scripts/run.sh onboarding_audit --profile acme
.flow/shared/scripts/run.sh profile_init orchestrate --profile acme
```

## Что migration kit переносит

- `flow.env` и `flow.sample.env`;
- repo overlay `.github/*`, если он включен в payload;
- manifest required files/secrets;
- migration metadata и launcher для target repo.

## Что migration kit намеренно не решает сам

- бизнес-выбор нового `GITHUB_REPO` и `PROJECT_*`, если binding не закреплен явно;
- подготовку GitHub Actions secrets в новом repo;
- запуск smoke за пользователя;
- выравнивание legacy-docs стиля вне того, что нужно для канонической web-навигации.
