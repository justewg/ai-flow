# Диаграмма зависимостей APP-issues

Сгенерировано: `2026-02-24T02:04:18Z`.

Источник данных:
- Репозиторий: `justewg/planka`
- Выборка: `gh issue list --state all --limit 200`
- Найдено APP-issues: `9`

```mermaid
flowchart TD
  classDef app fill:#EAF4FF,stroke:#1D4ED8,color:#0F172A;
  classDef external fill:#F3F4F6,stroke:#6B7280,color:#111827;
  I66["APP-03 · #66 · Реализовать Node.js auth-сервис для installation token"]
  I67["APP-04 · #67 · Подключить daemon/watchdog к GitHub App auth-сервису"]
  I68["APP-05 · #68 · Добавить fallback и auth-деградационные сигналы"]
  I69["APP-06 · #69 · Поднять auth-сервис под PM2"]
  I70["APP-07 · #70 · Провести end-to-end smoke-test flow с GitHub App"]
  I71["APP-08 · #71 · Реализовать dependency-gate по Flow Meta в daemon"]
  I72["APP-09 · #72 · Генератор диаграммы зависимостей (Mermaid)"]
  I73["APP-02 · #73 · Установить GitHub App на repo/project и проверить доступы"]
  I75["APP-10 · #75 · Review-feedback loop в статусе In Review"]
  I66 --> I67
  I66 --> I69
  I66 --> I75
  I67 --> I68
  I67 --> I70
  I67 --> I71
  I68 --> I70
  I69 --> I70
  I71 --> I72
  I73 --> I66
  I75 --> I67
  class I66 app;
  class I67 app;
  class I68 app;
  class I69 app;
  class I70 app;
  class I71 app;
  class I72 app;
  class I73 app;
  class I75 app;
```

## Ошибки парсинга
- Issue #73: Depends-On содержит нераспознанный токен "APP-01 (Draft)"
