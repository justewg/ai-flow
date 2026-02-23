# TASKFLOW.md

## Цель
Зафиксировать единый управляемый flow разработки PLANKA:
- текущий рабочий процесс (ручной триггер через `merged`);
- целевой daemon-процесс (управление через GitHub Project).

## 1. Роли и источник правды
- Ты управляешь приоритетами и запуском задач через GitHub Project.
- Я выполняю реализацию, коммиты, PR, обновления статусов.
- Источник правды по очереди задач: GitHub Project (поля `Priority`, `Status`, `Flow`; `Task ID` опционально, если заполнен).

## 2. Текущий рабочий flow (действует сейчас)
1. Ты делаешь merge PR `development -> main`.
2. Ты пишешь `merged`.
3. Я запускаю синхронизацию веток:
   - `scripts/codex/run.sh sync_branches`
4. Я проверяю очередь запуска:
   - `Status=To Progress` (твоя явная команда "запускай");
   - при подхвате сразу перевожу задачу в `In Progress` (`project_set_status`) как ACK.
5. После подхвата:
   - реализую изменения в рабочем цикле.
6. По готовности:
   - запускаю `scripts/codex/run.sh task_finalize` (commit+push, create/update PR, перевод в `Status=Review`, `Flow=In Review`);
   - перевожу PR в финальный сигнал ревью (`ready_for_review`);
   - отправляю ссылку на PR для ревью;
   - после merge цикл повторяется.

## 3. Post-merge автоматика (уже внедрена)
- GitHub Actions после merge PR в `main`:
  - извлекает `PL-xxx` и `ISSUE-<n>` из title/body PR;
  - переводит карточки в GitHub Project в `Done` (`Status=Done`, `Flow=Done`).
- Telegram-оповещения по статусам post-merge workflow.

## 4. Целевой daemon-flow (управление тасканием карточек)
### 4.1. Базовая идея
- GitHub Project становится пультом управления.
- Ты двигаешь задачи между колонками/статусами.
- Локальный daemon-процесс регулярно читает проект и запускает работу без команды `merged`.

### 4.2. Рекомендуемая модель состояний
Используем текущие поля:
- `Status`: `Todo -> To Progress -> In Progress -> Review -> Done -> Closed`
- `Flow`: `Backlog -> In Progress -> In Review -> Done`

Правила:
1. Новая задача: `Status=Todo`, `Flow=Backlog`.
2. Твоя команда на старт: перевести задачу `Status: Todo -> To Progress`.
3. Daemon мониторит только `Status=To Progress`.
4. Для автоподхвата учитываются только карточки типа `Issue` (не `DraftIssue`).
5. Для рабочего цикла используется `task_id`:
   - если задан `Task ID`, берется он;
   - иначе daemon пытается взять `PL-xxx` из title;
   - если `PL-xxx` нет, daemon автоматически использует `ISSUE-<number>`.
6. При подхвате daemon сразу переводит задачу в `Status=In Progress` (визуальный ACK, что демон жив и начал работу).
7. Затем daemon переводит `Flow=In Progress` и запускает обычный цикл реализации.
8. Перед запросом ревью: `Status=Review`, `Flow=In Review`.
9. После merge: existing workflow ставит `Done`.

### 4.3. Семантика статусов
- `Todo`: бэклог.
- `To Progress`: входная очередь для демона (твой явный сигнал "запускай").
- `In Progress`: задача уже подхвачена демоном и реально выполняется.
- `Done/Closed`: завершенные задачи.

## 5. Контракт демона (что он должен делать)
1. Периодически (например, каждые 30-60 сек) читать GitHub Project.
2. Гарантировать single-run (lock-файл), чтобы не запускать две задачи одновременно.
3. Если уже есть открытый PR `development -> main`, новую задачу не брать.
4. Проверять очередь `Status=To Progress`:
   - если `0` задач: ждать;
   - если `1` задача: забрать ее в работу;
   - если `>1` задач: перейти в `blocked` и уведомить (без самовольного выбора).
5. При подхвате задачи:
   - поменять `Status` на `In Progress` (ACK);
   - поменять `Flow` на `In Progress`;
   - продолжить разработку по стандартному flow.
6. При завершении разработки:
   - выполнить `task_finalize` для commit/push и create/update PR;
   - перевести карточку в `Status=Review`, `Flow=In Review`.
7. Логировать heartbeat и действия в `.tmp/codex/daemon.log`.
8. Корректно обрабатывать ошибки (retry/backoff, без дублирования действий).
9. Не запускать подхват задач при изменениях tracked-файлов (wait-state), чтобы не конфликтовать с ручной работой в чате.
10. Untracked-файлы (черновики, артефакты, заметки) не должны блокировать daemon-flow.
11. Если в ходе задачи нужен ответ от тебя:
   - агент публикует комментарий в Issue с сигналом `CODEX_SIGNAL: AGENT_QUESTION` или `AGENT_BLOCKER`;
   - Telegram workflow отправляет уведомление;
   - daemon переходит в ожидание ответа (`WAIT_USER_REPLY`) и не подхватывает новые задачи;
   - твой следующий комментарий в Issue принимается как входное сообщение;
   - после получения ответа daemon публикует `CODEX_SIGNAL: AGENT_RESUMED` и продолжает flow.
   - если executor завершил прогон (`DONE`), но задача не финализирована, агент обязан опубликовать blocker-комментарий и ждать твоего решения (`продолжай`/`финализируй`), а не молчать.
12. В heartbeat-логе daemon обязан писать агрегированный operational-state и причину (`STATE=...`), включая деградации вроде `WAIT_GITHUB_OFFLINE`.
13. При деградации daemon отправляет локальный Telegram-сигнал (не по каждому тику): вход в деградацию, смена причины, редкий reminder и восстановление.
14. Если деградация связана с DNS GitHub, daemon обязан дополнительно проверить доступность Telegram (`api.telegram.org`):
   - если Telegram доступен, обязательно отправлять сигнал через бота о текущем состоянии деградации;
   - если Telegram тоже недоступен, фиксировать это в state/detail и логе для диагностики.
15. Отдельный watchdog-процесс (вне sandbox runtime) должен мониторить daemon/executor и делать авто-восстановление:
   - `soft`: `daemon_tick`;
   - `medium`: `executor_reset` + `daemon_tick`;
   - `hard`: `daemon_uninstall` + `daemon_install` (и cleanup stale `daemon.lock`);
   - с cooldown и логированием причин в `watchdog.log`.

## 5.1. Режимы работы: чат и демон
Есть два параллельных режима, они не конфликтуют:

1. Ручной чат-режим (этот диалог):
   - используется для постановки задачи, обсуждения решений, код-изменений и ревью результата;
   - я выполняю осознанные инженерные шаги по твоим сообщениям.

2. Авто-режим демона:
   - фоновый `launchd`-процесс делает polling проекта и реагирует на `Status=To Progress`;
   - демон отвечает за подхват очереди, синхронизацию, перевод в `In Progress` и запуск/контроль executor.
   - executor выполняет реализацию, делает промежуточные коммиты и обновляет PR.

Правило разделения ответственности:
- выбор задачи делает только ты (перемещением карточки в `To Progress`);
- подхват и старт исполнения делает демон;
- содержательная разработка в авто-режиме делается executor-ом;
- коммуникация по блокерам/вопросам идет через Issue-комментарии;
- завершение дельты оформляется через `task_finalize` внутри executor-цикла.

Telegram-сигналы по PR:
- `Signal: TEMP_PROGRESS` — промежуточные изменения, проверка не требуется.
- `Signal: FINAL_REVIEW` (`Action: ready_for_review`) — финальная отсечка: нужно идти проверять и принимать.
- Backward-compatible правило: если PR открыт/переоткрыт сразу как non-draft, `Signal: FINAL_REVIEW` отправляется на `opened/reopened`.

Telegram-сигналы по Issue-вопросам:
- `Signal: AGENT_QUESTION` — вопрос по задаче, нужен твой ответ.
- `Signal: AGENT_BLOCKER` — блокер, нужен твой ответ.
- `Signal: AGENT_RESUMED` — ответ получен, выполнение продолжено.

## 6. Политика языка и оформления
- Общение: русский.
- Коммиты: русский формат `PL-xxx: ...` или `ISSUE-<n>: ...`.
- Заголовки PR: русский формат `PL-xxx ...` или `ISSUE-<n> ...`.
- Тело PR: краткое описание, состав изменений, критерии приемки, шаги QA, примечания.

## 7. Операционные правила безопасности
- Автоматически разрешено:
  - коммиты и push в `development`;
  - создание/обновление PR `development -> main`;
  - sync веток после merge.
- Обязательно спросить перед:
  - удалением файлов/директорий;
  - рискованными merge/rebase/cherry-pick;
  - потенциально деструктивными git-операциями.

## 8. Точка эволюции (следующий шаг)
Минимальный план внедрения daemon-версии:
1. `scripts/codex/daemon_loop.sh` (poll + lock + state machine).
2. Обновление `scripts/codex/README.md` с командами демона.
3. Проверка наличия значения `Status`: `To Progress` в проекте.
4. Запуск демона как системного сервиса (`launchd`) на рабочей машине.
5. Опционально: workflow `repository_dispatch` для ускоренного триггера после merge.

### 8.1. Команды launchd
- Установить и запустить сервис:
  - `scripts/codex/run.sh daemon_install`
- Установить с кастомным интервалом (например, 30 сек):
  - `scripts/codex/run.sh daemon_install com.planka.codex-daemon 30`
- Проверить статус:
  - `scripts/codex/run.sh daemon_status`
- Остановить и удалить сервис:
  - `scripts/codex/run.sh daemon_uninstall`

### 8.2. Команды watchdog
- Установить и запустить watchdog:
  - `scripts/codex/run.sh watchdog_install`
- Проверить статус watchdog:
  - `scripts/codex/run.sh watchdog_status`
- Выполнить ручной тик watchdog:
  - `scripts/codex/run.sh watchdog_tick`
- Остановить и удалить watchdog:
  - `scripts/codex/run.sh watchdog_uninstall`

## 9. Как добавить статус `To Progress` в GitHub Project
### 9.1. Рекомендуемый путь (UI)
1. Открой проект GitHub Project (№2) в table view.
2. Открой настройки single-select поля `Status`.
3. Добавь новую опцию со значением `To Progress`.
4. Сохрани изменения и расположи опции в порядке: `Todo`, `To Progress`, `In Progress`, `Review`, `Done`.
5. В board-view убедись, что колонка `To Progress` отображается.

Практический смысл:
- это не GitHub Label, а значение single-select поля `Status` (семантическое состояние проекта);
- при перетаскивании карточки в колонку `To Progress` значение поля `Status` обновляется автоматически.
- при создании Issue через UI поле `Task ID` обычно не заполняется автоматически (это нормально); демон не зависит от этого поля для перевода статусов и использует `project item id`.

### 9.2. Важные ограничения API/CLI
- `gh project` CLI умеет создавать/удалять поля и редактировать значения у items, но не имеет отдельной команды `field-edit` для опций существующего поля.
- REST API для Project fields покрывает list/add/get, но не отдельный endpoint "update options for existing field".
- Для API-редактирования опций у существующего single-select поля используется GraphQL mutation `updateProjectV2Field` с `singleSelectOptions`.
- Важно: передача `singleSelectOptions` в `updateProjectV2Field` перезаписывает весь список опций, поэтому нужно отправлять полный список (старые + новая `To Progress`).
