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

## Реестр того, что должно быть на сервере

Ниже минимальный канонический набор для Linux-hosted automation.

### Пользователи и роли

- `root`:
  - только для host bootstrap, установки системных пакетов, `systemd` wiring и VPN service;
  - не используется как runtime user для `codex`, `daemon`, `watchdog`.
- runtime user, например `ewg`:
  - владелец Linux-hosted automation runtime;
  - запускает `codex`, `daemon`, `watchdog`, позже `tmux`;
  - владеет host-level `ai-flow` runtime root.
- deploy user, например `planka-deploy`:
  - отдельный контур для app deploy и self-hosted runner;
  - не является владельцем Linux-hosted automation runtime.

### Host-level каталоги

- `AI flow root`:
  - `/var/sites/.ai-flow`
- внутри него:
  - `/var/sites/.ai-flow/config`
  - `/var/sites/.ai-flow/state`
  - `/var/sites/.ai-flow/logs`
  - `/var/sites/.ai-flow/systemd`
  - `/var/sites/.ai-flow/workspaces`

Рекомендуемый владелец:

```bash
ewg:ewg
```

### Authoritative workspace

Linux-hosted automation не должна жить из deploy snapshot (`/var/sites/planka` или `/var/sites/planka-dev`).

Канонический workspace:

```bash
/var/sites/.ai-flow/workspaces/planka
```

Это полноценный git checkout c `.git` и `/.flow/shared`, из которого работают:

- `codex`
- `daemon`
- `watchdog`
- Linux-host bootstrap commands

### Host-local конфиг

Конфиг runtime должен жить вне git и вне deploy snapshot.

Канонический пример:

```bash
/var/sites/.ai-flow/config/planka.flow.env
```

Этот файл:

- не коммитится;
- не приезжает через app deploy;
- может быть создан из перенесённого локального `flow.env`, но затем нормализуется под Linux paths.

### Secrets и auth artifacts

Вне git должны лежать:

- `OPENAI_API_KEY`
- `GitHub App private key (.pem)`
- при необходимости другие host-local secrets для auth/ops contour

Рекомендуемый layout:

```bash
/home/ewg/.config/planka-automation/openai.env
/home/ewg/.secrets/gh-apps/codex-flow.private-key.pem
```

### Обязательные runtime surfaces

Для Linux-hosted automation должны быть доступны:

- VPN path до OpenAI
- `codex`
- `gh`
- `git`
- `systemctl --user`
- SSH-доступ к GitHub для clone/fetch workspace repo

## Dependencies install

Ниже базовый набор установки зависимостей для Ubuntu VPS.

### 1. Базовые системные пакеты

```bash
sudo apt update
sudo apt install -y \
  ca-certificates \
  curl \
  git \
  jq \
  openssh-client \
  ripgrep \
  tmux \
  wget
```

### 2. GitHub CLI

```bash
type -p wget >/dev/null || (sudo apt update && sudo apt-get install wget -y)
sudo mkdir -p -m 755 /etc/apt/keyrings
wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
sudo apt update
sudo apt install gh -y
```

Проверка:

```bash
gh --version
```

### 3. Node.js и npm

Если `node`/`npm` ещё не стоят, установи их любым принятым на хосте способом. Минимально нужно получить рабочие:

```bash
node --version
npm --version
```

### 4. Codex CLI

```bash
npm install -g @openai/codex
codex --version
```

### 5. SSH-доступ к GitHub

Проверка, что runtime user может читать репозитории по SSH:

```bash
GIT_SSH_COMMAND='ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new' git ls-remote git@github.com:justewg/planka.git HEAD
```

### 6. Host-level directories

Создание runtime root:

```bash
sudo mkdir -p /var/sites/.ai-flow
sudo chown -R ewg:ewg /var/sites/.ai-flow
```

### 7. OpenAI VPN path

На хосте должен быть рабочий способ поднять VPN до OpenAI.

В уже проверенном контуре используется:

```bash
~/vpn.sh start
~/vpn.sh ip
```

### 8. Host-local secret files

Примеры:

```bash
mkdir -p /home/ewg/.config/planka-automation
chmod 700 /home/ewg/.config/planka-automation

mkdir -p /home/ewg/.secrets/gh-apps
chmod 700 /home/ewg/.secrets
chmod 700 /home/ewg/.secrets/gh-apps
```

После этого отдельно размещаются:

- `/home/ewg/.config/planka-automation/openai.env`
- `/home/ewg/.secrets/gh-apps/codex-flow.private-key.pem`

## Что должно быть готово перед запуском host bootstrap

Перед `flow-host-init.sh` должны быть готовы:

- runtime user, например `ewg`;
- доступ к GitHub по SSH;
- установленный `gh`;
- установленный `codex`;
- рабочий VPN path до OpenAI;
- host-local secrets вне git;
- право создавать и владеть `/var/sites/.ai-flow` для runtime user.

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
