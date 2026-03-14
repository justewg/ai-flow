# Flow Web Docs Source

Этот каталог хранит source layout для канонической web-документации flow.

## Что здесь лежит

- `source-map.json` — manifest разделов, sidebar и mapping repo-source -> web-docs.
- `pages/` — канонические markdown-страницы, из которых generator собирает Readocly project.

## Локальная сборка

```bash
python3 scripts/flow_docs/build_flow_docs.py \
  --output-dir .tmp/flow-docs/site \
  --static-output-dir .tmp/flow-docs/static
```

Результат:

- `.tmp/flow-docs/site/` — publishable Readocly bundle;
- `.tmp/flow-docs/static/` — статический HTML export для self-hosted `nginx`;
- `.tmp/flow-docs/scalar/` — self-hosted `Scalar API Reference` shell + `openapi.json` + upstream-server;
- `.tmp/flow-docs/site/reference/source-mapping.md` — generated mapping page;
- `.tmp/flow-docs/site/releases/index.md` — generated release delta из `CHANGELOG.md`.

## Локальная проверка

Prerequisite: `Node.js >= 20.19.0` и доступный `npx`.

```bash
npx -y @redocly/cli check-config --config .tmp/flow-docs/site/redocly.yaml
npx -y @redocly/cli preview --project-dir .tmp/flow-docs/site
```

## CI / publish

Workflow `.github/workflows/publish-flow-docs.yml`:

1. собирает bundle через `python3 scripts/flow_docs/build_flow_docs.py`;
2. валидирует `redocly.yaml`;
3. дополнительно собирает `dist/flow-docs-scalar/` для `Scalar API Reference`;
4. сохраняет `flow-web-docs-bundle` как GitHub artifact;
5. при наличии `FLOW_DOCS_DEPLOY_PATH` выкладывает статический HTML export на self-hosted runner;
6. при наличии `FLOW_DOCS_SCALAR_DEPLOY_PATH` выкладывает альтернативный Scalar visualizer на отдельный deploy-root;
7. при наличии `REDOCLY_*` secrets публикует bundle в Readocly Reunite после push в `main`.

## Secrets для publish job

- `REDOCLY_AUTHORIZATION`
- `REDOCLY_ORGANIZATION`
- `REDOCLY_PROJECT`
- `REDOCLY_MOUNT_PATH` (опционально, по умолчанию `/flow`)

## Nginx / self-hosted deploy

Для выкладки на свой сервер через self-hosted runner + `nginx`:

- repo variable `FLOW_DOCS_DEPLOY_PATH` — абсолютный deploy-root на сервере;
- repo variable `FLOW_DOCS_SCALAR_DEPLOY_PATH` — абсолютный deploy-root для альтернативного Scalar visualizer;
- runbook: `docs/flow-web-docs-nginx-deploy.md`.
- runbook для Scalar upstream: `docs/flow-web-docs-scalar-nginx-deploy.md`.
