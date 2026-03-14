# Linux-Hosted Codex API Bootstrap

## Цель

Зафиксировать проверенный сценарий запуска `codex` на Linux VPS в headless-режиме через `OpenAI API key`, без хранения секрета в репозитории и без зависимости от локального ChatGPT `auth.json`.

Этот сценарий нужен для `PL-050` и является каноническим для Linux-hosted automation.

## Что не делаем

- не кладём `OPENAI_API_KEY` в репозиторий;
- не кладём ключ в `flow.env`;
- не используем `auth.json` как основной Linux-host auth mode;
- не запускаем automation runtime под `root`, если для этого нет отдельной необходимости.

## Предпосылки

На сервере уже должны быть:

- установлен `codex`;
- рабочий checkout проекта, например `/var/sites/planka`;
- пользователь runtime, например `ewg`;
- поднятый VPN-доступ до OpenAI.

## Почему не `auth.json`

Проверенный факт:

- перенос ChatGPT login artifact (`auth.json`) на VPS не дал надёжного runtime-path и привёл к `403` на `https://chatgpt.com/backend-api/codex/responses`.

Поэтому для Linux VPS канонический auth mode:

- `codex login --with-api-key`

а не перенос локального браузерного login state.

## Где хранить ключ

Ключ хранится только вне git:

- либо в host-local env file, например `~/.config/planka-automation/openai.env`;
- либо в `systemd EnvironmentFile`;
- либо в уже существующем server-side secret storage другого проекта.

В уже проведённом smoke использовался существующий API key, ранее сохранённый на сервере в env другого проекта.

## Обязательный VPN шаг

Перед любым smoke `codex exec` на VPS нужно поднять VPN.

Команды:

```bash
~/vpn.sh start
~/vpn.sh ip
```

`~/vpn.sh ip` должен показывать внешний IP VPN-контура, а не обычный IP хоста.

Если VPN не поднят, Linux-hosted runtime надо считать неготовым.

## Канонический bootstrap

### 1. Подготовить user-owned `CODEX_HOME`

```bash
mkdir -p ~/.codex-server-api
chmod 700 ~/.codex-server-api
```

### 2. Подгрузить `OPENAI_API_KEY` из host-local secret file

Пример:

```bash
source ~/.config/planka-automation/openai.env
```

Файл должен жить вне репозитория и иметь права не шире `600`.

### 3. Выполнить login через API key

```bash
printf '%s' "$OPENAI_API_KEY" | CODEX_HOME="$HOME/.codex-server-api" codex login --with-api-key
```

### 4. Проверить статус логина

```bash
CODEX_HOME="$HOME/.codex-server-api" codex login status
```

Ожидаемый результат:

```text
Logged in using an API key - sk-proj-***
```

### 5. Прогнать smoke на реальный доступ к OpenAI

```bash
cd /var/sites/planka
CODEX_HOME="$HOME/.codex-server-api" codex exec "Ответь ровно строкой OK"
```

Ожидаемый результат:

```text
OK
```

## Проверенный smoke

На reg.ru VPS подтверждённо отработал следующий сценарий:

```bash
~/vpn.sh start
~/vpn.sh ip
CODEX_HOME="$HOME/.codex-server-api" codex login status
CODEX_HOME="$HOME/.codex-server-api" codex exec "Ответь ровно строкой OK"
```

Фактический результат:

- `codex login status` показал `Logged in using an API key`;
- `codex exec` успешно выполнился через provider `openai`.

## Следующий шаг после smoke

После этого можно переходить к:

- `systemd`-обвязке daemon/watchdog;
- host preflight для `codex`/VPN/OpenAI;
- tmux/session layout для server runtime;
- single-runtime ownership между MacBook и VPS.
