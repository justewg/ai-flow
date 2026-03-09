# Flow Toolkit Packaging

## Зачем нужен этот документ
Нужно решить две практические задачи:
- какой комплект файлов переносить в новый проект уже сейчас;
- как вынести automation в отдельный подключаемый git-репозиторий без боли для consumer-project.

## Короткий ответ

### Что переносить сейчас
Минимальный переносимый комплект:
- `scripts/codex/`
- `docs/flow-onboarding-checklist.md`
- `docs/flow-onboarding-quickstart.md`
- `docs/flow-portability-runbook.md`
- `docs/gh-app-daemon-integration-plan.md`

Опционально, если используете соответствующие части:
- `docs/ops-bot-dashboard.md`
- `docs/issue-69-auth-service-pm2.md`
- `docs/self-hosted-runner-deploy.md`

### Что не переносить как часть toolkit
- `.env`, `.env.deploy`, secrets, токены
- `.tmp/codex/`
- repo-specific product docs
- конкретные GitHub workflows продукта, если они завязаны на конкретный deploy/release process
- consumer-specific thin wrappers и narrative, если они чисто продуктовые

### Рекомендуемая стратегия
Не `submodule` по умолчанию.

Рекомендуемый путь:
1. сначала стабилизировать toolkit;
2. вынести его в отдельный repo;
3. подключать в consumer-repo через `git subtree` или pinned vendor-copy;
4. оставить thin-wrapper `scripts/codex/run.sh`, если нужен совместимый entrypoint.

## Что должно считаться toolkit-ядром

### Обязательное ядро
Переносится целиком:
- `scripts/codex/run.sh`
- все shell-скрипты из `scripts/codex/`
- `scripts/codex/env/resolve_config.sh`
- Node-сервисы:
  - `scripts/codex/gh_app_auth_service.js`
  - `scripts/codex/ops_bot_service.js`
- PM2 ecosystem файлы:
  - `scripts/codex/gh_app_auth_pm2_ecosystem.config.cjs`
  - `scripts/codex/ops_bot_pm2_ecosystem.config.cjs`

Практически это означает: переносить надо весь каталог `scripts/codex`, а не выбирать файлы по одному.

### Документация toolkit
Должна жить рядом с toolkit:
- `docs/flow-onboarding-checklist.md`
- `docs/flow-onboarding-quickstart.md`
- `docs/flow-portability-runbook.md`
- `docs/gh-app-daemon-integration-plan.md`

### Опциональные модули
Подключаются только если нужны:
- ops-bot/dashboard
- remote status/summary push
- self-hosted deploy runbook

## Что должно оставаться в consumer-project
- env-файлы конкретного проекта
- значения `GITHUB_REPO`, `PROJECT_ID`, `PROJECT_NUMBER`, `PROJECT_OWNER`
- токены, secrets, ключи
- `.tmp/codex/<profile>`
- product-specific workflows и deploy-цепочки
- consumer-specific README / docs / issue templates

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
- пока toolkit ещё нестабилен;
- пока consumer-проект всего один;
- пока extraction в отдельный repo ещё не оформлен.

### Вариант 2. `git submodule`
Как выглядит:
- consumer-repo содержит ссылку на отдельный toolkit-repo.

Плюсы:
- чистая граница между toolkit и продуктом;
- точный pin на commit.

Минусы:
- отдельный `git submodule update --init --recursive`;
- выше шанс забыть инициализировать submodule в CI/на новой машине;
- больше трения для разработчиков и для automation;
- хуже ergonomics для “просто открыл repo и работай”.

Вывод:
- не рекомендую как дефолт для этого flow.

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
- это лучший кандидат для штатного подключения toolkit после стабилизации.

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
Использовать vendor-copy:
- копировать `scripts/codex/` целиком;
- рядом копировать ключевые docs;
- repo/project-binding держать только в env.

### Этап B. После 2+ consumer-проектов
Создать отдельный toolkit-repo, например:
- `codex-flow-toolkit`

Структура может быть такой:
- `scripts/codex/`
- `docs/`
- `templates/`
- `CHANGELOG.md`
- `README.md`

### Этап C. Подключение consumer-repo
Подключать toolkit в consumer-repo через `git subtree`.

Рекомендуемый layout в consumer-repo:
- `vendor/codex-flow-toolkit/` или
- `toolkit/codex-flow/`

И поверх оставить тонкий совместимый wrapper:
- `scripts/codex/run.sh`

Этот wrapper может просто проксировать вызов в vendor-путь.

## Рекомендуемый consumer layout

### Вариант с vendor-path
- `vendor/codex-flow-toolkit/scripts/codex/...`
- `vendor/codex-flow-toolkit/docs/...`
- `scripts/codex/run.sh` — thin wrapper
- `.tmp/codex/profiles/<profile>.env`

### Зачем thin wrapper
Потому что тогда:
- старые команды не меняются;
- команда продолжает вызывать привычный `scripts/codex/run.sh`;
- toolkit можно переносить/обновлять без массовой правки команды.

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

1. Сейчас переносить целиком `scripts/codex/` + 4 ключевых onboarding/reference docs.
2. Не дробить toolkit по отдельным shell-файлам.
3. Не использовать `submodule` как основной способ подключения.
4. После стабилизации вынести automation в отдельный repo.
5. Подключать этот repo в consumer-проекты через `git subtree` + thin wrapper `scripts/codex/run.sh`.
