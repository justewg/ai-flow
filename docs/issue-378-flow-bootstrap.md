# ISSUE-378 Bootstrap `.flow` и shared toolkit

Дата: 2026-03-13

## Что реализовано

- Добавлен новый bootstrap/materialize entrypoint `bootstrap_repo` в shared toolkit.
- Bootstrap работает по `--target-repo` и может готовить как чистый repo, так и partially configured checkout.
- Для пути с `migration_kit.tgz` bootstrap больше не дублирует env/layout-логику:
  - подключает `/.flow/shared` как submodule;
  - при наличии manifest вызывает `apply_migration_kit`;
  - затем всегда вызывает `profile_init init` для state/log/launchd layout.

## Сценарии submodule path

### `init`

Условие:
- в target repo нет gitlink `/.flow/shared`.

Действие:
- создаётся `.flow/`;
- в `.gitmodules` добавляется секция submodule;
- выполняется `git submodule add ... .flow/shared`;
- submodule checkout фиксируется на заданном `--shared-revision` или revision из migration-kit manifest.

### `update`

Условие:
- `/.flow/shared` уже submodule, но URL/branch/revision расходятся с ожидаемыми.

Действие:
- bootstrap синхронизирует `.gitmodules`;
- выполняет `git submodule update --init --checkout`;
- при необходимости fetch/checkout нужного revision.

### `repair`

Условие:
- в repo уже лежит snapshot `.flow/shared` после распаковки kit или частичной ручной подготовки.

Действие:
- snapshot переносится в `.flow/tmp/bootstrap/backups/shared-pre-submodule-<timestamp>`;
- на его месте materialize-ится canonical submodule `/.flow/shared`;
- дальше bootstrap продолжает обычный `apply_migration_kit/profile_init init` path.

## Какие артефакты materialize-ятся

Bootstrap создаёт или переиспользует:

- `.flow/config/`
- `.flow/config/profiles/.gitkeep`
- `.flow/config/root/github-actions.required-files.txt`
- `.flow/config/root/github-actions.required-secrets.txt`
- `.flow/config/flow.sample.env`
- `.flow/config/flow.env`
- `.flow/tmp/`
- `.flow/tmp/wizard/`
- `.flow/tmp/bootstrap/backups/` только при repair snapshot/submodule path
- `/.flow/shared` как git-submodule

Через `profile_init init` дополнительно подготавливаются runtime links/layout:

- `.flow/state -> <AI_FLOW_ROOT_DIR>/state/<profile>`
- `.flow/logs -> <AI_FLOW_ROOT_DIR>/logs/<profile>` или `FLOW_LOGS_DIR`
- `.flow/launchd -> <AI_FLOW_ROOT_DIR>/launchd/<profile>`
- host-level runtime logs `<...>/runtime/{daemon,executor,watchdog,graphql_rate_stats}.log`
- compatibility symlink-и логов внутри `<state-dir>`

Для migration-kit path bootstrap также materialize-ит:

- `.github/workflows/*.yml`
- `.github/pull_request_template.md`
- `.flow/templates/github/`
- `.flow/tmp/migration_kit_manifest.env`

## Поведение при повторном запуске и partial state

- Повторный запуск не пересоздаёт submodule и env вслепую: bootstrap сообщает `SHARED_SUBMODULE_ACTION=reused|updated|repaired`.
- Если `flow.env` уже существует, `profile_init init` не перезаписывает его без явного force-path внутри backend-команды.
- Placeholder-директории из migration kit (`.flow/state/.keep` и аналогичные) repair-ятся в canonical symlink, если в них нет реальных данных.
- При tracked diff в управляемых путях (`.gitmodules`, `.flow/shared`, unpack/overwrite targets) bootstrap блокирует destructive path без `--allow-dirty-tracked`.

## Что проверено вручную

- `clean repo`: bootstrap создаёт `.flow/config`, `.flow/tmp/wizard`, submodule `/.flow/shared`, `flow.env`, `flow.sample.env`, symlink-и `.flow/state`, `.flow/logs`, `.flow/launchd`.
- `rerun`: повторный запуск остаётся idempotent и возвращает `SHARED_SUBMODULE_ACTION=reused`.
- `migration kit -> repair`: bootstrap переносит snapshot `.flow/shared` в backup, переключает repo на submodule path, применяет overlay и materialize-ит canonical runtime links.
- `tracked diff guard`: при изменённом tracked-контенте внутри уже materialized `.flow` bootstrap останавливается с `BOOTSTRAP_BLOCKED_DIRTY=*` и требует явный `--allow-dirty-tracked` для destructive path.
