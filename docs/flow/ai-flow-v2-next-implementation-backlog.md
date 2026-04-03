# AI Flow v2 — следующий backlog внедрения

Статус: рабочий backlog для обсуждения до переноса в GitHub Project  
Контекст: составлен по итогам сверки

- [ai-flow-v2-complete-reference.md](/private/var/sites/PLANKA/.flow/shared/docs/flow/ai-flow-v2-complete-reference.md)
- [ai-flow-v2-claude-delta-01.md](/private/var/sites/PLANKA/.flow/shared/docs/flow/ai-flow-v2-claude-delta-01.md)
- [ai-flow-v2-claude-integration-task.md](/private/var/sites/PLANKA/.flow/shared/docs/flow/ai-flow-v2-claude-integration-task.md)
- `aiflow-v2/phases/*.md`
- `aiflow-v2/results/*.md`
- `aiflow-v2/worklog.md`
- [graphql-audit-2026-03-31.md](/private/var/sites/PLANKA/.flow/shared/docs/flow/graphql-audit-2026-03-31.md)

---

## 1. Вывод по текущему состоянию

`AI Flow v2` уже прошёл большой путь и на сегодня **не находится на нулевой стадии**.

Фактически уже сделано:

- containment, incident/execution ledgers;
- bootstrap `runtime-v2`;
- orchestrator core;
- dedup / lease / stale execution handling;
- budget/rollout policy;
- shadow store и partial primary-source cutover;
- review/wait event bridge;
- supervisor-style watchdog;
- inspection/validation harness;
- micro execution profile;
- intake artifacts;
- normalized task spec;
- intake-driven execution profile;
- executor handoff на normalized spec.

То есть базовая state-machine архитектура уже существует и partially внедрена в live runtime.

При этом `claude`-документы не противоречат этой архитектуре, но они описывают **следующий слой модульности**, а не замену текущего ядра.

Главный вывод:

1. Claude/provider integration всё ещё актуальна.
2. Но её нельзя рассматривать как “следующий единственный шаг”.
3. До полноценной provider-модульности остаётся несколько незавершённых задач именно по state-machine/control-plane.

---

## 2. Что в Claude-плане уже совместимо с текущим контуром

Из `ai-flow-v2-claude-delta-01.md` и `ai-flow-v2-claude-integration-task.md` сохраняют актуальность:

- provider matrix `codex | claude | auto`;
- provider router как отдельный слой;
- provider contract с canonical request/result;
- запрет provider-specific drift на межмодульных стыках;
- стартовая стратегия:
  - `intake.interpretation -> claude`
  - `intake.ask_human -> claude`
  - `planning.spec_enrichment -> claude`
  - `review.summary -> claude`
  - `execution.micro -> codex`
  - `execution.standard -> codex`
- fallback policy с single fallback;
- provider telemetry и failure classes;
- config-driven routing.

Это согласуется с текущим v2-контуром, потому что:

- intake artifacts уже канонизированы;
- execution contract уже отделён от raw issue body;
- execution profiles уже есть;
- bounded executor уже существует;
- `runtime-v2` уже выполняет роль state/policy слоя.

---

## 3. Что в Claude-плане требует коррекции под текущую архитектуру

Некоторые формулировки из старого claude-плана надо уточнить.

### 3.1 Уже нельзя писать “не менять state machine”

Формально в `claude-integration-task` сказано:

- orchestrator не менять
- state machine не менять
- runtime-v2 не менять

Это слишком жёстко и уже не соответствует реальному положению дел.

Правильнее так:

- не ломать текущую state machine;
- не дублировать control plane вне `runtime-v2`;
- provider layer должна встраиваться в существующую state machine;
- допустимы расширения runtime-v2 для provider telemetry, provider failure classes и provider-aware module execution.

### 3.2 Intake migration формулировать уже не как замену “старого interpret”

Сейчас intake уже существует:

- `task_capture_source_definition`
- `task_standardize_spec`
- `task_interpret`
- `micro_task_classifier` как thin wrapper над intake

Значит следующая постановка должна быть не “создать intake с нуля”, а:

- сделать provider-pluggable interpretation внутри существующего intake pipeline;
- оставить canonical artifacts теми же;
- перенести только module implementation, а не downstream contract.

### 3.3 Execution migration на Claude пока не приоритет

Из текущих результатов видно, что:

- `micro` path уже специально harden-ился;
- `standard` execution всё ещё чувствителен к runtime/GraphQL/state drift;
- основная польза от Claude ожидается не в code execution, а в understanding / ask-human / summary.

Значит `execution.standard = auto/claude` пока рано ставить в первый backlog.

---

## 4. Что ещё реально не доведено в state-machine внедрении

По phase/results и live-опыту остаются незакрытые gaps.

### 4.1 Claim path ещё не полностью event-first

Это прямо зафиксировано в `PL-100`:

- initial daemon claim path всё ещё не переведён в event-first;
- при claim legacy shell всё ещё пишет часть active-context сама.

Это важный архитектурный долг, потому что именно claim-path определяет:

- кто взял задачу;
- когда задача считается active;
- когда watchdog должна видеть executor absence как норму, а когда как stale anomaly.

### 4.2 Legacy shell всё ещё держит часть business transitions

Несмотря на progress по review/wait, система всё ещё не до конца свела legacy shell к transport/effect layer.

Остаются места, где shell:

- сама интерпретирует состояние;
- сама лечит inconsistent state;
- сама implicitly определяет next action.

### 4.3 Watchdog всё ещё shell-based, а anomaly model недостаточно structured

Это прямо видно из `PL-101` limitation:

- watchdog пока shell-based;
- richer anomaly classification ещё впереди;
- structured anomaly model в `runtime-v2` не завершён.

### 4.4 GitHub queue/read path всё ещё слишком тяжёлый

GraphQL audit показывает, что:

- daemon по-прежнему тратит слишком много GraphQL на idle/review loop;
- review resume слишком зависит от project read path;
- queue read и item resolution ещё недостаточно кэшированы.

Это не просто performance debt, а архитектурный blocker для живой системы.

### 4.5 Runtime-v2 ещё не стала полным authoritative source

Сейчас `runtime-v2` уже primary source для selected contexts, но не для всего control plane.

Следующий шаг — не переписывать всё разом, а последовательно добить:

- claim lifecycle;
- provider execution metadata;
- structured anomalies;
- terminal closures;
- task-level authoritative lifecycle.

---

## 5. Рекомендуемый порядок дальнейшей работы

Ниже backlog разбит на эпики в правильной последовательности.

Сначала:

1. закрыть ключевые state-machine gaps;
2. затем ввести provider abstraction;
3. затем подключать Claude в intake/review modules;
4. только потом думать о `execution.standard = auto`.

---

## 6. Backlog

## EPIC A — Завершение state-machine cutover

### A1. Event-first claim path

**Цель**

Убрать остаточный legacy-first claim lifecycle и сделать `runtime-v2` authoritative source для claim/active bootstrap.

**Почему сейчас**

- это явный незавершённый долг после `PL-100`;
- stale active / missing executor / SAFE freezes в живом runtime показали, что claim bootstrap остаётся хрупким.

**Что сделать**

- описать canonical event для claim;
- материализовать claim metadata в `runtime-v2`;
- убрать прямой бизнес-write `daemon_active_*` как source of truth;
- оставить legacy files только как reconcile projection;
- обновить watchdog logic под новый claim model.

**Expected outcome**

- active task появляется в legacy files только как проекция из `runtime-v2`;
- orphaned-claim cases перестают быть отдельным классом shell drift;
- watchdog видит один и тот же authoritative claim state, что и daemon.

**Dependencies**

- none; это продолжение уже внедрённого cutover.

### A2. Structured anomaly model for watchdog

**Цель**

Перенести anomaly classification из ad-hoc shell heuristics в structured `runtime-v2` model.

**Что сделать**

- определить canonical anomaly classes;
- ввести runtime representation для anomaly events;
- сделать watchdog consumer этой модели;
- ограничить watchdog действиями `freeze / stop / alert / stale-clear`.

**Expected outcome**

- меньше ложных SAFE freezes;
- понятный machine-readable reason по каждому supervisor decision;
- удобная база для operator UI и incident export.

**Dependencies**

- A1 желательно, но не строго обязательно.

### A3. Terminal lifecycle closure

**Цель**

Добить закрытие terminal states, чтобы merged/closed/stopped tasks не держали очередь и не оставляли stale runtime хвосты.

**Что сделать**

- формализовать terminal transitions;
- унифицировать closure для:
  - merged review PR
  - closed/no-merge
  - automation stop
  - already_satisfied
  - blocked
- убрать зависимость новых задач от stale review/active/wait contexts.

**Expected outcome**

- “старая задача зависла — новые не берутся” перестаёт быть частой operational проблемой.

**Dependencies**

- A1

### A4. Queue/read path hardening and GraphQL reduction

**Цель**

Сделать queue/read layer достаточно дешёвым, чтобы state machine не зависела от постоянных GraphQL лимитов.

**Что сделать**

- убрать тяжёлые fallback paths из idle tick;
- развязать review-resume от полного project scan;
- кэшировать project field metadata;
- кэшировать `task_id -> item_id`;
- ввести per-caller GraphQL audit как канонический telemetry source.

**Expected outcome**

- daemon не живёт “от лимита к лимиту”;
- review replies не подвисают из-за полного queue read;
- очередь становится устойчивее.

**Dependencies**

- none, но логичнее делать параллельно с A1-A3.

---

## EPIC B — Provider abstraction layer

### B1. Provider contract

**Цель**

Ввести канонический provider-agnostic contract для модульных AI вызовов.

**Что сделать**

- определить `ProviderRequest`;
- определить `ProviderResult`;
- определить machine-readable provider error schema;
- зафиксировать output artifact discipline;
- исключить provider-specific output formats на downstream стыках.

**Expected outcome**

- downstream code не знает, кто породил artifact: `codex` или `claude`;
- можно подключать provider router без разрыва текущего intake/execution pipeline.

**Dependencies**

- A1-A3 желательно завершить или хотя бы стабилизировать.

### B2. Provider router

**Цель**

Сделать единый module router:

- `codex`
- `claude`
- `auto`

**Что сделать**

- ввести module identifiers:
  - `intake.interpretation`
  - `intake.ask_human`
  - `planning.spec_enrichment`
  - `execution.micro`
  - `execution.standard`
  - `review.summary`
- реализовать config-driven selection;
- добавить fallback policy;
- добавить timeout/budget envelope per module.

**Expected outcome**

- provider choice становится конфигурацией, а не размазанной логикой в shell scripts.

**Dependencies**

- B1

### B3. Codex adapter extraction

**Цель**

Обернуть текущий codex execution path в provider adapter без изменения state machine.

**Что сделать**

- вынести текущий codex invocation contract в adapter;
- сохранить текущий bounded execution semantics;
- завести provider telemetry metadata.

**Expected outcome**

- текущий работающий codex path остаётся рабочим;
- он становится первым provider под новым abstraction layer.

**Dependencies**

- B1
- B2

---

## EPIC C — Claude в intake/review modules

### C1. Claude adapter skeleton

**Цель**

Подготовить минимальный Claude provider adapter без перевода execution на Claude.

**Что сделать**

- реализовать adapter с JSON-only output;
- schema validation;
- timeout/error mapping;
- telemetry hooks;
- no side effects beyond module artifact generation.

**Expected outcome**

- Claude становится технически доступным provider-ом внутри router.

**Dependencies**

- B1
- B2

### C2. Claude intake interpretation

**Цель**

Перевести `intake.interpretation` на `claude` при сохранении canonical artifacts.

**Что сделать**

- встроить provider router в существующий intake path;
- оставить `source_definition.json`, `standardized_task_spec.json`, `intake_profile.json` без смены формата;
- поддержать deterministic fallback на codex или current local interpretation path.

**Expected outcome**

- свободные человеческие задачи лучше интерпретируются;
- снижается число ложных `human_needed`;
- runtime не ломается, потому что downstream contract не меняется.

**Dependencies**

- C1
- B3
- E1
- минимальная реализация `C3`, чтобы rollout interpretation не оставил старый слабый `ask-human` path

### C3. Claude ask-human / automation-stop comment generation

**Цель**

Сделать `intake.ask_human` отдельным module surface и передать её `claude`.

**Что сделать**

- выделить provider-routed генерацию human-needed comments;
- сохранить machine tags;
- улучшить human readability;
- улучшить explanation quality:
  - что поняли
  - чего не хватило
  - что именно надо уточнить

**Expected outcome**

- operator получает сразу понятный comment, а не vague `confidence low`.

**Dependencies**

- C1
- C2 желательно, но можно и отдельно.

### C4. Review summary module

**Цель**

Выделить review-summary как отдельный provider-routed модуль и отдать его `claude`.

**Что сделать**

- после run/finalize строить machine-readable review summary artifact;
- генерировать operator-facing summary без изменения finalize authority;
- не менять PR/review state machine.

**Expected outcome**

- review comments и handoff становятся качественнее;
- summary отделяется от execution path.

**Dependencies**

- C1
- B2

**Rollout note**

- `C4` не является блокером первого Claude rollout;
- успешный ранний rollout `Claude` допустим без `review.summary`;
- это optional / nice-to-have early module.

---

## EPIC D — Planning enrichment

### D1. Planning spec enrichment module

**Цель**

Добавить отдельную post-intake фазу enrichment, не смешанную с execution.

**Что сделать**

- ввести `planning_enriched_spec.json`;
- модуль должен:
  - уточнить `expectedChange`
  - расширить `checks`
  - выделить `riskFlags`
  - сузить `candidateTargetFiles`
- запускать enrichment только после успешного intake.

**Expected outcome**

- `standard` execution получает более качественный contract;
- ambiguity снимается раньше, чем expensive execution.

**Dependencies**

- C2

---

## EPIC E — Provider telemetry, fallback and policy

### E1. Provider telemetry

**Цель**

Сделать provider behavior measurable на уровне модулей.

**Что сделать**

- логировать:
  - module
  - provider
  - fallback_used
  - duration
  - tokens
  - estimated cost
  - schema_valid
  - verdict
  - provider_error_class
- завести summary/report surfaces.

**Expected outcome**

- можно сравнивать `codex` vs `claude` не по ощущениям, а по данным.

**Dependencies**

- B1
- B2

**Rollout note**

- telemetry должна быть включена до первого production использования `Claude`;
- без `E1` нельзя считать provider rollout управляемым.

### E2. Fallback policy

**Цель**

Сделать fallback deterministic и ограниченным.

**Что сделать**

- разрешить single fallback только для transport/timeout/schema failure;
- запретить fallback на:
  - `human_needed`
  - `blocked`
  - budget breach
  - explicit policy stop;
- писать полный audit trail fallback decision.

**Expected outcome**

- provider layer не превращается в endless retry machine.

**Dependencies**

- E1

### E3. Provider failure classes in runtime-v2

**Цель**

Встроить provider-specific failure classes в общий incident/state model.

**Что сделать**

- добавить классы:
  - `provider_output_schema_invalid`
  - `provider_timeout`
  - `provider_transport_error`
  - `provider_budget_exceeded`
  - `provider_fallback_exhausted`
  - `provider_selection_misroute`
- связать их с supervisor/incident trail.

**Expected outcome**

- provider integration не живёт отдельной “серой зоной” вне runtime model.

**Dependencies**

- A2
- E1

---

## EPIC F — Auto-routing and selective expansion

### F1. Auto-router heuristics

**Цель**

Ввести controlled `auto` mode для module routing.

**Что сделать**

- использовать deterministic hints:
  - micro/small scoped known task -> codex
  - ambiguity / free-form / review summary -> claude
- логировать route reason;
- не давать auto-router менять state machine semantics.

**Expected outcome**

- `auto` становится измеримой эвристикой, а не магией.

**Dependencies**

- B2
- E1

### F2. Selective `execution.standard = auto`

**Цель**

Начать ограниченный эксперимент с `execution.standard = auto` только после накопления telemetry.

**Что сделать**

- ограничить rollout allowlist-классами задач;
- держать strict fallback policy;
- не трогать `execution.micro`, пока `standard` не докажет безопасность.

**Expected outcome**

- migration execution provider делается data-driven, а не на доверии.

**Dependencies**

- F1
- E1
- E2

---

## 7. Что не стоит брать прямо сейчас

Ниже задачи, которые выглядят привлекательными, но сейчас рано:

- полный перевод `execution.micro` на Claude;
- полный перевод `execution.standard` на Claude;
- агрессивный `auto` без provider telemetry;
- новая operator UI до закрытия claim/anomaly/GraphQL gaps;
- попытка одномоментно перевести весь legacy shell runtime на чистый provider-router without finishing state-machine cutover.

---

## 8. Рекомендуемая практическая последовательность

Оптимальный следующий порядок:

1. `A1 Event-first claim path`
2. `A2 Structured anomaly model`
3. `A3 Terminal lifecycle closure`
4. `A4 Queue/read path hardening`
5. `B1 Provider contract`
6. `B2 Provider router`
7. `B3 Codex adapter extraction`
8. `E1 Provider telemetry`
9. `C1 Claude adapter skeleton`
10. `C2 Claude intake interpretation`
11. `C3 Claude ask-human`
12. `C4 Claude review summary`
13. `D1 Planning enrichment`
14. `E2 Fallback policy`
15. `E3 Provider failure classes`
16. `F1 Auto-router heuristics`
17. `F2 Selective execution.standard auto`

---

## 9. Минимальный следующий срез

Если брать **один реально следующий slice**, а не весь backlog сразу, то он такой:

### Slice 1

- `A1 Event-first claim path`
- `A4 Queue/read path hardening`

Почему именно он:

- это уменьшит текущую operational fragility живого runtime;
- снизит зависимость от GitHub limit;
- уберёт часть ложных safe freezes;
- создаст более устойчивую базу перед provider abstraction.

### Slice 2

- `B1 Provider contract`
- `B2 Provider router`
- `B3 Codex adapter extraction`
- `E1 Provider telemetry`

Почему:

- это минимальный безопасный слой модульности;
- после него можно подключать Claude без architectural drift;
- telemetry должна уже работать до первого production-использования второго provider.

### Slice 3

- `C2 Claude intake interpretation`
- `C3 Claude ask-human`

Почему:

- именно здесь ожидается самый быстрый продуктовый выигрыш;
- execution при этом не ломается и остаётся на Codex.

`C4 Claude review summary` можно брать либо в конце Slice 3, либо сразу после него как неблокирующий early follow-up.

---

## 10. Короткий итог

На сегодня правильная трактовка такая:

- `AI Flow v2` уже имеет рабочее state-machine ядро и intake/execution separation;
- claude-provider integration актуальна, но это **следующий слой**, а не замена текущей работы;
- перед ней нужно достаточно стабилизировать несколько ключевых gaps в state-machine/control-plane, но не ждать “идеального” ядра;
- первый полезный Claude rollout должен идти не в execution, а в:
  - `intake.interpretation`
  - `intake.ask_human`
  - `review.summary`

Именно в такой последовательности дальнейшее внедрение будет и архитектурно честным, и practically полезным.

---

## 11. Уточнение по prerequisite для EPIC A

`EPIC A` остаётся верхним приоритетом, но не должен превращаться в бесконечный блокер provider integration.

Правильная формулировка prerequisite:

- `A1–A4` должны быть **достаточно стабилизированы**;
- нет критических багов в claim/anomaly/queue path;
- prod/runtime работает предсказуемо;
- но не требуется ждать полного идеального завершения всех core migration задач перед стартом `EPIC B/C`.

Разрешено:

- начинать `EPIC B` и затем `EPIC C`, когда core стабилен operationally;
- продолжать закрывать остаточные долги `EPIC A` параллельно.

Запрещено:

- откладывать provider integration до неопределённого “идеального состояния” core.
