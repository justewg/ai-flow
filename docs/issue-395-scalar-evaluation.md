# ISSUE-395: оценка Scalar для web-docs

## Контекст

- Текущий публичный контур flow web-docs в PLANKA уже ушёл от `redocly preview`: после обновления `main` мы собираем статический HTML и публикуем его через `nginx`.
- Вопрос задачи: может ли Scalar заменить этот контур без повторения проблем с dev-режимом Readocly и без потери self-hosted схемы публикации.
- Дата проверки внешних источников: `2026-03-14`.

## Что проверено

1. `Scalar Docs` как продукт для многостраничной документации на Markdown + OpenAPI.
2. `Scalar API Reference` как отдельный движок для OpenAPI-референса.
3. Варианты self-hosted / server / static-hosting.
4. Наличие dev-only поведения, похожего на проблемный сценарий с Readocly preview.

## Вывод

### 1. Scalar Docs не выглядит drop-in заменой текущему `nginx`-контуру

- Официальный starter для Docs предлагает локальный `npx @scalar/cli project preview`, то есть отдельный dev-сервер для предпросмотра.
- Публикация в production описана через `npx @scalar/cli project publish`, automatic deployment и preview deployments на платформу Scalar.
- В официальной документации Docs не найден задокументированный static export или self-hosted `nginx`-поток, аналогичный нашему текущему `dist/flow-docs-static`.
- Из этого следует, что для многостраничной web-документации Scalar ведёт к смене модели хостинга: вместо нашего статического контура нужен Scalar-hosted deployment с custom domain или preview deployment. Это вывод по найденным официальным сценариям, а не прямое заявление Scalar.

### 2. Scalar API Reference можно держать у себя без dev-preview в проде

- `@scalar/api-reference` можно встроить в обычный HTML-файл через CDN-скрипт и `Scalar.createApiReference(...)`.
- Есть официальные server-side интеграции для Express, Next.js и Rust, а также Docker image `scalarapi/api-reference:latest`, который сам поднимает HTTP-сервер на `8080`.
- В Rust-интеграции явно задокументировано встраивание HTML/JS assets в бинарь и выдача статических assets с сервера приложения.
- Пакет `@scalar/api-reference` экспортирует SSR entrypoint `@scalar/api-reference/ssr`, то есть при желании можно собирать HTML на своей стороне.

### 3. Признак "dev toolbar" у Scalar контролируемый и не привязан к production

- В runtime-конфигурации Scalar есть `showDeveloperTools: 'always' | 'localhost' | 'never'`.
- Значение по умолчанию: только `localhost` и другие dev-домены.
- Для production можно явно задать `showDeveloperTools: 'never'`.
- Поэтому проблема вида "в публичном контуре виден dev-режим" для Scalar API Reference не выглядит архитектурно обязательной, в отличие от попытки держать публичный контур на `redocly preview`.

## Решение для PLANKA

- Не переводить текущую многостраничную flow web-docs публикацию на `Scalar Docs` в рамках этой задачи.
- Оставить текущий self-hosted static HTML + `nginx` контур как канонический для публичной flow-документации.
- Если позже понадобится отдельно улучшить OpenAPI/reference-слой, можно делать изолированный pilot на `Scalar API Reference`, потому что этот слой реально поддерживает self-hosted HTML/server-сценарии.

## Почему решение именно такое

- Наша текущая задача решена статической публикацией после merge в `main`; она хорошо совпадает с self-hosted требованиями.
- `Scalar Docs` по официально описанному пути уводит нас в стороннюю платформу публикации, а не в локально контролируемый static export.
- `Scalar API Reference` подходит как движок для API-референса, но не закрывает как drop-in замену весь текущий pipeline flow web-docs без отдельной интеграционной работы.

## Что осталось вне scope

- Proof-of-concept в коде с встраиванием `Scalar API Reference`.
- Миграция текущего сборщика flow web-docs на новый движок.
- Сравнение визуального оформления, производительности и DX по реальному pilot-стенду.

## Источники

- PLANKA: `docs/flow-web-docs-nginx-deploy.md`
- Scalar Docs Starter Kit: <https://github.com/scalar/starter/blob/main/README.md>
- Scalar Docs Starter guide: <https://github.com/scalar/scalar/blob/main/documentation/guides/docs/starter-kit.md>
- Scalar Docs configuration: <https://github.com/scalar/scalar/blob/main/documentation/guides/docs/configuration/scalar.config.json.md>
- Scalar Docs CLI publish: <https://github.com/scalar/scalar/blob/main/documentation/guides/docs/deployment/cli.md>
- Scalar Docs automatic deployment: <https://github.com/scalar/scalar/blob/main/documentation/guides/docs/deployment/automatic-deployment.md>
- Scalar Docs preview deployments: <https://github.com/scalar/scalar/blob/main/documentation/guides/docs/deployment/preview-deployments.md>
- Scalar HTML/JS integration: <https://github.com/scalar/scalar/blob/main/documentation/integrations/html-js.md>
- Scalar Express integration: <https://github.com/scalar/scalar/blob/main/documentation/integrations/express.md>
- Scalar Docker image: <https://github.com/scalar/scalar/blob/main/documentation/integrations/docker.md>
- Scalar Rust integration: <https://github.com/scalar/scalar/blob/main/documentation/integrations/rust.md>
- Scalar runtime configuration: <https://github.com/scalar/scalar/blob/main/documentation/configuration.md>
- SSR entrypoint `@scalar/api-reference/ssr`: <https://github.com/scalar/scalar/blob/main/packages/api-reference/src/ssr.ts>
