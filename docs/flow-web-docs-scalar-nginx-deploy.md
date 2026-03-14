# Flow Web Docs Scalar API Reference Through Nginx

Этот runbook описывает альтернативный self-hosted visualizer документации на базе `Scalar API Reference`.

Выбранная форма deployment для `ISSUE-397`: отдельный app-server под `node`, запущенный под deploy-user и проксируемый через `nginx` на фиксированный upstream-порт `127.0.0.1:4310`.

Важно:

- это дополнительный reference-контур, а не замена канонического `flow-web-docs` static publish;
- fallback `static HTML + nginx` остаётся рабочим и описан в `docs/flow-web-docs-nginx-deploy.md`;
- production-shell явно отключает dev-only элементы через `showDeveloperTools: 'never'`.

## Что собирает workflow

Workflow `.github/workflows/publish-flow-docs.yml` после push в `main` теперь собирает три артефакта:

- `dist/flow-docs/` — Readocly bundle;
- `dist/flow-docs-static/` — канонический static fallback;
- `dist/flow-docs-scalar/` — self-hosted `Scalar API Reference` site:
  - `index.html`
  - `scalar-config.json`
  - `openapi.json`
  - `server.mjs`
  - `build-metadata.json`

## Что добавить в GitHub Actions variables

- `FLOW_DOCS_SCALAR_DEPLOY_PATH` — абсолютный путь на сервере, например `/var/sites/planka-flow-docs-scalar`
- `FLOW_DOCS_SCALAR_DEPLOY_POST_COMMAND` — опциональная команда, которую deploy job выполнит после выкладки release

Рекомендуемый сценарий:

1. Первый старт/обновление upstream-процесса завернуть в отдельный host-level script.
2. В `FLOW_DOCS_SCALAR_DEPLOY_POST_COMMAND` указать путь к этому script.

Пример:

```bash
/usr/local/bin/planka-flow-docs-scalar-reload
```

## Layout на сервере

После первого успешного deploy:

```text
/var/sites/planka-flow-docs-scalar/
  current -> releases/<sha>
  releases/
    <sha>/
      index.html
      scalar-config.json
      openapi.json
      server.mjs
      build-metadata.json
```

При каждом deploy workflow обновляет release directory и переключает symlink `current`.
Это и есть штатный путь обновления схемы/API reference на production.

## Upstream-процесс

Минимальная команда для ручного запуска:

```bash
node /var/sites/planka-flow-docs-scalar/current/server.mjs \
  --bind 127.0.0.1 \
  --port 4310 \
  --root /var/sites/planka-flow-docs-scalar/current
```

Рекомендуется держать процесс под `pm2`.

Пример host-level helper-script `/usr/local/bin/planka-flow-docs-scalar-reload`:

```bash
#!/usr/bin/env bash
set -euo pipefail

APP_NAME="planka-flow-docs-scalar"
SITE_ROOT="/var/sites/planka-flow-docs-scalar/current"
PORT="4310"
BIND="127.0.0.1"

if pm2 describe "${APP_NAME}" >/dev/null 2>&1; then
  FLOW_DOCS_SCALAR_ROOT="${SITE_ROOT}" \
  FLOW_DOCS_SCALAR_PORT="${PORT}" \
  FLOW_DOCS_SCALAR_BIND="${BIND}" \
  pm2 restart "${APP_NAME}" --update-env
else
  FLOW_DOCS_SCALAR_ROOT="${SITE_ROOT}" \
  FLOW_DOCS_SCALAR_PORT="${PORT}" \
  FLOW_DOCS_SCALAR_BIND="${BIND}" \
  pm2 start "${SITE_ROOT}/server.mjs" \
    --name "${APP_NAME}" \
    --interpreter node \
    -- --bind "${BIND}" --port "${PORT}" --root "${SITE_ROOT}"
fi

pm2 save --force >/dev/null 2>&1 || true
```

После создания helper-script:

```bash
sudo chmod +x /usr/local/bin/planka-flow-docs-scalar-reload
/usr/local/bin/planka-flow-docs-scalar-reload
curl -fsS http://127.0.0.1:4310/health
```

Ожидаемо:

- endpoint `/health` отвечает JSON со `status: "ok"`;
- `pm2 describe planka-flow-docs-scalar` показывает процесс в статусе `online`.

## Nginx reverse proxy

Пример отдельного домена `https://flow-ref.ewg40.ru/`:

```nginx
upstream flow_docs_scalar {
    server 127.0.0.1:4310;
    keepalive 16;
}

server {
    listen 80;
    listen [::]:80;
    server_name flow-ref.ewg40.ru;

    location / {
        proxy_pass http://flow_docs_scalar;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Проверка:

```bash
sudo nginx -t
sudo systemctl reload nginx
curl -I http://flow-ref.ewg40.ru/
curl -fsS http://127.0.0.1:4310/health
```

## Ручной smoke-check после deploy

1. Merge в `main`.
2. Проверить workflow `Publish Flow Web Docs`:
   - `build_bundle`
   - `deploy_scalar_reference` (если задан `FLOW_DOCS_SCALAR_DEPLOY_PATH`)
3. На сервере проверить:
   - `readlink -f /var/sites/planka-flow-docs-scalar/current`
   - `test -f /var/sites/planka-flow-docs-scalar/current/openapi.json`
   - `curl -fsS http://127.0.0.1:4310/health`
   - `curl -fsS http://127.0.0.1:4310/openapi.json | jq '.info.title, .info.version'`
4. В браузере открыть `https://flow-ref.ewg40.ru/`.

## Локальная ручная выкладка

Если нужно проверить контур до merge:

```bash
cd /private/var/sites/PLANKA
python3 scripts/flow_docs/build_flow_docs.py \
  --output-dir .tmp/flow-docs/site \
  --static-output-dir .tmp/flow-docs/static \
  --scalar-output-dir .tmp/flow-docs/scalar

bash scripts/flow_docs/deploy_flow_docs.sh \
  --site-dir .tmp/flow-docs/scalar \
  --deploy-root /var/sites/planka-flow-docs-scalar \
  --release-id manual-smoke
```

После этого можно поднять upstream:

```bash
node /var/sites/planka-flow-docs-scalar/current/server.mjs \
  --bind 127.0.0.1 \
  --port 4310 \
  --root /var/sites/planka-flow-docs-scalar/current
```

## Rollback

Если нужно откатить только Scalar visualizer:

1. Выбрать предыдущий release:

```bash
ls -1 /var/sites/planka-flow-docs-scalar/releases
```

2. Переключить `current` на нужный release:

```bash
ln -sfn /var/sites/planka-flow-docs-scalar/releases/<old-sha> /var/sites/planka-flow-docs-scalar/current
```

3. Перезапустить upstream helper-script:

```bash
/usr/local/bin/planka-flow-docs-scalar-reload
```

4. Если проблема не в visualizer, а в reference-ветке вообще:
   использовать fallback static docs из `docs/flow-web-docs-nginx-deploy.md`.

## Ограничения

- Этот контур покрывает reference/UI-слой для runtime HTTP endpoints, но не заменяет многостраничный docs-портал.
- Browser bundle `@scalar/api-reference` загружается из version-pinned CDN (`1.34.6`). Если понадобится полностью offline/self-contained delivery без CDN, это отдельная задача.
- Если меняется upstream-порт, нужно синхронно обновить `pm2` helper-script, `FLOW_DOCS_SCALAR_DEPLOY_POST_COMMAND` и `nginx upstream`.
- `openapi.json` хранится в репозитории и приезжает на сервер через тот же deploy workflow, поэтому обновление schema не требует `redocly preview` и не зависит от Scalar-hosted publish.
