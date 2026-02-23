# GitHub App + Daemon Integration Plan

## Цель
Перевести daemon/watchdog с пользовательского PAT на GitHub App, чтобы:
- GitHub-активность автоматики шла от `app-name[bot]`;
- уменьшить риски доступа (короткоживущие installation tokens);
- сохранить текущий flow `Backlog -> Todo -> In Progress -> Review -> Done`.

## Архитектура
1. Локальный auth-сервис (Node.js) получает installation token GitHub App.
2. Daemon/Watchdog берут токен у локального сервиса перед GitHub-операциями.
3. Токен живет коротко, сервис обновляет его заранее.
4. Fallback: если App-сервис недоступен, можно временно включить `DAEMON_GH_TOKEN`.

## Шаги в GitHub UI
1. Создать GitHub App (`Settings -> Developer settings -> GitHub Apps`).
2. Выдать минимальные permissions:
- Repository `Issues: Read & write`
- Repository `Pull requests: Read & write`
- Repository `Metadata: Read-only`
- Repository `Contents: Read-only` (или выше, если потребуется)
- Project/Projects permissions для Project v2 с правом редактирования (если доступны в UI)
3. Установить App на owner/repo `justewg/planka`.
4. Проверить доступ App к Project v2 (карточки/поля/статусы).
5. Скачать private key `.pem`.

## Локальная конфигурация
Добавить в `.env`:
- `GH_APP_ID=...`
- `GH_APP_INSTALLATION_ID=...`
- `GH_APP_PRIVATE_KEY_PATH=...`
- `GH_APP_OWNER=justewg`
- `GH_APP_REPO=planka`
- `GH_APP_BIND=127.0.0.1`
- `GH_APP_PORT=8787`
- `GH_APP_INTERNAL_SECRET=...`
- `GH_APP_TOKEN_SKEW_SEC=300`

Опционально аварийный fallback:
- `DAEMON_GH_TOKEN=...`

## Мини-сервис (Node.js)
### Обязательные endpoint-ы
1. `GET /health`
2. `GET /token` (защищен `X-Internal-Secret`)

### Требования
1. Кэшировать installation token в памяти.
2. Обновлять токен заранее (`expires_at - skew`).
3. Не логировать токены/ключи.
4. Слушать только `127.0.0.1`.
5. Возвращать диагностические коды ошибок, понятные daemon/watchdog.

## Интеграция в daemon/watchdog
1. Добавить шаг получения `GH_TOKEN` из auth-сервиса перед GitHub-вызовами.
2. При ошибке auth-сервиса:
- не выполнять GitHub-мутирующие действия;
- писать `WAIT_AUTH_SERVICE` в state/detail;
- отправлять сигнал в Telegram, если доступен.
3. Сохранить fallback на `DAEMON_GH_TOKEN` (feature flag).

## PM2
1. Поднять auth-сервис под `pm2` с авто-рестартом.
2. Вынести логи в отдельные файлы.
3. Добавить health-check команду.

## Риски
1. `Resource not accessible by integration` для Project v2.
2. Нехватка scopes/permissions при установке App.
3. Ошибки ротации токена (протухание, недоступность auth-сервиса).

## Критерии приемки
1. Комментарии в Issue от `app-name[bot]`.
2. PR create/edit от `app-name[bot]`.
3. Обновление статусов Project от `app-name[bot]`.
4. Daemon работает >65 минут без auth-сбоев.
5. При недоступном auth-сервисе daemon корректно уходит в ожидание и сигнализирует.

## Разбиение на задачи (для Project)
1. `APP-01` Создать GitHub App и выдать permissions.
2. `APP-02` Установить App на repo/project и проверить доступы.
3. `APP-03` Поднять Node.js auth-сервис (JWT + installation token).
4. `APP-04` Подключить daemon/watchdog к auth-сервису.
5. `APP-05` Добавить fallback-режим и деградационные сигналы.
6. `APP-06` Добавить запуск/мониторинг auth-сервиса через PM2.
7. `APP-07` Провести интеграционный smoke-test полного flow.
