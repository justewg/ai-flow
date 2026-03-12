# GitHub Actions Repo Secrets

> Канонический shared-toolkit path: `.flow/shared/{scripts,docs}`.
> Ссылки на `.flow/scripts` и `.flow/docs` ниже допустимы только как временный compatibility layer.

## Зачем нужен этот документ
`migration_kit.tgz` может перенести в новый consumer-project snapshot `.github/workflows/`, но не переносит значения GitHub Actions secrets.

Этот документ фиксирует:
- какие repo secrets ожидает текущий overlay workflow;
- куда их заводить в GitHub UI;
- что именно в них должно лежать.

GitHub UI для нового repo:
- `Settings -> Secrets and variables -> Actions`

## Обязательные repo secrets

### `DEPLOY_DEV_PATH`
Используется в:
- `.github/workflows/deploy-dev-pr.yml`

Что это:
- абсолютный путь на self-hosted runner, куда workflow выкладывает preview/development snapshot через `rsync`.

Что вписывать:
- путь на хосте deploy runner, например `/srv/www/favs-dev`

Нюанс:
- путь должен существовать или быть создаваемым пользователем runner.

### `DEPLOY_PATH`
Используется в:
- `.github/workflows/deploy-main.yml`

Что это:
- абсолютный путь на self-hosted runner, куда workflow выкладывает production/main snapshot.

Что вписывать:
- путь на хосте deploy runner, например `/srv/www/favs`

### `PROJECT_AUTOMATION_TOKEN`
Используется в:
- `.github/workflows/project-auto-close.yml`

Что это:
- GitHub PAT для post-merge Project v2 операций.

Что вписывать:
- PAT classic, которым workflow сможет вызвать `project_set_status.sh` и перевести связанные задачи в `Done`.

Минимальные scopes:
- `repo`
- `read:project`
- `project`

Рекомендуемые дополнительные scopes:
- `read:org`
- `read:discussions`

Нюанс:
- сейчас это не GitHub App token, а PAT-владелец будет автором перемещений в Project timeline.

### `TG_BOT_TOKEN`
Используется в:
- `.github/workflows/notify-telegram-issue-signals.yml`
- `.github/workflows/notify-telegram-main-merge.yml`
- `.github/workflows/notify-telegram-pr-review.yml`

Что это:
- токен Telegram-бота, через который workflow шлют уведомления.

Что вписывать:
- полный bot token вида `123456789:AA...`

### `TG_CHAT_ID`
Используется в:
- `.github/workflows/notify-telegram-issue-signals.yml`
- `.github/workflows/notify-telegram-main-merge.yml`
- `.github/workflows/notify-telegram-pr-review.yml`

Что это:
- целевой Telegram chat id, куда workflow отправляют уведомления.

Что вписывать:
- id личного чата, группы или супергруппы, куда должен писать бот

Нюанс:
- это именно `chat_id`, а не id бота из `TG_BOT_TOKEN`.

## Опциональный secret

### `DEPLOY_POST_COMMAND`
Используется в:
- `.github/workflows/deploy-dev-pr.yml`
- `.github/workflows/deploy-main.yml`

Что это:
- опциональная post-deploy команда, которую workflow выполняет после `rsync`.

Что вписывать:
- shell-команду, если после выкладки нужен reload/build/restart

Примеры:
- `docker compose up -d --force-recreate web`
- `npm run build`
- `php artisan optimize:clear`

Если не нужен:
- secret можно не создавать; workflow уже умеют пропускать этот шаг.

## Что ещё проверить кроме secrets
- self-hosted runner label `planka-deploy` в deploy workflows может потребовать адаптации под новый consumer-project;
- runner, зарегистрированный для другого repo, не появится автоматически в новом consumer-project; для нового repo нужен собственный repo-level runner или общий org-level runner;
- `DEPLOY_*` пути почти всегда project-specific;
- Telegram notify workflows можно переносить как есть, если логика уведомлений подходит новому repo;
- `PROJECT_AUTOMATION_TOKEN` должен иметь доступ к Project v2 именно нового consumer-project.

## Как использовать вместе с audit
1. Разверни kit:
   `.flow/scripts/run.sh apply_migration_kit --project <name>`
2. Открой:
   `.flow/config/root/github-actions.required-secrets.txt`
3. Для каждого имени из списка найди описание в этом документе.
4. Создай secrets в:
   `Settings -> Secrets and variables -> Actions`
5. Повтори:
   `.flow/scripts/run.sh onboarding_audit --profile <name>`

Ожидаемый результат:
- `GH_REPO_ACTIONS_SECRETS=all-required-secrets-present:<n>`
