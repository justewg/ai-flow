# PLANKA Flow Docs

Это каноническая web-поверхность по flow для PLANKA. Она не живет как отдельный ручной артефакт: страницы собираются из markdown-источников репозитория, changelog и diagram-схем, а публикация запускается автоматически после обновления `main`.

## Что покрывает этот слой

- бизнес-цели и рамки flow;
- архитектуру платформенного решения и runtime-компоненты;
- процессные диаграммы и канонические переходы `Issue -> development -> PR -> main`;
- онбординг, configurator, migration/init и supported scenarios;
- ops, troubleshooting, approve/noise-политику, runtime state и логи;
- последние flow-изменения по `CHANGELOG.md`.

## Навигация

- [Цели и рамки](./platform/overview.md)
- [Архитектура](./platform/architecture.md)
- [Runtime-компоненты](./runtime/components.md)
- [Процессы и диаграммы](./runtime/processes.md)
- [Онбординг нового проекта](./adoption/onboarding.md)
- [Конфигуратор и entrypoint-команды](./adoption/configurator.md)
- [Migration и init](./adoption/migration.md)
- [Ops и troubleshooting](./operations/troubleshooting.md)
- [Политики и supported scenarios](./reference/policies.md)
- [Source mapping](./reference/source-mapping.md)
- [Последние изменения](./releases/index.md)

## Правила слоя

1. Источник правды остается в git-репозитории.
2. Web-docs задают стабильную публичную структуру поверх существующей knowledge base, а не заменяют ее целиком.
3. Изменения во flow должны сопровождаться апдейтом либо исходного runbook, либо соответствующей канонической страницы и source mapping.

## Сборка текущего bundle

{{BUILD_METADATA_LIST}}
