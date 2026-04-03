# AI Flow v2 Complete Reference

## 1. Назначение

`AI Flow v2` — это self-hosted проектонезависимый контур автоматизированной разработки, в котором AI-исполнитель работает поверх GitHub `Issues + PR + Project`, но сам GitHub не считается control plane.

Система предназначена для следующего режима:

- пользователь ставит задачу через GitHub Issue и/или GitHub Project;
- daemon выбирает задачу из очереди;
- intake слой нормализует постановку;
- executor выполняет ограниченный контракт работы;
- результат оформляется в commit/PR/review-comment;
- watchdog следит за health и containment, но не принимает продуктовых решений;
- runtime/state store хранит каноническое состояние потока и не позволяет expensive-run без значимого нового события.

Это не “бот, который иногда пишет в issue”. Это stateful orchestration system с ограничениями по бюджету, ownership, дедупликации и ручному контролю.

---

## 2. Главный принцип

Ключевой архитектурный тезис:

**GitHub не является control plane системы.**

GitHub в `AI Flow v2` играет роль:

- внешнего event surface;
- хранилища задач, PR и review-обратной связи;
- интеграционного канала;
- transport-layer для operator-visible side effects.

Но внутренний truth должен жить не в GitHub, а в собственном state/runtime контуре:

- `runtime-v2` state store;
- orchestrator semantics;
- execution policy;
- budget policy;
- primary context derivation;
- reconcile layer для legacy shell/runtime.

Следствие: система не должна принимать дорогие решения только потому, что “тик увидел новый GitHub snapshot”.

---

## 3. Что именно исправляет v2 по сравнению с legacy/v1

Из подтверждённых проблем legacy/v1:

- polling-first orchestration вместо state-first/event-first модели;
- слабая идемпотентность repeated AI runs;
- повторные expensive executions по одной и той же задаче/стадии;
- отсутствие жёсткого budget containment;
- размытая граница между automation и human takeover;
- избыточная зависимость от GitHub GraphQL;
- форензика через сырые логи вместо нормализованного timeline/state.

`v2` строится так, чтобы:

- expensive execution не происходил без meaningful new event;
- duplicate execution по тому же смысловому input не запускался;
- global/project/task budgets могли остановить контур до перерасхода;
- waiting/review/active состояния были явными;
- human feedback был частью формальной state machine, а не побочным эффектом issue comments;
- GitHub rate limit не превращался в retry storm.

---

## 4. Scope системы

Проектонезависимое ядро `AI Flow v2` должно уметь работать с любым GitHub repository/profile, где есть:

- GitHub repo;
- GitHub Project v2;
- issue/PR workflow;
- локальный или серверный runtime;
- настроенный toolkit `.flow/shared`;
- профиль проекта через `flow.env` / authority env.

Система не привязана к `planka` по смыслу. Она переносима на другой репозиторий при условии, что там параметризованы:

- repo owner/name;
- project id/number;
- branch policy;
- profile/state/log paths;
- GitHub auth mode;
- optional operator integrations.

---

## 5. Основные принципы дизайна

### 5.1 Safety before automation

Сначала containment, потом orchestration richness.

Обязательные свойства:

- global stop modes;
- manual unlock;
- budget ledger;
- incident ledger;
- stale execution detection;
- review/human-needed stop path.

### 5.2 State-first

Каждое дорогое действие должно вытекать из:

- текущего state;
- нового события;
- policy checks;
- dedup checks.

Не из “кажется, пора ещё раз попробовать”.

### 5.3 Executor is not the orchestrator

Executor не принимает продуктовых решений:

- не выбирает бизнес-фазу;
- не решает, делать ли ещё один expensive run;
- не решает ownership;
- не переводит систему через произвольные semantic transitions.

Он только исполняет выданный execution contract и пишет результат.

### 5.4 Supervisor is not a hidden second daemon

Watchdog/supervisor не должна:

- “сама долечивать” flow;
- плодить side effects;
- скрыто переигрывать бизнес-решения daemon/orchestrator.

Она может:

- freeze;
- stop;
- alert;
- mark stale;
- request re-evaluation.

### 5.5 Human feedback is first-class

Ответ пользователя в issue/review — это не строка в логах, а отдельный нормализованный trigger:

- ordinary wait reply;
- review feedback;
- rework;
- continue;
- finalize decision;
- blocker clarification.

### 5.6 GitHub pressure must be minimized

Система должна жить не “от лимита к лимиту”, а иметь:

- REST-first там, где можно;
- GraphQL only where necessary;
- metadata cache;
- bounded polling;
- no fallback-heavy idle loops;
- audit trail по GraphQL consumers.

---

## 6. Высокоуровневая архитектура

Логическая схема выглядит так:

1. GitHub Project / Issue / PR производят внешний observable state.
2. Daemon получает snapshot/replies и решает, есть ли следующий допустимый transition.
3. Intake layer превращает свободную задачу в normalized execution contract.
4. Executor выполняет строго ограниченный worktree-based run.
5. Finalize path оформляет commit/PR/review state.
6. Watchdog следит за аномалиями и containment.
7. Runtime-v2 хранит canonical state, events, executions, budgets, primary contexts.

В текущем реализованном контуре часть flow всё ещё гибридная:

- часть legacy shell state живёт в файловом state-dir;
- runtime-v2 уже умеет быть primary source для selected contexts;
- reconcile bridge проецирует runtime-v2 обратно в legacy files;
- cutover идёт поэтапно, не одномоментно.

---

## 7. Канонические роли компонентов

### 7.1 Event/transport layer

Источники событий:

- GitHub issue comments;
- review feedback;
- PR merge;
- project field/status changes;
- local/runtime lifecycle events;
- completion/failure execution;
- operator commands.

На текущей реализации transport исторически partly shell-based, но направление v2 — нормализовать это в explicit event model.

### 7.2 Daemon

Daemon отвечает за:

- claim задач;
- проверку блокеров и preconditions;
- запуск intake/executor path;
- переходы в waiting/review;
- работу с GitHub task lifecycle;
- дорогие orchestration decisions.

Daemon не должна:

- выполнять AI работу сама;
- обходить budget/containment policy;
- бесконечно читать GitHub в idle-loop ради “подстраховки”.

### 7.3 Executor

Executor отвечает за:

- materialize task worktree;
- собрать context/prompt;
- выполнить AI run;
- провести allowed verification;
- собрать usage/budget artifacts;
- вернуть result в runtime/finalize path.

Executor должна работать в clearly bounded envelope:

- task id;
- issue number;
- branch;
- execution profile;
- budget policy;
- deterministic check commands;
- side-effect class.

### 7.4 Watchdog / Supervisor

Watchdog следит за:

- stale active task;
- missing executor heartbeat;
- impossible state combinations;
- dirty worktree / lock conflicts;
- runtime anomalies;
- stuck review/wait transitions;
- health of daemon/executor/runtime surfaces.

Она может:

- перевести систему в `SAFE` или `EMERGENCY_STOP`;
- записать incident;
- очистить stale state в строго определённых случаях;
- снять зависший hold, если задача уже terminal/closed.

### 7.5 Runtime-v2

`runtime-v2` — это следующий canonical state layer, который должен постепенно забирать у legacy shell право быть truth source.

Он содержит:

- store/adapters;
- primary context derivation;
- orchestrator policy;
- execution policy;
- budgets;
- event application;
- shadow/legacy bridge.

---

## 8. Data model

Архитектурно v2 опирается на минимальный набор сущностей.

### 8.1 Task

Бизнес-задача.

Содержит:

- `taskId`;
- привязку к issue/PR/project item;
- owner mode;
- repo/profile metadata;
- coarse phase/status.

### 8.2 TaskState

Runtime состояние задачи.

Содержит:

- текущую фазу;
- reason waiting/paused;
- current attempt;
- links to latest source/spec/execution artifacts;
- lock state;
- timestamps.

### 8.3 Event

Нормализованное входящее событие.

Примеры:

- `human.response_received`;
- `review.feedback_wait_requested`;
- `review.finalized`;
- `execution.started`;
- `execution.finished`;
- `budget.breached`;
- `supervisor.freeze_requested`.

### 8.4 Execution

Единица дорогой AI-работы.

Содержит:

- type / phase;
- dedup key;
- execution profile;
- status;
- provider result;
- token usage;
- cost;
- termination reason;
- timestamps / heartbeat / lease.

### 8.5 Budget

Budget-layer должен уметь считать ограничения на уровне:

- task;
- day/window;
- project/system.

Минимальные лимиты:

- executions per task per period;
- tokens per task per period;
- estimated cost per task per period;
- global spend cap.

### 8.6 Lock

Lock нужен для:

- защиты от параллельных conflicting runs;
- human takeover;
- stale recovery;
- lease enforcement.

---

## 9. State machine

Каноническая state machine должна быть компактной. Базовый набор фаз:

- `NEW`
- `READY`
- `PLANNING`
- `IMPLEMENTING`
- `REVIEWING`
- `WAIT_HUMAN`
- `WAIT_GITHUB`
- `WAIT_COOLDOWN`
- `PAUSED`
- `DONE`
- `FAILED`

На текущем shell/runtime уровне используются операционные состояния/маркеры:

- `IDLE_NO_TASKS`
- `WAIT_USER_REPLY`
- `WAIT_REVIEW_FEEDBACK`
- `WAIT_GITHUB_RATE_LIMIT`
- `WAIT_GITHUB_AUTH`
- `WAIT_GITHUB_OFFLINE`
- `WAIT_DIRTY_WORKTREE`
- `WAIT_OPEN_PR`
- `ERROR_LOCAL_FLOW`
- `SAFE`
- `EMERGENCY_STOP`

Важно: reason waiting должен храниться отдельно от phase, чтобы state machine не раздувалась в десятки псевдосостояний.

Пример:

- `phase = WAIT_COOLDOWN`
- `reason = github_rate_limit`

---

## 10. Ownership model

Ownership определяет, кто имеет право продолжать задачу:

- `human`
- `mixed`
- `auto`
- `blocked`

Смысл:

- `human`: AI execution запрещён;
- `mixed`: допускаются ограниченные safe/read-only paths;
- `auto`: full flow разрешён в рамках budget;
- `blocked`: всё заморожено.

Manual переключения ownership должны оставлять audit trail.

---

## 11. Containment and control modes

Одна из первых реализованных частей v2 — глобальные control modes:

- `AUTO`
- `SAFE`
- `EMERGENCY_STOP`

Их назначение:

- `AUTO`: expensive path разрешён;
- `SAFE`: expensive path заблокирован, inspection/read-only живы;
- `EMERGENCY_STOP`: жёсткая остановка по инциденту, quota failure или supervisor decision.

Containment обязан уважаться:

- daemon;
- watchdog;
- executor_start;
- executor_run;
- related wrappers.

Система обязана не “забывать” containment при локальных тиках, restart или partial failure.

---

## 12. Runtime-v2 и phased cutover

`runtime-v2` не включается одномоментно. В проекте уже реализован phased cutover:

### 12.1 Shadow contour

Сначала `runtime-v2` живёт как shadow bridge:

- file adapter;
- shadow sync из legacy state;
- snapshot/clear wrappers;
- отдельное хранилище рядом с legacy runtime.

### 12.2 Primary source for selected contexts

Следующим этапом runtime-v2 начинает быть primary source для selected contexts:

- active;
- review;
- далее waiting.

Через:

- `runtime_v2_primary_context.sh`
- `runtime_v2_reconcile_primary_context.sh`

### 12.3 Orchestrator semantics

Review/wait transitions постепенно перестают быть direct shell writes и переходят в:

- emit event;
- apply event in runtime-v2;
- reconcile into legacy files for compatibility.

### 12.4 Execution policy

Execution policy в runtime-v2 уже покрывает:

- dedup key;
- running execution lookup;
- recent-success duplicate suppression;
- stale execution marking.

### 12.5 Supervisor separation

Watchdog постепенно перестаёт лечить flow напрямую и становится supervisor:

- freeze;
- stop;
- alert;
- anomaly classification.

---

## 13. Intake layer

Один из самых важных срезов v2 — отделение task understanding от task execution.

### 13.1 Зачем нужен intake

Свободная пользовательская постановка может содержать:

- шум;
- mixed signals;
- implicit target files;
- ambiguous intent;
- sections `Что сделать`, `Проверки`, `Вне scope`;
- уточнения через issue comments.

Executor не должна читать raw issue text как execution contract.

### 13.2 Canonical intake artifacts

Введены три основных артефакта:

- `source_definition.json`
- `standardized_task_spec.json`
- `intake_profile.json`

### 13.3 Source Definition

Хранит raw human input как audit source:

- issue title;
- issue body;
- reply text;
- source hash;
- capture timestamp.

### 13.4 Standardized Task Spec

Нормализованный execution-ready contract.

Содержит:

- `profileDecision`
- `decisionReason`
- `interpretedIntent`
- `candidateTargetFiles`
- `expectedChange`
- `checks`
- `confidence`
- `notes`
- `rationale`
- repository context

### 13.5 Intake Profile

Содержит verdict interpretation layer:

- `micro`
- `standard`
- `human_needed`
- `blocked`

С rationale и confidence.

### 13.6 Reply-aware interpretation

Intake должна учитывать не только issue body, но и последующие clarifying replies. Это позволяет:

- повторно классифицировать задачу после уточнения;
- не терять смысл human feedback;
- избегать ложного `human_needed`, когда пользователь уже ответил.

### 13.7 Human-needed / blocked

Если intake не может построить безопасный execution contract:

- execution не стартует;
- задача уходит в explicit review/human-needed;
- issue получает понятный handoff-comment с объяснением.

---

## 14. Execution profiles

В текущем v2 есть как минимум следующие profile classes.

### 14.1 Micro

Для маленьких, узко scoped правок.

Свойства:

- ограниченный prompt;
- bounded target files;
- bounded allowed commands;
- жёсткий token envelope;
- максимум ограниченное число LLM calls;
- repair path только в заранее разрешённых пределах.

Micro profile не должен брать raw issue как единственный contract. Он должен брать normalized spec.

### 14.2 Standard

Для более широких задач, где нужен:

- richer repo context;
- broader reasoning;
- более широкий execution envelope.

### 14.3 Human-needed

Execution не стартует.

Причины:

- ambiguous target files;
- недоопределённый intent;
- conflicting constraints;
- intake не может безопасно нормализовать задачу.

### 14.4 Blocked

Жёсткий stop ещё до execution.

Причины:

- security-sensitive requests;
- credential/billing/secrets;
- policy-prohibited work.

---

## 15. Task worktree model

Исполнение должно идти не в живом root checkout, а через per-task worktree contour.

Основные свойства:

- task-specific repo dir;
- deterministic path;
- toolkit materialization;
- execution artifacts рядом с task worktree;
- recovery/recreate path при broken submodule/toolkit state.

Worktree contour нужен для:

- изоляции задач;
- repeatability;
- artifact locality;
- safer cleanup and forensic analysis.

Если toolkit revision в reused worktree битый, worktree должен пересоздаваться целиком, а не “доживать на поломанном состоянии”.

---

## 16. Executor contract

Формальный execution envelope должен содержать как минимум:

- `taskId`
- `issueNumber`
- `phase`
- `triggerEventId`
- `dedupKey`
- `sideEffectClass`
- `leaseExpiresAt`
- execution profile
- references to source/spec artifacts

Executor обязана:

- логировать usage;
- писать structured result;
- фиксировать provider errors;
- respect profile guardrails;
- respect lease/budget/containment;
- не переходить сама в semantic business state без finalization path.

---

## 17. Dedup, lease, stale handling

Это обязательный слой v2.

### 17.1 Dedup

Для каждого expensive-run вычисляется deterministic `dedupKey`, например из:

- task id;
- phase;
- branch head sha;
- PR/review snapshot hash;
- task spec hash;
- input context hash.

Если такой execution уже:

- `running` — новый старт запрещён;
- `recent successful` — новый старт запрещён;
- `failed above retry policy` — нужен manual/cooldown path.

### 17.2 Lease

Execution получает lease/heartbeat.

Если heartbeat stale:

- execution переводится в terminal failed;
- restart chain не должен стартовать автоматически;
- supervisor может только freeze/alert/re-evaluate.

### 17.3 Stale active task

Если task активна, но executor уже нет:

- normal waiting/review path не должен давать false-positive freeze;
- если задача уже terminal/closed, stale hold должен сниматься автоматически;
- orphan executor tail не должен стопорить новые задачи.

---

## 18. Budget policy

Budget guardrails должны проверяться до expensive run.

Минимальный набор:

- `max executions per task per 24h`
- `max input/output tokens per task per window`
- `max estimated cost per task`
- global project/system cap

При breach:

- автоматический retry запрещён;
- задача или система переходит в `WAIT_HUMAN`, `PAUSED_BUDGET` или `EMERGENCY_STOP`;
- выход только через explicit operator action.

В текущем runtime есть уже фактические gate reasons вроде:

- `max_executions_per_task`
- `max_token_usage_per_task`
- `max_estimated_cost_per_task`

И они должны приводить не к немому стопу, а к понятному task-level handoff.

---

## 19. GitHub integration model

### 19.1 Project

Project v2 используется для:

- backlog;
- `Todo`;
- `In Progress`;
- `Review`;
- `Done`;
- auxiliary fields вроде `Flow`, `Priority`, `Task ID`.

### 19.2 Issue

Issue используется для:

- постановки задачи;
- clarification;
- blockers/questions;
- human-needed review;
- final review handoff;
- continuation/rework responses.

### 19.3 PR

PR используется для:

- промежуточного progress;
- финального review surface;
- merge signal;
- auto-close/done transitions.

### 19.4 Webhook-first target

Архитектурная цель v2:

- webhook-first change detection;
- polling only for reconciliation/cooldown/health;
- polling не должен напрямую запускать expensive execution.

---

## 20. GraphQL discipline

Одна из критических тем v2 — давление на GitHub GraphQL.

Из аудита:

- основной consumer — daemon, не executor;
- самый вредный hotspot — project-item fallback в idle loop;
- review-resume не должен зависеть от полного project scan;
- fields metadata хорошо кэшируется;
- `task_id -> item_id` нужно кэшировать;
- per-caller audit нужен для реальной картины расхода.

### 20.1 Что обязательно

- direct GraphQL wrappers with caller tagging;
- indirect `gh project *` audit;
- metadata cache;
- bounded project pagination;
- no fallback-heavy idle loop;
- clear `WAIT_GITHUB_RATE_LIMIT_*` semantics.

### 20.2 Что уже видно из практики

Если этого не делать, система живёт в цикле:

1. idle tick делает project scan;
2. пустая очередь вызывает лишний fallback list;
3. приходит rate limit;
4. review reply не может обработаться;
5. после cooldown всё повторяется.

---

## 21. Waiting and review model

Система должна различать как минимум:

- ordinary question/blocker wait;
- review-feedback wait;
- terminal review;
- human-needed review;
- automation-stop review.

### 21.1 WAIT_USER_REPLY

Используется, когда executor задал вопрос или уткнулся в blocker.

### 21.2 WAIT_REVIEW_FEEDBACK

Используется после finalization/review handoff.

### 21.3 Human-needed / intake stop

Если задача не дошла до execution, но требует уточнения, это должно быть выражено отдельным structured comment, а не vague fallback text.

### 21.4 Resume path

Reply processing должно:

- dedup-ить consumed comments;
- очищать legacy waiting anchors;
- переносить смысл reply в source/spec;
- не зависеть жёстко от полного project queue read.

---

## 22. Finalize path

Финализация задачи включает:

- подготовку branch/head;
- commit/push;
- create/edit PR;
- mark ready if needed;
- issue comment `AGENT_IN_REVIEW`;
- project status/flow transition;
- reconcile review context.

Важно:

- finalize не должна silently fail;
- при неудаче в GitHub/API должен быть deferred/runtime-safe path;
- semantic review comment не должен врать про отсутствие PR, если PR уже существует.

---

## 23. Comment protocol

Issue comments используются как machine-readable interface.

Типовые сигналы:

- `CODEX_SIGNAL: AGENT_IN_REVIEW`
- `CODEX_EXPECT: USER_REVIEW`
- `CODEX_REVIEW_KIND: AUTOMATION_STOP`
- `CODEX_AUTOMATION_STOP_REASON: ...`
- question/blocker/rework/continue markers

К comment protocol предъявляются требования:

- комментарий должен быть human-readable;
- при этом должен сохранять machine tags;
- при stop/review он должен объяснять не только “что произошло”, но и “что именно было непонятно системе”.

Пример нужной детализации для intake stop:

- decision reason;
- confidence;
- interpreted intent;
- candidate target files count;
- явное объяснение, что именно не удалось привязать.

---

## 24. Operator controls

Даже в project-agnostic контуре оператор должен иметь базовый набор manual controls:

- pause/resume automation;
- switch ownership;
- retry allowed stage;
- cancel execution;
- clear stale active state;
- unlock after budget breach;
- inspect snapshots/log summary/primary contexts.

На shell/tooling уровне это уже partly выражается через `run.sh` wrappers и runtime control scripts.

---

## 25. Observability

Raw logs недостаточны. Нужны:

- structured execution profile logs;
- incident ledger;
- execution ledger;
- runtime snapshots;
- primary context output;
- GraphQL audit log;
- explicit state transitions;
- failure categories.

Особенно важно, чтобы по первым строкам лога было видно:

- какой execution profile выбран;
- почему;
- сколько target files;
- какой artifact file использован;
- на каком именно GitHub call возник auth/rate-limit problem.

---

## 26. Failure classes

Система должна различать хотя бы такие категории:

- GitHub auth failure;
- GitHub rate limit;
- GitHub offline/network failure;
- local flow error;
- stale execution;
- dirty worktree;
- intake human-needed;
- intake blocked;
- profile breach;
- provider quota exceeded;
- materialize failed;
- supervisor freeze anomaly.

Каждая такая категория должна иметь:

- machine-readable reason;
- понятный human explanation;
- expected next action.

---

## 27. Rollout strategy

`v2` не включается “одним рубильником”.

Рекомендуемый порядок:

1. containment baseline;
2. state store bootstrap;
3. orchestrator/execution policy;
4. budget guardrails;
5. ownership model;
6. GitHub integration rework;
7. supervisor hard contract;
8. operator UI / richer surfaces;
9. observability and incident exports;
10. controlled rollout;
11. limited rollout;
12. broader adoption.

В архиве и docs уже отражены отдельные rollout kits/checklists для safe и limited rollout.

---

## 28. Что уже реализовано в текущем AI Flow v2 contour

По собранным phase/result docs в систему уже заведены и частично внедрены:

- global containment modes и incident/execution ledgers;
- runtime-v2 file-backed shadow store;
- dedup key и stale execution policy;
- selected primary contexts в runtime-v2;
- review/wait business state migration через event/reconcile;
- supervisor semantics вместо auto-healing watchdog;
- intake layer с source/spec/profile artifacts;
- normalized task spec;
- intake-driven execution profile;
- executor handoff на normalized spec;
- micro profile guardrails, canaries и target-aware context slicing;
- GraphQL audit direction и сокращение idle fallback pressure;
- fixes вокруг human reply/review resume, stale active holds и clearer automation-stop signaling.

Это значит, что `AI Flow v2` уже не абстрактный план, а действующий гибридный runtime, который ещё не доведён до полного event-first control plane, но уже строится по этой модели.

---

## 29. Что ещё остаётся архитектурным долгом

Несмотря на большой прогресс, проект всё ещё не полностью закончен как чистый v2 control plane.

Ключевые долги:

- GitHub всё ещё слишком сильно участвует в queue/read path;
- webhook-first модель ещё не доведена до конца;
- waiting/review resume местами всё ещё завязаны на legacy transport logic;
- runtime-v2 пока primary source не для всего lifecycle;
- Mongo как canonical persistent store упомянут и частично подготовлен, но file-backed contour всё ещё заметен;
- operator UI пока вторичен по сравнению с shell/runtime scripts;
- не вся anomaly model формализована как structured events.

---

## 30. Definition of Done для зрелого project-agnostic AI Flow

Систему можно считать зрелой, если одновременно выполняется следующее:

1. Expensive execution невозможен без meaningful new event.
2. Duplicate execution по одному semantic input не создаётся.
3. Budget breach останавливает flow deterministically.
4. Human takeover и human-needed paths не ломают очередь.
5. Review/wait states живут как canonical state, а не как fragile file flags.
6. GitHub GraphQL не является главным bottleneck idle-loop.
7. Watchdog не плодит side effects и не скрывает root cause.
8. Intake умеет честно различать `micro`, `standard`, `human_needed`, `blocked`.
9. Operator может объяснить любое состояние по structured artifacts, не читая много сырых логов.
10. Перенос на новый repo/profile требует только конфигурации, а не переписывания ядра.

---

## 31. Практическая проектонезависимая формула системы

В сжатом виде `AI Flow v2` — это:

- **GitHub как внешний интерфейс**
- **runtime-v2 как внутренний source of truth**
- **daemon как orchestration entrypoint**
- **executor как bounded AI worker**
- **watchdog как supervisor**
- **intake как слой понимания задачи**
- **dedup + lease + budgets как safety envelope**
- **review/human feedback как first-class events**
- **worktree/toolkit isolation как execution substrate**
- **observability/audit как обязательная часть system contract**

Именно это и составляет проектонезависимый `AI GitHub Repo/Projects Flow`, который может быть перенесён между репозиториями при сохранении тех же принципов, state contracts и operational discipline.
