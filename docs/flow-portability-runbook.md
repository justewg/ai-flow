# Flow Portability Runbook

## Цель
Зафиксировать воспроизводимый сценарий переноса flow-комплекта `scripts/codex` из текущего проекта в новый consumer-project, не ломая рабочий current project на том же хосте.

Документ покрывает:
- bootstrap и эксплуатацию двух проектов параллельно;
- миграцию `current -> new project`;
- smoke и rollback;
- troubleshooting;
- стратегию выноса `scripts/codex` в отдельный toolkit-repo.

## Термины
- `current project` — существующий проект, где flow уже работает.
- `new project` — новый consumer-repo/Project v2, который подключается к flow-комплекту.
- `profile` — набор `env + state-dir + launchd labels`, отделяющий один проект от другого.
- `<state-dir>` — каталог runtime-состояния, логов, fixed input files и snapshot-артефактов `run.sh`.

## Целевая схема для двух проектов

| Контур | Repo | Profile | Env file | State dir | Daemon label | Watchdog label |
| --- | --- | --- | --- | --- | --- | --- |
| Current | `justewg/planka` | `default` | `.env` или `.tmp/codex/profiles/default.env` | `.tmp/codex` | `com.planka.codex-daemon` | `com.planka.codex-watchdog` |
| New | `<owner>/<new-repo>` | `acme` | `.tmp/codex/profiles/acme.env` | `.tmp/codex/acme` | `com.planka.codex-daemon.acme` | `com.planka.codex-watchdog.acme` |

Инварианты:
- у каждого проекта свой `CODEX_STATE_DIR/FLOW_STATE_DIR`;
- у каждого launchd-агента свой label;
- для `PROJECT_PROFILE != default` обязательно заданы `PROJECT_ID`, `PROJECT_NUMBER`, `PROJECT_OWNER`;
- у user-owned Project v2 для каждого проекта должен быть свой валидный `DAEMON_GH_PROJECT_TOKEN`, если используется hybrid mode.

## Предпосылки
1. В новом репозитории уже есть копия `scripts/codex` и связанных документов, совместимая с current project.
2. На хосте доступны `bash`, `gh`, `jq`, `node`, `launchctl`.
3. GitHub App auth-сервис настроен, либо подготовлен fallback (`DAEMON_GH_TOKEN_FALLBACK_ENABLED=1` + `DAEMON_GH_TOKEN`).
4. Для нового проекта известны `GITHUB_REPO`, `PROJECT_ID`, `PROJECT_NUMBER`, `PROJECT_OWNER`.
5. Рабочее дерево нового проекта чистое по tracked-файлам перед первым bootstrap.

## План миграции current -> new project

### 1. Зафиксировать рабочую базу current project
1. Проверить текущий профиль:
   `scripts/codex/run.sh daemon_status com.planka.codex-daemon`
2. Снять snapshot текущего состояния:
   `scripts/codex/run.sh status_snapshot`
3. Зафиксировать путь текущего state-dir и labels, чтобы не переиспользовать их в новом проекте.

### 2. Подготовить flow-комплект в new project
1. Перенести каталог `scripts/codex` и связанные docs в новый репозиторий отдельной дельтой.
2. Не редактировать скрипты под новый проект вручную, пока перенос не доказан env-конфигурацией.
3. Оставить repo/project-binding в env, а не в исходниках.

### 3. Инициализировать новый profile
1. Выполнить:
   `scripts/codex/run.sh profile_init init --profile acme`
2. Открыть `.tmp/codex/profiles/acme.env`.
3. Заполнить минимум:
   - `PROJECT_PROFILE=acme`
   - `GITHUB_REPO=<owner>/<new-repo>`
   - `FLOW_BASE_BRANCH=main`
   - `FLOW_HEAD_BRANCH=development`
   - `PROJECT_ID=<new-project-id>`
   - `PROJECT_NUMBER=<new-project-number>`
   - `PROJECT_OWNER=<@owner-or-org>`
   - `DAEMON_GH_PROJECT_TOKEN=<project-token>`
   - `GH_APP_INTERNAL_SECRET=<shared-secret>` либо fallback-token pair
4. Убедиться, что в файле есть:
   - `CODEX_STATE_DIR=<root-dir>/.tmp/codex/acme`
   - `FLOW_STATE_DIR=<root-dir>/.tmp/codex/acme`
   - `WATCHDOG_DAEMON_LABEL=com.planka.codex-daemon.acme`
   - `WATCHDOG_DAEMON_INTERVAL_SEC=45`

### 4. Установить automation для new project
1. Запустить:
   `scripts/codex/run.sh profile_init install --profile acme`
2. Скрипт сам провалидирует env и установит:
   - `daemon_install com.planka.codex-daemon.acme 45`
   - `watchdog_install com.planka.codex-watchdog.acme 45`
3. Если нужен предварительный просмотр без изменений, использовать:
   `scripts/codex/run.sh profile_init bootstrap --profile acme --dry-run`

### 5. Выполнить smoke нового проекта
1. Базовый preflight:
   `scripts/codex/run.sh profile_init preflight --profile acme`
   Ожидается `PREFLIGHT_READY=1`.
2. Проверка daemon:
   `env DAEMON_GH_ENV_FILE=.tmp/codex/profiles/acme.env CODEX_STATE_DIR=.tmp/codex/acme FLOW_STATE_DIR=.tmp/codex/acme scripts/codex/run.sh daemon_status com.planka.codex-daemon.acme`
3. Проверка watchdog:
   `env DAEMON_GH_ENV_FILE=.tmp/codex/profiles/acme.env CODEX_STATE_DIR=.tmp/codex/acme FLOW_STATE_DIR=.tmp/codex/acme scripts/codex/run.sh watchdog_status com.planka.codex-watchdog.acme`
4. Проверка GitHub API:
   `env DAEMON_GH_ENV_FILE=.tmp/codex/profiles/acme.env CODEX_STATE_DIR=.tmp/codex/acme FLOW_STATE_DIR=.tmp/codex/acme scripts/codex/run.sh github_health_check`
5. Проверка snapshot:
   `env DAEMON_GH_ENV_FILE=.tmp/codex/profiles/acme.env CODEX_STATE_DIR=.tmp/codex/acme FLOW_STATE_DIR=.tmp/codex/acme scripts/codex/run.sh status_snapshot`
6. Проверка App token exchange:
   `env DAEMON_GH_ENV_FILE=.tmp/codex/profiles/acme.env CODEX_STATE_DIR=.tmp/codex/acme FLOW_STATE_DIR=.tmp/codex/acme scripts/codex/gh_app_auth_token.sh >/dev/null`
7. Функциональный smoke:
   - создать тестовую карточку в новом Project v2 со статусом `Todo`;
   - дождаться claim демоном в `In Progress`;
   - убедиться, что изменения ушли только в новый Project и новый repo;
   - закрыть smoke-цикл до `Review`/`Done` либо откатить карточку вручную.

### 6. Подтвердить параллельную эксплуатацию двух проектов
1. Повторить `daemon_status`, `watchdog_status`, `status_snapshot` для current project.
2. Проверить, что:
   - current project использует старый `<state-dir>`;
   - new project использует `.tmp/codex/acme`;
   - launchd labels не пересекаются;
   - логи пишутся в разные каталоги.
3. После подтверждения можно считать перенос flow-комплекта воспроизводимым.

## Эксплуатация двух проектов

### Запуск
1. Для current project использовать его существующий profile/env.
2. Для new project штатный запуск выполняется через:
   `scripts/codex/run.sh profile_init install --profile acme`
3. Если daemon/watchdog уже были удалены, можно поднять их вручную с тем же env:
   - `env DAEMON_GH_ENV_FILE=.tmp/codex/profiles/acme.env CODEX_STATE_DIR=.tmp/codex/acme FLOW_STATE_DIR=.tmp/codex/acme scripts/codex/run.sh daemon_install com.planka.codex-daemon.acme 45`
   - `env DAEMON_GH_ENV_FILE=.tmp/codex/profiles/acme.env CODEX_STATE_DIR=.tmp/codex/acme FLOW_STATE_DIR=.tmp/codex/acme WATCHDOG_DAEMON_LABEL=com.planka.codex-daemon.acme WATCHDOG_DAEMON_INTERVAL_SEC=45 scripts/codex/run.sh watchdog_install com.planka.codex-watchdog.acme 45`

### Остановка
1. Остановить watchdog нового профиля:
   `scripts/codex/run.sh watchdog_uninstall com.planka.codex-watchdog.acme`
2. Остановить daemon нового профиля:
   `scripts/codex/run.sh daemon_uninstall com.planka.codex-daemon.acme`
3. Убедиться, что current profile не затронут и его labels не удалены.

### Rollback
1. Если проблема только в конфигурации new project, остановить только новый profile.
2. Сохранить логи и snapshot из `.tmp/codex/acme`.
3. Исправить `.tmp/codex/profiles/acme.env`.
4. Повторить `profile_init install --profile acme` и затем `profile_init preflight --profile acme`.
5. Если перенос отменяется полностью:
   - оставить current project как единственный рабочий контур;
   - удалить только labels и state-dir нового профиля;
   - не менять `default` profile и его `.tmp/codex`.

## Troubleshooting

### `PREFLIGHT_READY=0`
Причина:
- не заполнены обязательные поля в env;
- не указан `GH_APP_INTERNAL_SECRET` и не включен fallback;
- для non-default profile отсутствует часть `PROJECT_*`.

Что делать:
1. Проверить вывод `CHECK_FAIL ...` из `profile_init preflight/install`.
2. Дополнить `.tmp/codex/profiles/<profile>.env`.
3. Повторить `profile_init install --profile <profile>`.

### `Non-default Project profile requires explicit PROJECT_ID, PROJECT_NUMBER and PROJECT_OWNER`
Причина:
- для `PROJECT_PROFILE != default` указан неполный binding.

Что делать:
1. Заполнить все три переменные.
2. Не смешивать `PROJECT_PROFILE=acme` с default-значениями только одной-двух переменных.

### `Resource not accessible by integration`
Причина:
- GitHub App не имеет write-доступа к Project v2;
- installation не обновлен после смены permissions;
- используется user-owned Project без hybrid token.

Что делать:
1. Проверить permissions и installation по `docs/gh-app-daemon-integration-plan.md`.
2. Для user-owned Project задать `DAEMON_GH_PROJECT_TOKEN`.
3. Перезапустить профиль и повторить smoke.

### `NOT_INSTALLED` или `INSTALLED_NOT_LOADED`
Причина:
- launchd plist не установлен или не загружен.

Что делать:
1. Повторить `profile_init install --profile <profile>`.
2. Проверить уникальность labels.
3. Проверить, что `~/Library/LaunchAgents/<label>.plist` создается без конфликта.

### Snapshot и fixed files попадают не в тот проект
Причина:
- не выставлен `DAEMON_GH_ENV_FILE` или перепутан `<state-dir>`.

Что делать:
1. Сверить `CODEX_STATE_DIR/FLOW_STATE_DIR` с profile env-файлом.
2. Повторять команды через явный префикс:
   `env DAEMON_GH_ENV_FILE=... CODEX_STATE_DIR=... FLOW_STATE_DIR=... scripts/codex/run.sh ...`
3. Убедиться, что `commit_message.txt`, `pr_body.txt` и остальные fixed files лежат в нужном `<state-dir>`.

### Watchdog перезапускает не тот daemon
Причина:
- `WATCHDOG_DAEMON_LABEL` указывает на чужой профиль.

Что делать:
1. Проверить значение в env-файле профиля.
2. Переустановить watchdog через `profile_init install`.

### `WAIT_AUTH_SERVICE` или проблемы с `gh_app_auth_token.sh`
Причина:
- auth-сервис недоступен;
- неверный `GH_APP_INTERNAL_SECRET`;
- некорректные `GH_APP_*` параметры.

Что делать:
1. Проверить `scripts/codex/run.sh gh_app_auth_pm2_health`.
2. Проверить `GH_APP_INTERNAL_SECRET` и сетевые параметры.
3. Для аварийного окна включить fallback-token pair и повторить install/preflight.

### Новый проект блокируется на dirty worktree
Причина:
- tracked-файлы изменены до старта daemon-flow.

Что делать:
1. Очистить tracked changes или оформить их в отдельную дельту.
2. Только после этого повторять smoke/cutover.

## Стратегия выноса `scripts/codex` в отдельный toolkit-repo

### Когда выносить
Вынос имеет смысл после выполнения всех условий:
1. Flow-комплект подтвержден минимум на двух consumer-проектах с разными `GITHUB_REPO` и `PROJECT_*`.
2. Bootstrap нового profile проходит без ручной правки install/uninstall-скриптов.
3. Multi-project smoke и rollback воспроизводимы по этому runbook.
4. Repo-specific defaults сведены к env/templates/docs, а не размазаны по bash-логике.

Пока хотя бы одно условие не выполнено, преждевременный extraction только усложнит поддержку.

### Что должно переехать в toolkit-repo
1. Портируемые bash-скрипты и Node-сервисы из `scripts/codex`.
2. Общий env resolver и profile bootstrap.
3. Runbook, smoke-checklists и шаблоны env/profile.
4. Минимальный consumer-adapter слой с repo-specific defaults.

### Что должно остаться в consumer-repo
1. Значения `GITHUB_REPO`, `PROJECT_*`, токены и секреты.
2. Consumer-specific docs, issue templates и narrative вокруг конкретного продукта.
3. Локальные thin-wrapper'ы для обратной совместимости, если команда уже использует `scripts/codex/run.sh`.

### Рекомендуемая схема extraction
1. Сначала внутри PLANKA выделить repo-specific defaults в templates/env-слой.
2. Создать `toolkit-repo` со структурой:
   - `bin/` или `scripts/` для entrypoints;
   - `lib/` для shared bash helpers;
   - `services/` для Node-процессов;
   - `docs/` для runbook;
   - `templates/` для profile env и consumer bootstrap.
3. В consumer-repo оставить только:
   - pinned toolkit snapshot;
   - env-файлы проекта;
   - thin-wrapper `scripts/codex/run.sh`, если нужен совместимый entrypoint.
4. После extraction проверить тот же smoke из этого runbook уже на toolkit-based installation.

### Версионирование toolkit-repo
Рекомендуемый режим:
1. До стабилизации API команд использовать `0.y.z`.
2. После подтверждения совместимости на двух и более consumer-repo перейти на semver `1.x.y`.
3. `patch` — doc fixes, безопасные bugfix.
4. `minor` — новые команды/env без ломки текущих сценариев.
5. `major` — изменения CLI, state layout, обязательных env или формата fixed files.

### Обновления в consumer-repo
1. Пиновать toolkit на конкретный git tag, а не на плавающую ветку.
2. Обновление делать отдельным PR:
   - поднять новую toolkit-версию;
   - прогнать `profile_init preflight`;
   - прогнать smoke нового и текущего профиля;
   - обновить consumer docs, если поменялись env/команды.
3. Не смешивать toolkit-update с продуктовой функциональностью.
4. При регрессии откатываться на предыдущий tag без ручного cherry-pick по отдельным скриптам.

## Критерий готовности extraction phase
Extraction можно считать готовым к отдельному PR/проекту, когда:
1. runbook отсюда выполняется без неявных PLANKA-specific предположений;
2. portable toolkit имеет pinned release и changelog;
3. consumer-repo умеет обновлять toolkit отдельной воспроизводимой процедурой;
4. rollback toolkit-version не затрагивает product changes consumer-repo.
