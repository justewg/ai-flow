# Self-Hosted Runner For Deploy

Этот runbook переводит deploy workflow на self-hosted runner, запущенный прямо на сервере хостинга.

## Что изменилось в CI

- Workflow `deploy-dev-pr.yml` и `deploy-main.yml` теперь запускаются на `runs-on: [self-hosted, planka-deploy]`.
- Деплой выполняется локально на сервере через `rsync` из workspace runner в `DEPLOY_DEV_PATH`/`DEPLOY_PATH`.
- SSH-секреты для деплоя больше не используются.

## Что должно быть в Secrets

- `DEPLOY_DEV_PATH` — абсолютный путь dev-выкладки (пример: `/var/sites/planka-dev`)
- `DEPLOY_PATH` — абсолютный путь prod-выкладки (пример: `/var/sites/planka`)
- `DEPLOY_POST_COMMAND` — опционально, команда после выкладки (пример: `pm2 restart planka-ops-bot`)

## Установка runner на сервер

1. Создать отдельного системного пользователя.

```bash
sudo useradd -m -s /bin/bash gha-runner || true
```

2. Подготовить каталог runner и права.

```bash
sudo apt-get update
sudo apt-get install -y rsync curl tar
sudo mkdir -p /opt/actions-runner/planka-deploy
sudo chown -R gha-runner:gha-runner /opt/actions-runner
```

3. Установить runner от имени `gha-runner`.
   Команды download/config берутся в GitHub UI:
   `Repository -> Settings -> Actions -> Runners -> New self-hosted runner -> Linux x64`.

```bash
sudo -iu gha-runner bash
cd /opt/actions-runner/planka-deploy

# Вставить блок "Download" из GitHub UI (curl + tar).
# Затем выполнить configure с нужным label:
./config.sh \
  --url https://github.com/justewg/planka \
  --token <ONE_TIME_RUNNER_TOKEN> \
  --name planka-deploy-01 \
  --labels planka-deploy \
  --work _work \
  --unattended \
  --replace
exit
```

4. Поставить runner как сервис.

```bash
cd /opt/actions-runner/planka-deploy
sudo ./svc.sh install gha-runner
sudo ./svc.sh start
sudo ./svc.sh status
```

5. Проверить, что runner online в GitHub UI:
   `Repository -> Settings -> Actions -> Runners`.

## Права на deploy-path

Пользователь runner (`gha-runner`) должен иметь права записи в `DEPLOY_DEV_PATH` и `DEPLOY_PATH`.

Пример:

```bash
sudo mkdir -p /var/sites/planka-dev /var/sites/planka
sudo chown -R gha-runner:gha-runner /var/sites/planka-dev /var/sites/planka
```

Если нужен другой владелец каталогов, настройте group ACL так, чтобы runner мог читать/писать/удалять файлы.

Важно: каталог runner лучше держать вне deploy-path, например в `/opt/actions-runner/planka-deploy`.
Если runner уже установлен внутри `DEPLOY_PATH` (например, `/var/sites/planka/actions-runner`), deploy workflow должен исключать `actions-runner/` из `rsync --delete`, иначе прод-выкладка может ломать собственный workspace runner.

## Smoke-проверка

1. Сделать push в `development`.
2. Убедиться, что job `Deploy PR Preview to Dev Hosting` выполнен на runner `planka-deploy-01`.
3. Проверить наличие обновленных файлов в `DEPLOY_DEV_PATH`.
4. После merge в `main` проверить `Deploy Main to Hosting` и файлы в `DEPLOY_PATH`.

## Troubleshooting

- Если workflow висит в `queued`, в репозитории нет online runner с label `planka-deploy`, либо label настроен иначе.
- Если workflow падает на шаге `Explain missing self-hosted runner`, это тот же случай: GitHub API не видит подходящий runner.
- Если preflight пишет warning `Runner preflight skipped`, это нормально: стандартный `GITHUB_TOKEN` не имеет доступа к API списка repository runners. В этом случае workflow просто продолжает запуск self-hosted job без fail-fast проверки.
- Проверить наличие runner можно в `Repository -> Settings -> Actions -> Runners`.
- Проверить сервис на сервере:

```bash
cd /opt/actions-runner/planka-deploy
sudo ./svc.sh status
```

- Если runner зарегистрирован, но не матчится, убедитесь, что при `config.sh` был указан label `planka-deploy`.

## Обновление runner

Runner умеет self-update во время работы. Для ручного обновления:

```bash
cd /opt/actions-runner/planka-deploy
sudo ./svc.sh stop
sudo -iu gha-runner ./run.sh --once
sudo ./svc.sh start
```

## Откат на GitHub-hosted + SSH (если нужен)

1. Вернуть `runs-on: ubuntu-latest` в deploy workflow.
2. Вернуть SSH-steps и секреты `DEPLOY_HOST/PORT/USER/SSH_KEY/KNOWN_HOSTS`.
3. Сделать push и rerun workflows.
