# Flow Toolkit Packaging

> Целевой layout для отдельной flow-repo/submodule: `.flow/shared/{scripts,docs}`.

## Зачем нужен этот документ
Нужно решить две практические задачи:
- какой комплект файлов переносить в новый проект уже сейчас;
- как вынести automation в отдельный подключаемый git-репозиторий без боли для consumer-project.

## Короткий ответ

### Что переносить сейчас
Минимальный переносимый комплект:
- `.flow/shared/scripts/`
- `.flow/shared/docs/`
- `COMMAND_TEMPLATES.md`

Опционально, если используете соответствующие части:
- `.flow/shared/docs/ops-bot-dashboard.md`
- `docs/issue-69-auth-service-pm2.md`
- `docs/self-hosted-runner-deploy.md`

### Что не переносить как часть toolkit
- `.env`, `.env.deploy`, secrets, токены
- `.flow/state/codex/`
- `.tmp/codex/`, если он есть: это только legacy compatibility layer, а не часть канонического toolkit-layout
- repo-specific product docs
- consumer-specific thin wrappers и narrative, если они чисто продуктовые

Уточнение:
- repo-level GitHub workflows не являются ядром toolkit;
- но migration kit может переносить snapshot `.github/workflows/` и `.github/pull_request_template.md` как overlay исходного consumer-project;
- вместе с overlay переносится только manifest required secrets, но не их значения.

Допустимое исключение для migration kit:
- безопасный шаблон `.flow/config/flow.sample.env` без живых секретов
- `.flow/tmp/migration_kit_manifest.env` как временный descriptor распакованного kit
- `.flow/templates/github/` как source overlay для `.github/workflows/` и `.github/pull_request_template.md`
- `.flow/templates/github/required-files.txt`
- `.flow/templates/github/required-secrets.txt`

### Рекомендуемая стратегия
Рекомендуемый путь:
1. держать toolkit в отдельном repo;
2. подключать его в consumer-repo как git-submodule `/.flow/shared`;
3. вызывать команды только через `/.flow/shared/scripts/run.sh`;
4. runtime state/logs/launchd оставлять вне git consumer-repo.

## Что должно считаться toolkit-ядром

### Обязательное ядро
Переносится целиком:
- `.flow/shared/scripts/run.sh`
- все shell-скрипты из `.flow/shared/scripts/`
- `.flow/shared/scripts/env/resolve_config.sh`
- `.flow/launchd/` как каноническое место для генерируемых plist
- `.flow/tmp/` как место для временных toolkit-артефактов
- Node-сервисы:
  - `.flow/shared/scripts/gh_app_auth_service.js`
  - `.flow/shared/scripts/ops_bot_service.js`
- PM2 ecosystem файлы:
  - `.flow/shared/scripts/gh_app_auth_pm2_ecosystem.config.cjs`
  - `.flow/shared/scripts/ops_bot_pm2_ecosystem.config.cjs`

Практически это означает: переносить надо весь каталог `.flow/shared/scripts`, а не выбирать файлы по одному.

### Документация toolkit
Должна жить рядом с toolkit:
- `.flow/shared/docs/flow-onboarding-checklist.md`
- `.flow/shared/docs/flow-onboarding-quickstart.md`
- `.flow/shared/docs/flow-portability-runbook.md`
- `.flow/shared/docs/gh-app-daemon-integration-plan.md`
- `.flow/shared/docs/github-actions-repo-secrets.md`
- `.flow/shared/docs/flow-toolkit-packaging.md`

### Опциональные модули
Подключаются только если нужны:
- ops-bot/dashboard
- remote status/summary push
- self-hosted deploy runbook

## Что должно оставаться в consumer-project
- env-файлы конкретного проекта
- значения `GITHUB_REPO`, `PROJECT_ID`, `PROJECT_NUMBER`, `PROJECT_OWNER`
- токены, secrets, ключи
- `.flow/state/codex/<profile>`
- deploy-цепочки, secrets values и runner-координаты, даже если сами workflow snapshot-ом перенесены из source-project
- consumer-specific README / docs / issue templates

Если перенос делается через `migration_kit.tgz`, в него можно включать только шаблоны:
- `.flow/config/flow.sample.env` как единый безопасный шаблон flow-конфига consumer-project
- `.flow/tmp/migration_kit_manifest.env` как временный descriptor применяемого kit
- `.flow/templates/github/` для repo workflow overlay
- `.flow/templates/github/required-files.txt` и `.flow/templates/github/required-secrets.txt` как manifests

## Варианты подключения toolkit

### Вариант 1. Просто копировать snapshot в repo
Как выглядит:
- toolkit-файлы лежат прямо в consumer-repo;
- обновление делается ручным copy/rsync/cherry-pick.

Плюсы:
- самый простой старт;
- нет дополнительных git-механик;
- Codex/IDE видят файлы как обычную часть repo.

Минусы:
- тяжело обновлять несколько consumer-проектов;
- история toolkit размазывается по продуктовым PR;
- сложнее rollback toolkit-version.

Когда подходит:
- для разового bootstrap/миграционного архива;
- когда submodule по организационным причинам пока нельзя подключить.

### Вариант 2. `git submodule`
Как выглядит:
- consumer-repo содержит ссылку на отдельный toolkit-repo.

Плюсы:
- чистая граница между toolkit и продуктом;
- точный pin на commit.

Минусы:
- отдельный `git submodule update --init --recursive`;
- в CI/на новой машине нужен явный шаг инициализации submodule.

Вывод:
- это канонический способ подключения toolkit для consumer-repo.

### Вариант 3. `git subtree`
Как выглядит:
- toolkit живёт в отдельном repo;
- в consumer-repo он встраивается как обычная папка, но обновляется через subtree.

Плюсы:
- в рабочем дереве consumer-repo toolkit выглядит как обычные файлы;
- нет дополнительного шага init, как у submodule;
- удобно делать отдельные PR на обновление toolkit;
- легко пиновать на tag/commit.

Минусы:
- история merge чуть тяжелее;
- требуется дисциплина в update-процедуре.

Вывод:
- допустимый fallback, если submodule недоступен организационно.

### Вариант 4. package manager
Как выглядит:
- toolkit ставится как npm/pip/brew/и т.д. пакет.

Почему пока не подходит:
- toolkit состоит не только из бинаря, но и из bash-скриптов, env-логики, сервисов, docs и consumer-facing wrapper-пути;
- текущая модель ожидает наличие файлов в repo;
- это добавит packaging-complexity раньше времени.

Вывод:
- пока не рекомендую.

## Рекомендация по этапам

### Этап A. Сейчас
- держать toolkit в отдельном repo;
- подключать его в consumer-repo как `/.flow/shared` submodule;
- repo/project-binding держать только в env consumer-проекта.

### Этап B. Для bootstrap без submodule
- использовать `migration_kit.tgz` как snapshot toolkit + repo overlay;
- после bootstrap по возможности переходить на submodule, чтобы обновления toolkit не размазывались по продуктовым PR.

## Рекомендуемый consumer layout

### Канонический consumer layout
- `.flow/shared/` — git-submodule toolkit repo
- `.flow/shared/scripts/...`
- `.flow/shared/docs/...`
- `.flow/config/flow.env`
- `.flow/state`, `.flow/logs`, `.flow/launchd` — runtime-артефакты проекта

## Update policy для toolkit
- toolkit пиновать на tag, не на плавающую ветку;
- обновлять отдельным PR;
- не смешивать toolkit update с продуктовой фичей;
- после update обязательно прогонять:
  - `profile_init preflight`
  - `github_health_check`
  - `status_snapshot`
  - smoke `Todo -> In Progress`

## Migration checklist в отдельный toolkit-repo
- [ ] repo-specific defaults вынесены в env/templates/docs
- [ ] новый проект подключается без ручной правки bash-логики
- [ ] smoke воспроизводим минимум на двух consumer-repo
- [ ] changelog toolkit отделён от changelog продукта
- [ ] есть pinned release/tag
- [ ] rollback toolkit-version воспроизводим отдельным PR

## Итоговая рекомендация
Если нужен практический ответ “что делать сейчас”:

1. Переносить toolkit целиком как `/.flow/shared`.
2. Не дробить toolkit по отдельным shell-файлам.
3. Подключать consumer-проекты через git-submodule.
4. Для временного bootstrap использовать `migration_kit.tgz`.
5. Все команды вызывать только через `/.flow/shared/scripts/run.sh`.
