# Бизнес-цели и рамки flow

## Для чего существует flow

Flow нужен не как набор shell-скриптов, а как управляемый контур разработки, в котором:

- GitHub Project является входной очередью и состоянием задач;
- daemon/watchdog/executor доводят задачу от `Todo` до `Review`;
- GitHub Actions закрывают post-merge шаги и публикации;
- документация, changelog и runtime-сигналы не расходятся с фактическим состоянием репозитория.

## Что считается in-scope

- очередь задач через `Status` и `Flow` в GitHub Project;
- runtime-автоматика: daemon, watchdog, executor, waiting/review режимы;
- онбординг нового consumer-project, bootstrap `.flow`, configurator и migration kit;
- ops/status слой, Telegram-сигналы и deploy/runtime runbook;
- post-merge automation для `main`, включая публикацию web-docs.

## Что остается вне этого слоя

- маркетинговый сайт;
- CMS и ручное редактирование опубликованной версии в отрыве от git;
- полная stylistic rewrite исторических markdown-файлов;
- любые сценарии, которые требуют обходить канонические entrypoint-команды toolkit.

## Принципы канонической документации

- Один repo является source of truth.
- Web-docs нормализуют навигацию и терминологию, но не подменяют исходные runbook-файлы.
- Generated sections строятся автоматически из manifest и changelog.
- Публикация привязана к production-merge в `main`, а не к ручному напоминанию.
