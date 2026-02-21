# PL-017 - Автодеплой `main` на hosting

## Цель
После merge PR в `main` автоматически обновлять код на хосте `Ubuntu` в директории `/var/sites/planka`.

Это даст быстрый цикл проверки с мобильника/планшета по FQDN, без ручного копирования после каждого merge.

## Выбранный вариант
`GitHub Actions` + `rsync` по `SSH`.

Почему этот вариант:
- Простая эксплуатация без отдельного orchestration-слоя.
- Детерминированный trigger: `push` в `main` (то есть после принятого PR).
- Легко добавить post-deploy шаг (например, `systemctl reload nginx`), если потребуется.

## Что добавлено в репо
- Workflow: `.github/workflows/deploy-main.yml`
- Ручной fallback-скрипт: `scripts/deploy/push_main_snapshot.sh`
- Шаблон переменных: `.env.example`

## GitHub Secrets (repo settings)
Нужно заполнить:
- `DEPLOY_HOST` - хост/IP сервера
- `DEPLOY_PORT` - ssh порт (обычно `22`)
- `DEPLOY_USER` - ssh пользователь
- `DEPLOY_PATH` - путь деплоя (для этого проекта: `/var/sites/planka`)
- `DEPLOY_SSH_KEY` - приватный ключ для доступа по SSH

Опционально:
- `DEPLOY_KNOWN_HOSTS` - зафиксированный host key (предпочтительно)
- `DEPLOY_POST_COMMAND` - команда после копирования (например, reload nginx)

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
