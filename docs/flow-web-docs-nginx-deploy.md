# Flow Web Docs Through Nginx

Этот runbook описывает практичный способ публиковать flow web-docs на своём сервере.

Важно: текущий output `scripts/flow_docs/build_flow_docs.py` — это **Redocly Realm project bundle**, а не статический HTML export. Поэтому канонический серверный контур такой:

1. GitHub Actions собирает bundle.
2. Self-hosted runner выкладывает bundle в server path.
3. На сервере локально работает `redocly preview --product=realm`.
4. `nginx` проксирует публичный URL в этот локальный preview process.

## Что добавить в GitHub Actions variables

- `FLOW_DOCS_DEPLOY_PATH` — абсолютный путь на сервере, например `/var/sites/planka-flow-docs`
- `FLOW_DOCS_DEPLOY_POST_COMMAND` — опциональная команда после выкладки, например:
  `sudo systemctl restart planka-flow-docs.service && sudo systemctl reload nginx`

Дополнительно можно использовать server-side env для preview service:

- `FLOW_DOCS_PROJECT_DIR=/var/sites/planka-flow-docs/current`
- `FLOW_DOCS_PREVIEW_HOST=127.0.0.1`
- `FLOW_DOCS_PREVIEW_PORT=4410`
- `FLOW_DOCS_PREVIEW_PRODUCT=realm`

## Что делает workflow

Workflow `.github/workflows/publish-flow-docs.yml` после push в `main`:

1. собирает `dist/flow-docs`;
2. сохраняет artifact `flow-web-docs-bundle`;
3. при наличии `FLOW_DOCS_DEPLOY_PATH` выкладывает bundle на self-hosted runner с label `planka-deploy`;
4. материализует на сервере:
   - `<deploy-root>/releases/<sha>/`
   - `<deploy-root>/current -> releases/<sha>`
   - `<deploy-root>/bin/serve_flow_docs.sh`

## Установка preview service на сервере

Ниже пример `systemd` unit-а:

```ini
[Unit]
Description=PLANKA Flow Docs Preview
After=network.target

[Service]
User=gha-runner
WorkingDirectory=/var/sites/planka-flow-docs
Environment=FLOW_DOCS_PROJECT_DIR=/var/sites/planka-flow-docs/current
Environment=FLOW_DOCS_PREVIEW_HOST=127.0.0.1
Environment=FLOW_DOCS_PREVIEW_PORT=4410
Environment=FLOW_DOCS_PREVIEW_PRODUCT=realm
ExecStart=/usr/bin/env bash /var/sites/planka-flow-docs/bin/serve_flow_docs.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

После создания unit:

```bash
sudo systemctl daemon-reload
sudo systemctl enable planka-flow-docs.service
sudo systemctl start planka-flow-docs.service
sudo systemctl status planka-flow-docs.service
```

Если на сервере нет глобально установленного `redocly`, wrapper использует `npx -y @redocly/cli preview ...`. Для более предсказуемого cold start лучше заранее установить Node.js и `@redocly/cli`.

## Nginx reverse proxy

Пример для публикации docs на отдельном домене `https://aiflow.ewg40.ru/`:

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name aiflow.ewg40.ru;

    location / {
        proxy_pass http://127.0.0.1:4410/;
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
curl -I http://aiflow.ewg40.ru/
```

## Ручной smoke-check

1. Merge в `main`.
2. Проверить workflow `Publish Flow Web Docs`.
3. На сервере проверить:
   - `/var/sites/planka-flow-docs/current/redocly.yaml`
   - `systemctl status planka-flow-docs.service`
4. В браузере открыть `https://aiflow.ewg40.ru/`

## Troubleshooting

- Если workflow собирает bundle, но не делает server deploy:
  - не задан `FLOW_DOCS_DEPLOY_PATH`
  - нет online self-hosted runner с label `planka-deploy`
- Если `nginx` отвечает 502:
  - preview service не поднялся
  - неверный `FLOW_DOCS_PREVIEW_PORT`
- Если preview service падает:
  - проверь `journalctl -u planka-flow-docs.service -n 100 --no-pager`
  - проверь, что `current/redocly.yaml` существует
  - проверь наличие `node`, `npx` или глобального `redocly`
