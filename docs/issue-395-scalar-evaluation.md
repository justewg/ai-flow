# ISSUE-395: оценка Scalar для web-docs

## Контекст

- Текущий публичный контур flow web-docs в PLANKA уже не использует `redocly preview`: после merge в `main` мы собираем статический HTML и публикуем его через `nginx`.
- Вопрос задачи: может ли Scalar заменить этот контур без повторения проблем dev-preview и без отказа от self-hosted модели публикации.
- Отдельный вопрос из issue: насколько в реальности сложно поднять более "живой" production-контур документации, если мы готовы держать отдельный процесс под deploy-user и проксировать его через `nginx` на фиксированный upstream-порт.
- Дата проверки внешних источников: `2026-03-14`.

## Что проверено

1. `Scalar Docs` как продукт для многостраничной Markdown/MDX-документации.
2. `Scalar API Reference` как отдельный reference-движок.
3. Official deployment-модели: local preview, managed publish, self-hosted HTML/server/Docker.
4. Риск dev-only поведения в production.
5. Сравнение с текущей схемой `static HTML + nginx`.

## Короткий вывод

- `Scalar Docs` не выглядит полной заменой текущему self-hosted контуру PLANKA: официальный production-сценарий ведёт в Scalar-hosted publish, а не в локальный static export.
- `Scalar API Reference` выглядит реальным self-hosted вариантом: его можно поднять как статическую HTML-страницу, как middleware в своём приложении или как отдельный Docker/HTTP-сервис за `nginx`.
- Поэтому полная миграция всей многостраничной web-документации на Scalar в рамках текущей архитектуры не рекомендована.
- Но отдельный альтернативный visualizer для reference-слоя на базе `Scalar API Reference` выглядит реализуемым и не требует возврата к проблемному dev-preview контуру.

## Что показывают официальные источники

### 1. `Scalar Docs`: production-модель завязана на платформу Scalar

- Starter Kit для Docs предлагает локальный предпросмотр через `npx @scalar/cli project preview`, то есть через dev-сервер, а не через готовый статический export.
- Официальный publish-сценарий для CI описан через `npx @scalar/cli auth login --token ...` и `npx @scalar/cli project publish --slug ...`.
- В публичном getting started для Scalar Docs публикация описана как работа с проектом на `docs.scalar.com`, с Git sync, custom domains, guides и другими platform-функциями.
- В pricing/getting-started Scalar Docs представлены как platform feature c subdomain/custom domain, а не как self-hosted runtime или standalone static-site generator.
- В рамках этой проверки не найден официальный сценарий вида "build static bundle -> положить в свой `dist/` -> отдавать через свой `nginx`" для `Scalar Docs`.

Вывод: для многостраничного docs-портала `Scalar Docs` тянет за собой смену модели публикации. Это не прямой запрет на self-hosting, а инженерный вывод по официально описанным сценариям: documented prod path у Scalar идёт через их publish/platform workflow.

### 2. `Scalar API Reference`: self-hosted варианты документированы напрямую

- Для самого простого случая есть официальный HTML/JS сценарий: достаточно обычного HTML-файла, подключения `@scalar/api-reference` из CDN и вызова `Scalar.createApiReference(...)`.
- Есть официальный universal configuration object: одна и та же конфигурация работает в HTML и server-интеграциях.
- Есть официальная Express-интеграция: `app.use('/reference', apiReference({ url: '/openapi.json' }))`.
- Есть официальный Docker image:
  - `docker run -p 8080:8080 ... scalarapi/api-reference:latest`
  - конфигурация через `API_REFERENCE_CONFIG`
  - либо mount OpenAPI-документов в `/docs`
  - есть `restart: unless-stopped` и `/health`
- Есть официальный Rust crate с двумя важными свойствами:
  - можно встраивать HTML/JS assets прямо в бинарь;
  - можно отдавать собственный JS bundle URL вместо CDN.
- Есть официальные интеграции для Next.js, Fastify, Hono, Docusaurus, Django, Java и других стеков.

Вывод: `Scalar API Reference` не привязан к dev-preview и не требует Scalar-hosted publish. Это уже не гипотеза, а прямой documented capability.

### 3. Dev-only поведение у `Scalar API Reference` контролируемо

- В runtime configuration есть `showDeveloperTools: 'always' | 'localhost' | 'never'`.
- По умолчанию developer tools показываются только на `localhost` и dev-доменах.
- Для production можно явно задать `showDeveloperTools: 'never'`.
- В server-side примерах вроде Hono `proxyUrl` обычно включают условно только для development-окружения.

Вывод: проблема уровня "в production крутится dev-toolbar/dev-preview" для `Scalar API Reference` не выглядит архитектурно обязательной. В этом месте Scalar принципиально отличается от сценария, где публичный контур держится на `redocly preview`.

## Сравнение с текущим контуром PLANKA

| Вариант | Как публикуется | Где живёт runtime | Совместимость с `nginx` + fixed upstream | Оценка внедрения |
| --- | --- | --- | --- | --- |
| Текущий PLANKA web-docs | build -> `dist/flow-docs-static` -> release directory | runtime отсутствует, только static files | Полная | Уже внедрено |
| `Scalar Docs` | `project publish` / Scalar platform | managed runtime/platform Scalar | Непрямая, требует смены модели хостинга | Высокая / нежелательная |
| `Scalar API Reference` в static HTML | deploy HTML + OpenAPI file | runtime отсутствует или минимальный | Полная | Низкая |
| `Scalar API Reference` как app server | свой Node/Next/Express/Hono/Fastify процесс | наш процесс под deploy-user | Полная | Средняя |
| `Scalar API Reference` как Docker service | отдельный контейнер на `:8080` | наш контейнер под deploy-user | Полная | Низкая-средняя |

## Насколько сложно поднять production-контур на практике

Ниже оценка относится только к `Scalar API Reference`. Для `Scalar Docs` она не применима, потому что там production-модель уходит в managed publish.

### Вариант A: статический HTML-shell + OpenAPI-файл

Что нужно:

1. Сгенерировать `openapi.json` или `openapi.yaml`.
2. Положить рядом `index.html`, который вызывает `Scalar.createApiReference(...)`.
3. Отдать оба файла через существующий `nginx`.

Сложность: низкая.

Плюсы:

- почти тот же ops-контур, что и сейчас;
- не нужен отдельный процесс;
- нет dev-preview в production;
- можно оставить текущий release layout через symlink `current -> releases/<sha>`.

Минусы:

- это в первую очередь reference UI, а не полноценная многостраничная docs-CMS;
- если нужен очень кастомный shell вокруг reference, его придётся собрать отдельно.

### Вариант B: отдельный upstream-процесс под deploy-user

Что нужно:

1. Поднять маленький HTTP-сервис на Express/Next/Hono/Fastify или готовом Docker-образе Scalar.
2. Привязать его к фиксированному порту, например `127.0.0.1:8080`.
3. Настроить `nginx` как reverse proxy на этот upstream.
4. При деплое обновлять OpenAPI-конфигурацию/файлы и рестартовать процесс.

Сложность: низкая-средняя.

Почему это реалистично:

- официальный Docker-сценарий уже предполагает сервис на `:8080`;
- официальный Express/Hono/Fastify path прямо показывает server-route deployment;
- пользовательский процесс под deploy-user и стандартный `nginx` front полностью совпадает с documented shape таких интеграций.

Практический вывод для PLANKA:

- с учётом текущего операционного допущения "можем запускать и рестартовать процессы под deploy-user, а `nginx` смотрит на фиксированный upstream-порт" этот контур выглядит реализуемым без экзотики;
- это уже обычная схема "маленький docs-service за reverse proxy", а не нестабильный dev-preview.

### Вариант C: self-hosted docs-портал + Scalar как reference-встраивание

Что нужно:

1. Оставить или выбрать self-hosted shell для текстовой документации.
2. Встроить Scalar как reference page/plugin.

Сложность: средняя.

Реалистичные формы:

- Docusaurus + официальный `@scalar/docusaurus`;
- свой Next.js/React shell + `@scalar/api-reference`;
- существующий статический docs-shell + отдельная scalar reference page.

Это уже не drop-in замена текущему pipeline, но это реалистичный путь, если цель именно "визуально богаче, мобильнее, современнее", а не только "рендерить OpenAPI".

## Ограничения и инженерные оговорки

- `Scalar API Reference` решает reference/UI-слой, но не заменяет сам по себе весь многостраничный docs-site generator.
- Если в production нужен `Try it out` против отдельного backend-origin, могут понадобиться CORS-настройки или proxy-layer. Это вывод по типовой архитектуре HTTP UI, а не отдельное прямое заявление Scalar.
- В HTML/Express-примерах по умолчанию используется CDN-версия `@scalar/api-reference`; для более жёсткого self-host контроля нужно либо зафиксировать версию CDN, либо отдать собственный bundle URL. Последний путь официально подтверждён как минимум в Rust-интеграции и в server-интеграциях с custom CDN/config.
- По официальным источникам `Scalar Docs` остаётся platform-first продуктом. Поэтому даже если self-host обходной путь когда-то возможен, он не выглядит каноническим documented path для production на сегодняшний день, `2026-03-14`.

## Решение для PLANKA

### Что не рекомендуется

- Не переводить текущую многостраничную flow web-docs публикацию на `Scalar Docs` как полную замену текущего `static HTML + nginx` контура.

Причина:

- это меняет модель хостинга;
- не снимает архитектурный вопрос по self-hosted публикации;
- не даёт нам официально задокументированного static/server deployment path для всего docs-портала.

### Что можно считать реализуемым

- Отдельный альтернативный visualizer reference-слоя на `Scalar API Reference`.

Почему:

- есть официальный HTML/JS путь;
- есть официальный server path;
- есть официальный Docker path;
- dev-only элементы можно выключить в production;
- такой сервис можно поднять под deploy-user и держать за `nginx` на фиксированном upstream-порту.

### Рекомендуемый fallback

- Оставить текущий static HTML + `nginx` контур каноническим способом публикации всей flow web-документации.
- Если нужен более сильный UX/UI-слой, развивать Scalar как дополнительный reference-визуализатор, а не как полную замену текущего docs-pipeline.

## Итоговая рекомендация

1. Закрыть `ISSUE-395` решением: `Scalar Docs` не подходит как полная замена текущему public web-docs pipeline PLANKA.
2. Зафиксировать отдельное положительное решение: `Scalar API Reference` пригоден для self-hosted production-контура.
3. Если хотим улучшить внешний вид, мобильность и modern UX документации, выносить это в отдельную backlog-задачу как pilot/implementation альтернативного visualizer-слоя на Scalar.

Создан follow-up:

- `ISSUE-397` — реализация self-hosted альтернативного visualizer документации на `Scalar API Reference` (карточка заведена в Project со статусами `Backlog / Backlog`).

## Вне scope текущей задачи

- PoC в коде с новым docs-service.
- Переписывание текущего `build_flow_docs.py`.
- Миграция всех многостраничных flow pages на новый движок.
- Benchmark по производительности и Lighthouse.

## Источники

- Текущий self-hosted runbook PLANKA: <https://github.com/justewg/PLANKA/blob/main/docs/flow-web-docs-nginx-deploy.md>
- Scalar Docs Starter Kit: <https://github.com/scalar/starter/blob/main/README.md>
- Scalar Docs getting started: <https://guides.scalar.com/scalar/scalar-docs>
- Scalar Docs publish via GitHub Actions: <https://guides.scalar.com/scalar/scalar-docs/publish-scalar-projects-using-github-actions>
- Scalar pricing/features: <https://guides.scalar.com/scalar/pricing>
- Scalar API Reference getting started: <https://guides.scalar.com/products/api-references/getting-started>
- Scalar API Reference HTML/JS: <https://guides.scalar.com/scalar/scalar-api-references/integrations/htmljs>
- Scalar API Reference configuration: <https://guides.scalar.com/scalar/scalar-api-references/configuration>
- Scalar API Reference Express: <https://guides.scalar.com/scalar/scalar-api-references/integrations/express>
- Scalar API Reference Docker: <https://guides.scalar.com/scalar/scalar-api-references/integrations/docker>
- Scalar API Reference Rust: <https://guides.scalar.com/scalar/scalar-api-references/integrations/rust>
- Scalar API Reference Docusaurus: <https://guides.scalar.com/scalar/scalar-api-references/integrations/docusaurus>
- Scalar API Reference Next.js: <https://guides.scalar.com/scalar/scalar-api-references/integrations/nextjs>
- Scalar API Reference Hono: <https://guides.scalar.com/scalar/scalar-api-references/integrations/hono>
