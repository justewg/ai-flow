# PL-017 - Автодеплой `main` на hosting

## Цель
После merge PR в `main` автоматически обновлять код на хосте `Ubuntu` в директории `/var/sites/planka`.

Это даст быстрый цикл проверки с мобильника/планшета по FQDN, без ручного копирования после каждого merge.

## Выбранный вариант
`GitHub Actions` + `self-hosted runner` на том же сервере + локальный `rsync`.

Почему этот вариант:
- Не зависит от внешнего SSH-доступа с GitHub-hosted runner (VPN/IP ACL больше не блокируют деплой).
- Файлы копируются локально на сервере, без сетевого hop.
- Детерминированный trigger: `push` в `main` (то есть после принятого PR).
- Легко добавить post-deploy шаг (например, `systemctl reload nginx`), если потребуется.

## Что добавлено в репо
- Workflow: `.github/workflows/deploy-main.yml`
- Workflow preview-деплоя до merge: `.github/workflows/deploy-dev-pr.yml`
- Ручной fallback-скрипт: `scripts/deploy/push_main_snapshot.sh`
- Шаблон переменных: `.env.example`
- Runbook установки self-hosted runner: `docs/self-hosted-runner-deploy.md`

## GitHub Secrets (repo settings)
Нужно заполнить:
- `DEPLOY_PATH` - путь деплоя (для этого проекта: `/var/sites/planka`)
- `DEPLOY_DEV_PATH` - путь preview-деплоя для PR (например, `/var/sites/planka-dev`)

Опционально:
- `DEPLOY_POST_COMMAND` - команда после копирования (например, reload nginx)

Обязательно:
- В репозитории должен быть online self-hosted runner с label `planka-deploy` (см. `docs/self-hosted-runner-deploy.md`).

## Локальный fallback
Можно деплоить вручную тем же механизмом:

1. Скопировать `.env.example` в `.env.deploy` и заполнить значения.
2. Запустить:

```bash
scripts/deploy/push_main_snapshot.sh
```

## Проверка после включения
1. Смержить PR в `main`.
2. Проверить `Actions` run `Deploy Main to Hosting`.
3. Открыть FQDN с мобильного/планшета и убедиться, что версия обновилась.

## Preview до merge (`PR -> main`)
- Trigger: `pull_request` (`opened`, `reopened`, `synchronize`, `ready_for_review`) в ветку `main`.
- Workflow: `Deploy PR Preview to Dev Hosting` (`.github/workflows/deploy-dev-pr.yml`).
- Деплой идет тем же локальным `rsync`-механизмом, что и прод, но в `DEPLOY_DEV_PATH`.
- Источник кода: `pull_request.head.sha` (актуальный коммит PR-ветки, до merge).
