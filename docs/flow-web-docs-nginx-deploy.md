# Flow Web Docs Through Nginx

Этот runbook описывает текущий канонический способ публиковать flow web-docs на своём сервере.

Важно: публичный контур больше не использует `redocly preview`. Workflow собирает два артефакта:

- `dist/flow-docs/` — Readocly bundle для Reunite publish;
- `dist/flow-docs-static/` — статический HTML export для self-hosted `nginx`.

## Что добавить в GitHub Actions variables

- `FLOW_DOCS_DEPLOY_PATH` — абсолютный путь на сервере, например `/var/sites/planka-flow-docs`

Больше ничего не нужно: `FLOW_DOCS_DEPLOY_POST_COMMAND` для статического контура не используется.

## Что делает workflow

Workflow `.github/workflows/publish-flow-docs.yml` после push в `main`:

1. собирает `dist/flow-docs` и `dist/flow-docs-static`;
2. сохраняет artifact `flow-web-docs-bundle`;
3. при наличии `FLOW_DOCS_DEPLOY_PATH` выкладывает `dist/flow-docs-static` на self-hosted runner с label `planka-deploy`;
4. материализует на сервере:
   - `<deploy-root>/releases/<sha>/`
   - `<deploy-root>/current -> releases/<sha>`

## Layout на сервере

После первого успешного deploy на сервере должен быть такой layout:

```text
/var/sites/planka-flow-docs/
  current -> releases/<sha>
  releases/
    <sha>/
      index.html
      platform/...
      runtime/...
      adoption/...
      operations/...
      reference/...
      releases/...
      assets/
```

## Nginx static hosting

Пример для публикации docs на отдельном домене `https://aiflow.ewg40.ru/`:

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name aiflow.ewg40.ru;

    root /var/sites/planka-flow-docs/current;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

Проверка:

```bash
sudo nginx -t
sudo systemctl reload nginx
curl -I http://aiflow.ewg40.ru/
```

## Ручной smoke-check

1. Merge в `main`.
2. Проверить workflow `Publish Flow Web Docs`.
3. На сервере проверить:
   - `/var/sites/planka-flow-docs/current/index.html`
   - `/var/sites/planka-flow-docs/releases/`
4. В браузере открыть `https://aiflow.ewg40.ru/`

## Локальная ручная выкладка

Если нужно проверить контур до merge:

```bash
cd /private/var/sites/PLANKA
python3 scripts/flow_docs/build_flow_docs.py \
  --output-dir .tmp/flow-docs/site \
  --static-output-dir .tmp/flow-docs/static

bash scripts/flow_docs/deploy_flow_docs.sh \
  --site-dir .tmp/flow-docs/static \
  --deploy-root /var/sites/planka-flow-docs \
  --release-id manual-smoke
```

После этого достаточно `nginx` с `root /var/sites/planka-flow-docs/current;`.

## Troubleshooting

- Если workflow собирает bundle, но не делает server deploy:
  - не задан `FLOW_DOCS_DEPLOY_PATH`
  - нет online self-hosted runner с label `planka-deploy`
- Если на сервере нет `current/index.html`:
  - deploy job не отработал или указал не тот `FLOW_DOCS_DEPLOY_PATH`
- Если домен отвечает 404/403:
  - проверь `root` в `nginx`
  - проверь права на `/var/sites/planka-flow-docs/current`
  - проверь, что `index.html` реально лежит в `current`
