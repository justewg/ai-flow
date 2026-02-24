# ISSUE-69 - Auth-сервис под PM2

## Цель
Запускать `gh_app_auth_service.js` под `PM2` с авто-перезапуском, отдельными логами и явной health-проверкой для операционного контура.

## Что добавлено
- PM2 ecosystem-конфиг: `scripts/codex/gh_app_auth_pm2_ecosystem.config.cjs`
- Команды-обертки:
  - `scripts/codex/run.sh gh_app_auth_pm2_start`
  - `scripts/codex/run.sh gh_app_auth_pm2_stop`
  - `scripts/codex/run.sh gh_app_auth_pm2_restart`
  - `scripts/codex/run.sh gh_app_auth_pm2_status`
  - `scripts/codex/run.sh gh_app_auth_pm2_health`
  - `scripts/codex/run.sh gh_app_auth_pm2_crash_test`
- Логи PM2 auth-сервиса:
  - `.tmp/codex/pm2/gh_app_auth.out.log`
  - `.tmp/codex/pm2/gh_app_auth.err.log`

## Операционная инструкция
### 1. Предусловия
1. Установлен `node` (рекомендуется LTS >= 18).
2. Установлен `pm2`:
   ```bash
   npm install -g pm2
   ```
3. В `.env` или `.env.deploy` заданы обязательные переменные GitHub App:
   - `GH_APP_ID`
   - `GH_APP_INSTALLATION_ID`
   - `GH_APP_PRIVATE_KEY_PATH`
   - `GH_APP_INTERNAL_SECRET`

### 2. Старт сервиса под PM2
```bash
scripts/codex/run.sh gh_app_auth_pm2_start
```

### 3. Проверка состояния и health
```bash
scripts/codex/run.sh gh_app_auth_pm2_health
```

Ожидаемо:
1. В выводе есть `PM2_STATUS=online`.
2. Endpoint `/health` возвращает JSON со `status: "ok"`.

### 4. Проверка авто-restart после падения
```bash
scripts/codex/run.sh gh_app_auth_pm2_crash_test
```

Ожидаемо:
1. В выводе есть `PM2_CRASH_TEST_OK ...`.
2. После этого выводится `AUTH_HEALTH_OK`.

### 5. Операционные команды
```bash
scripts/codex/run.sh gh_app_auth_pm2_status
scripts/codex/run.sh gh_app_auth_pm2_restart
scripts/codex/run.sh gh_app_auth_pm2_stop
```

### 6. Диагностика логов
```bash
tail -n 100 .tmp/codex/pm2/gh_app_auth.out.log
tail -n 100 .tmp/codex/pm2/gh_app_auth.err.log
```

## Критерии приемки (чек)
- [x] Auth-сервис запускается и стабильно работает под PM2 (`PM2_STATUS=online` + `gh_app_auth_pm2_health`).
- [x] Авто-перезапуск после падения подтверждается через `gh_app_auth_pm2_crash_test`.
- [x] Операционная инструкция добавлена в `docs`.
