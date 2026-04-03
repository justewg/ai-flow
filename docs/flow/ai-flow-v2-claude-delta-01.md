# AI Flow v2 — дельта по вживлению Claude-фаз в текущий проектонезависимый контур

Статус: proposal delta  
Язык: русский  
Назначение: дополнительный файл к базовому описанию `AI Flow v2 Complete Reference`; предназначен для анализа и последующей постановки задач Codex CLI.

---

## 1. Назначение дельты

Этот документ **не заменяет** базовый файл-описание `AI Flow v2 Complete Reference`, а добавляет к нему архитектурную дельту по внедрению `Claude`-фаз в текущий `aiflow-v2` с сохранением **backward compatibility**, модульного переключения через конфиг и возможности быстрого отката на `Codex`. Базовый документ уже фиксирует ключевые принципы системы: GitHub как внешний интерфейс, `runtime-v2` как внутренний truth source, отделение intake от execution, bounded executor, canonical artifacts, dedup/lease/budget, phased cutover и project-agnostic дизайн. Эти принципы принимаются как инварианты и не меняются этой дельтой. fileciteturn2file0

Цель дельты — не “заменить Codex на Claude”, а встроить в `aiflow-v2` **модульную матрицу провайдеров**, где в каждом узле flow можно выбрать исполнителя:

- `codex`
- `claude`
- `auto`

Выбор должен задаваться конфигом и поддерживать безопасный откат без переписывания orchestration-ядра.

---

## 2. Инварианты, которые сохраняются

Ниже перечислены свойства базовой архитектуры, которые остаются обязательными.

### 2.1 GitHub не становится control plane

Дельта не меняет главный принцип: GitHub остаётся внешним event surface и operator-visible transport-layer, но не становится внутренним источником истины. Все дорогие решения, state transitions, dedup/budget/lease проверки и semantic business transitions по-прежнему должны проходить через `runtime-v2` и orchestrator. fileciteturn2file0

### 2.2 Executor не становится orchestrator’ом

Ни `Codex`, ни `Claude` не должны:

- самостоятельно выбирать бизнес-фазу;
- самостоятельно решать, запускать ли ещё один expensive run;
- самостоятельно менять ownership;
- самостоятельно переводить систему по semantic transitions.

Оба провайдера остаются bounded workers внутри execution contract. Это полностью согласуется с базовым принципом `Executor is not the orchestrator`. fileciteturn2file0

### 2.3 Канонические artifacts остаются едиными

В базовом описании уже закреплены canonical intake artifacts:

- `source_definition.json`
- `standardized_task_spec.json`
- `intake_profile.json`

Дельта запрещает появление provider-specific форматов на межмодульных стыках. Независимо от того, кто отработал модуль — `Codex` или `Claude` — downstream-фазы должны видеть один и тот же контракт артефактов. fileciteturn2file0

### 2.4 Phased cutover сохраняется

В базовом документе `runtime-v2` уже внедряется поэтапно через shadow/primary/reconcile model. Новая provider-модульность должна встраиваться так же поэтапно, без одномоментного разрыва с legacy shell/runtime bridge. fileciteturn2file0

---

## 3. Почему нужна именно provider-модульность

Базовый контур `AI Flow v2` уже разделяет понимание задачи (`intake`) и выполнение (`execution`), а также различает `micro`, `standard`, `human_needed`, `blocked`. Это создаёт естественную точку для подключения разных AI-провайдеров не ко всей задаче целиком, а к отдельным фазам. fileciteturn2file0

Практическая мотивация дельты:

1. `Codex` уже встроен в текущий shell/executor contour и хорошо подходит для части execution-сценариев.
2. На свободно сформулированных человеческих задачах боль концентрируется в `intake / interpretation / ask-human / review-summary`, а не только в code execution.
3. Нужна возможность быстро переключать конкретный модуль на `Claude` и так же быстро возвращать его на `Codex`, не ломая весь flow.
4. Нужна статистика по качеству и стоимости работы каждого провайдера на каждом типе модуля.

Вывод: переключение должно происходить **по модулям**, а не по всему жизненному циклу задачи.

---

## 4. Новая сущность: Provider Matrix

В `aiflow-v2` вводится новая логическая сущность: **Provider Matrix**.

Она определяет, какой AI-провайдер обслуживает конкретный модуль pipeline.

Минимальный набор модулей:

1. `intake.interpretation`
2. `intake.ask_human`
3. `planning.spec_enrichment`
4. `execution.micro`
5. `execution.standard`
6. `review.summary`

Для каждого модуля конфиг должен позволять задать:

- фиксированный провайдер: `codex` или `claude`
- автоматический выбор: `auto`
- fallback-провайдер
- лимиты времени/бюджета
- разрешён ли single fallback

---

## 5. Рекомендуемое стартовое распределение модулей

Оптимальный начальный вариант для `aiflow-v2`:

- `intake.interpretation` → `claude`
- `intake.ask_human` → `claude`
- `planning.spec_enrichment` → `claude`
- `execution.micro` → `codex`
- `execution.standard` → `codex`
- `review.summary` → `claude`

Смысл такого расклада:

- `Claude` ставится туда, где основная ценность — понимание свободной постановки, интерпретация неоднозначности, написание адекватного handoff-комментария, enrichment и operator-facing summary.
- `Codex` сохраняется там, где уже есть существующая shell-дисциплина, target-aware context slicing, micro-profile guardrails и отлаженный bounded execution contour. Базовый документ подтверждает, что execution-контур уже сильно завязан на normalized spec, worktree isolation, guardrails и deterministic envelope, поэтому замена execution сразу целиком не является обязательной целью первого этапа. fileciteturn2file0

---

## 6. Provider Router

Вводится новый слой: **Provider Router**.

### 6.1 Роль Router

Router отвечает за решение:

- какой провайдер запускается для конкретного `module`;
- почему выбран именно он;
- какой fallback допускается;
- какой budget envelope и timeout назначаются.

### 6.2 Router не принимает бизнес-решений

Router не имеет права:

- менять phase/state задачи;
- обходить dedup/budget policy;
- переводить задачу в `WAIT_HUMAN`, `DONE`, `FAILED` напрямую.

Его роль — только выбрать исполнителя модуля по конфигу и по deterministic hints.

### 6.3 Источники решения Router

Router должен опираться на:

1. конфиг `providers.yaml`;
2. task context;
3. intake/profile hints;
4. deterministic heuristics;
5. историю успехов/ошибок провайдера по данному модулю.

---

## 7. Provider Contract

Чтобы `Codex` и `Claude` были взаимозаменяемыми на стыках, вводится единый provider contract.

### 7.1 ProviderRequest

Каждый модуль должен получать унифицированный запрос вида:

- `taskId`
- `module`
- ссылки на input artifacts
- `dedupKey`
- `triggerEventId`
- timeout
- budget envelope
- side-effect permissions
- provider-local metadata

### 7.2 ProviderResult

Каждый модуль должен возвращать унифицированный ответ:

- `ok`
- `provider`
- `module`
- `status`
- ссылки на output artifacts
- `usage` (tokens / estimated cost / duration)
- `terminationReason`
- `fallbackRecommended`
- `notes`
- machine-readable error block

### 7.3 Запрет provider-specific drift

Запрещается ситуация, когда downstream-код знает, что upstream отработал `Claude` или `Codex`, и начинает ветвиться по формату output.

Если модуль выдал валидный canonical artifact, он должен быть полностью provider-agnostic.

---

## 8. Где именно Claude должен использоваться в первую очередь

### 8.1 Intake Interpretation

Это главный кандидат.

На вход модуль получает:

- issue title/body;
- reply/comment summary;
- `source_definition.json`;
- repo facts;
- project policy;
- optional previous interpretation context.

На выходе должен появляться canonical `standardized_task_spec.json` и `intake_profile.json`.

Основной выигрыш ожидается именно на свободной человеческой постановке: mixed signals, implicit scope, неструктурированные описания, комментарии с контекстом “ну ты понял”. Базовый документ уже подчёркивает, что `Executor` не должен использовать raw issue text как execution contract, и именно для этого в `v2` введён intake layer. Эта дельта усиливает этот тезис: interpretation-модуль становится provider-switchable, а наиболее предпочтительным провайдером для него назначается `Claude`. fileciteturn2file0

### 8.2 Ask Human / Human-needed Handoff

Если intake не может безопасно собрать execution-ready contract, система уже сейчас должна переводить задачу в `human_needed` или `blocked` и оставлять понятный handoff-comment. Это закреплено в базовом документе. Дельта уточняет: написание такого комментария выделяется в отдельный модуль `intake.ask_human` и по умолчанию отдается `Claude`, чтобы комментарий был:

- human-readable;
- machine-readable;
- коротким;
- конкретным;
- не “что-то не так”, а “вот что мы поняли, вот где ambiguity, вот чего не хватает для запуска”. fileciteturn2file0

### 8.3 Planning Spec Enrichment

Новый дополнительный модуль `planning.spec_enrichment` работает только после успешного intake.

Задача модуля:

- уточнить `expectedChange`;
- расширить список `checks`;
- пометить `riskFlags`;
- сузить/уточнить `candidateTargetFiles`;
- подготовить enriched spec для execution.

Этот модуль особенно полезен для `standard`-профиля.

### 8.4 Review Summary

После исполнения нужен нормализованный operator-facing summary:

- что изменено;
- какие проверки пройдены;
- какие ограничения остались;
- где есть риск;
- почему задача остановлена или переведена в review.

Этот модуль не меняет finalize-path, но даёт более качественный текст для issue/PR handoff.

---

## 9. Где Codex должен оставаться по умолчанию

### 9.1 Execution Micro

`execution.micro` по умолчанию остаётся на `Codex`, потому что в текущем контуре уже реализованы:

- intake-driven execution profile;
- micro profile guardrails;
- bounded target files;
- deterministic path через normalized spec;
- worktree isolation;
- structured execution contract.

Базовый документ прямо фиксирует, что micro profile должен работать по normalized spec и ограниченному envelope. На этой фазе уже не требуется глубокая интерпретация свободного человеческого текста, а значит выигрыш от смены провайдера на первом этапе ниже, чем стоимость интеграционного риска. fileciteturn2file0

### 9.2 Execution Standard

`execution.standard` на первом этапе также остаётся на `Codex`, но модуль становится provider-switchable.

Причина:

- сначала нужно стабилизировать provider-agnostic intake/planning outputs;
- затем накопить telemetry;
- и только после этого включать `execution.standard = auto` или `execution.standard = claude` для подмножества задач.

---

## 10. Конфигурация переключения

В `aiflow-v2` должен появиться единый конфиг провайдеров, например:

```yaml
providers:
  default: codex

  intake:
    interpretation: claude
    ask_human: claude
    fallback: codex

  planning:
    spec_enrichment: claude
    fallback: codex

  execution:
    micro: codex
    standard: codex
    fallback: codex

  review:
    summary: claude
    fallback: codex

routing:
  use_auto_router: true
  auto_router_rules:
    - when:
        task_profile: micro
      use: codex
    - when:
        task_profile: standard
        reasoning_heavy: true
      use: claude
    - when:
        ambiguous_human_text: true
      use: claude
```

Требования к конфигу:

1. переключение провайдера — только через конфиг;
2. откат — только через конфиг;
3. отсутствие изменений в state machine при смене провайдера;
4. все provider decisions должны логироваться в execution ledger.

---

## 11. Auto-router heuristics

Режим `auto` не должен быть “магией по ощущениям”. Нужны детерминированные признаки.

Минимальный набор сигналов:

- narrative-heavy issue body;
- implicit target files;
- ambiguous verbs;
- конфликтующие ограничения;
- задача похожа на повторяющийся micro-pattern;
- уже есть успешная история `Codex` по такому профилю;
- уже есть успешная история `Claude` по interpretation-подобным модулям.

Рекомендуемые правила:

- узкая задача с уже известными файлами и понятными checks → `Codex`
- свободный human text, ambiguity, неясная трактовка, handoff-comment → `Claude`
- `review.summary` → `Claude`
- `execution.micro` → `Codex`, если явно не переопределено

---

## 12. Fallback policy

Fallback должен быть ограниченным и прозрачным.

### 12.1 Когда fallback разрешён

Разрешён single fallback только если первичный provider вернул:

- инфраструктурную ошибку;
- timeout;
- невалидный schema output;
- provider-local crash;
- policy-safe malformed result.

### 12.2 Когда fallback запрещён

Fallback запрещён, если первичный provider уже честно вернул:

- `human_needed`;
- `blocked`;
- budget breach;
- явный policy stop.

Иначе система начнёт бегать по кругу между двумя моделями, вместо того чтобы честно признать нехватку входных данных.

### 12.3 Аудит fallback

Каждый fallback обязан оставлять:

- какой provider был первым;
- почему он был отклонён;
- какой provider стал fallback;
- изменился ли итоговый verdict;
- сколько это стоило.

---

## 13. Нужные новые модули и файлы

### 13.1 Новые общие сущности

Нужно добавить:

- `provider_router`
- `provider_contract`
- `provider_result_schema`
- `provider telemetry`
- `provider healthcheck`

### 13.2 Новые адаптеры

Нужно выделить отдельные адаптеры:

- `providers/codex/provider_codex_cli.*`
- `providers/claude/provider_claude_sdk.*`
- опционально `providers/claude/provider_claude_cli.*`

### 13.3 Новые provider-agnostic artifacts

Опционально можно ввести ещё один артефакт поверх базовых intake-файлов:

- `planning_enriched_spec.json`
- `review_summary.json`

Но только при условии, что это будут canonical форматы, а не provider-specific outputs.

---

## 14. Изменения в intake flow

Текущая логика intake должна быть реорганизована так, чтобы `task_standardize_spec` и `task_interpret` перестали быть “жёстко кодексовыми” шагами и стали thin wrappers над provider layer.

Новый канонический порядок:

1. `capture source definition`
2. `provider_router(module = intake.interpretation)`
3. `provider_run`
4. `schema validation`
5. `persist standardized_task_spec`
6. `persist intake_profile`
7. `optional provider_router(module = planning.spec_enrichment)`
8. `persist enriched spec`

Таким образом, downstream execution больше не знает, кто именно интерпретировал задачу.

---

## 15. Изменения в execution flow

Execution flow меняется минимально.

### 15.1 Что не меняется

Не меняются:

- worktree model;
- execution contract;
- dedup key semantics;
- lease/heartbeat policy;
- budget prechecks;
- finalize path authority;
- semantic transitions только через orchestrator.

Это всё уже является базовыми инвариантами `AI Flow v2`. fileciteturn2file0

### 15.2 Что меняется

Меняется только способ выбора AI-провайдера для модуля `execution.*`.

На первом этапе это mostly config compatibility layer. На следующем — возможность перевести `execution.standard` в `auto` без переписывания flow.

---

## 16. Изменения в observability

Базовый документ уже требует structured observability, execution ledger, incident ledger, explicit state transitions и failure categories. Дельта добавляет обязательную provider-telemetry. fileciteturn2file0

Минимум нужно логировать:

- `module`
- выбранный `provider`
- `fallback_used`
- длительность
- input/output tokens
- estimated cost
- schema valid / invalid
- verdict
- provider error class
- operator override

Дополнительно полезно иметь:

- success rate по модулю и провайдеру;
- average clarification quality для `ask_human`;
- долю случаев, когда `Claude` снизил ложный `human_needed`;
- долю случаев, когда `Codex` лучше отработал узкий execution.

---

## 17. Новые failure classes

К уже перечисленным failure classes нужно добавить provider-specific категории:

- `provider_output_schema_invalid`
- `provider_timeout`
- `provider_transport_error`
- `provider_budget_exceeded`
- `provider_fallback_exhausted`
- `provider_selection_misroute`

Каждая должна иметь:

- machine-readable reason;
- human-readable explanation;
- expected next action;
- запись в audit/incident ledger.

---

## 18. План внедрения по этапам

### Этап 1. Provider abstraction

Внедрить:

- `provider contract`
- `provider router`
- `providers.yaml`
- `codex adapter`
- `claude adapter`

На этом этапе behaviour может ещё полностью повторять текущий Codex-path, но через новый router.

### Этап 2. Claude intake

Переключить:

- `intake.interpretation = claude`
- `intake.ask_human = claude`
- `review.summary = claude`

`execution.*` оставить на `Codex`.

### Этап 3. Claude planning

Добавить:

- `planning.spec_enrichment = claude`

Execution всё ещё можно оставить на `Codex`.

### Этап 4. Selective standard execution routing

Включить:

- `execution.standard = auto`

Но только для задач, удовлетворяющих детерминированным условиям маршрутизации.

### Этап 5. Data-driven optimization

По данным telemetry решить:

- какие классы задач навсегда оставить на `Codex`;
- какие классы задач лучше стабильно отдавать `Claude`;
- где `auto-router` действительно окупается.

---

## 19. Что считать успехом этой дельты

Дельта считается успешно реализованной, если одновременно верно следующее:

1. провайдер на каждом модуле меняется конфигом;
2. откат на `Codex` делается конфигом;
3. canonical artifacts не зависят от провайдера;
4. ambiguous human tasks заметно лучше нормализуются на intake;
5. handoff-комментарии стали понятнее и короче;
6. state machine не ветвится по provider-типу;
7. fallback не плодит циклы;
8. наблюдаемость показывает реальную стоимость и реальную пользу каждого провайдера;
9. `execution.micro` не деградировал по стабильности;
10. `AI Flow v2` остался project-agnostic и переносимым между репозиториями через конфиг.

---

## 20. Рекомендуемая постановка задач для Codex CLI

Ниже — рекомендуемый список задач, который можно давать Codex CLI как следующий рабочий backlog поверх базового референса и этой дельты.

### Задача A. Provider abstraction layer

Сделать общий provider layer для `aiflow-v2`, чтобы модули `intake`, `planning`, `execution`, `review` могли вызывать либо `Codex`, либо `Claude`, либо `auto` через единый router и единый контракт запроса/ответа.

Ожидаемый результат:

- provider-agnostic request/result schema;
- provider router;
- config-driven selection;
- execution ledger enrichment provider metadata.

### Задача B. Codex adapter extraction

Вынести текущий вызов `Codex CLI` в отдельный адаптер, чтобы его можно было использовать как модульный provider без прямой зашивки в shell-фазах.

Ожидаемый результат:

- `provider_codex_cli`;
- одинаковый contract с будущим `provider_claude`;
- отсутствие provider-specific форматов на стыках.

### Задача C. Claude adapter skeleton

Добавить адаптер `Claude` как отдельный provider-модуль, сначала хотя бы в skeleton-режиме, работающем на модулях `intake.interpretation`, `intake.ask_human`, `review.summary`.

Ожидаемый результат:

- `provider_claude_sdk`;
- JSON-only output enforcement;
- schema validation;
- telemetry hooks.

### Задача D. Intake migration to provider router

Перевести intake-фазы на provider-router так, чтобы interpretation-модуль больше не был жёстко связан с `Codex`.

Ожидаемый результат:

- `source_definition.json` создаётся как раньше;
- `standardized_task_spec.json` и `intake_profile.json` создаются через выбранный provider;
- downstream execution не знает, кто их породил.

### Задача E. Planning enrichment module

Добавить опциональный модуль `planning.spec_enrichment` для нормализованного enriched-spec после intake.

### Задача F. Review summary module

Добавить модуль `review.summary`, генерирующий operator-facing canonical summary.

### Задача G. Auto-router heuristics

Реализовать детерминированные признаки выбора `Codex`/`Claude` в режиме `auto`, без скрытой магии и без semantic drift.

### Задача H. Fallback policy

Реализовать single-fallback policy с полным audit trail и запретом на циклическую гонку между двумя провайдерами.

### Задача I. Provider telemetry and incident classes

Расширить observability так, чтобы по каждому модулю и каждому провайдеру были видны качество, стоимость, ошибки и operator overrides.

---

## 21. Короткая формула дельты

Если сжать этот документ до одного тезиса, он звучит так:

**AI Flow v2 должен получить не “ещё одного агента”, а provider-модульность по фазам, где Claude усиливает понимание и операторскую коммуникацию, Codex сохраняет сильные execution-пути, а orchestrator и canonical state остаются едиными и неизменными.**
