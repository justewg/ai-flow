# AI Flow v2 — задача внедрения Claude (единый план выполнения)

## Цель
Встроить Claude как альтернативный provider в существующий aiflow-v2 без ломки архитектуры.

## Ключевая идея
Одна задача = один запуск.
Внутри — последовательные фазы с checkpoint’ами.

## Инварианты
- orchestrator НЕ менять
- state machine НЕ менять
- runtime-v2 НЕ менять
- GitHub НЕ делать control plane
- менять только слой provider/execution

---

## ФАЗА 1 — Provider abstraction

Создать:
- .flow/shared/providers/provider_contract.ts
- .flow/shared/providers/provider_router.ts

Результат:
единый интерфейс вызова провайдера

---

## ФАЗА 2 — Codex adapter

Завернуть текущий codex-cli в provider:
- provider_codex_cli.ts

Результат:
Codex работает через новый abstraction слой

---

## ФАЗА 3 — Claude adapter

Создать:
- provider_claude_sdk.ts

Требования:
- JSON-only output
- запись standardized_task_spec.json
- запись intake_profile.json

---

## ФАЗА 4 — Config routing

Создать:
.flow/config/providers.yaml

Начальные значения:
- intake.interpretation = claude
- execution.micro = codex

---

## ФАЗА 5 — Intake migration

Заменить:
task_interpret → provider_router

Результат:
Claude начинает обрабатывать свободные задачи

---

## ФАЗА 6 — Planning enrichment

Добавить фазу:
planning.spec_enrichment → claude

---

## ФАЗА 7 — Review summary

Добавить:
review.summary → claude

---

## ФАЗА 8 — Auto-router

Реализовать выбор:
- сложная задача → claude
- простая micro → codex

---

## ФАЗА 9 — Fallback

Правило:
1 попытка → fallback → стоп

---

## ФАЗА 10 — Telemetry

Логировать:
- provider
- cost
- fallback
- результат

---

## Критерии успеха

- переключение provider через config
- intake стал качественнее
- нет дублирующих execution
