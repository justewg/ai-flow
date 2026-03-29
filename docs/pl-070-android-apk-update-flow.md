# PL-070: безопасный APK update flow для Android shell

## Цель

Зафиксировать MVP-совместимый и проверяемый flow обновления APK для Android shell через HTTPS manifest, без silent install и без неявных trust assumptions.

Документ должен быть одинаково понятен:

- Android shell;
- publish-инфраструктуре;
- операторскому runbook;
- последующим задачам `PL-071` и `PL-072`.

## Границы решения

Этот документ не вводит:

- silent install;
- MDM / device owner / enterprise policy path;
- background install без явного действия пользователя;
- downgrade APK через manifest;
- delta/binary patching APK;
- staged rollout и cohort routing.

MVP-путь остаётся ручным:

1. shell проверяет manifest;
2. shell понимает, что доступен новый APK;
3. пользователь явно подтверждает установку;
4. Android system installer выполняет обновление поверх текущего приложения.

## Канонические входные данные

APK update flow опирается на contract из `PL-068` и использует только следующие поля manifest:

- `appVersion`
- `appVersionName`
- `minSupportedAppVersion`
- `message`
- `apk.url`
- `apk.sha256`

Дополнительных APK-специфичных полей schema v1 не требуется.

## Trust model

### Источник истины

Для MVP доверенный update path строится из трёх уровней:

1. HTTPS-доставка от доверенного publish endpoint.
2. Проверка целостности скачанного APK через `sha256`, заданный в manifest.
3. Проверка identity/update-совместимости через Android package signing path при установке поверх уже установленного приложения.

### Что считается доверенной identity APK

Доверенным считается только APK, который одновременно:

1. имеет ожидаемый `packageName` Android shell;
2. имеет `versionCode`, совпадающий с `manifest.appVersion`;
3. по байтам совпадает с `manifest.apk.sha256`;
4. подписан тем же release signing lineage, что и уже установленное приложение;
5. принимается системным installer как корректный update existing app.

### Откуда берётся проверка signature

В MVP принимается такой security contract:

1. publish-side использует один устойчивый release signing key / signing lineage;
2. Android installer является последней authoritative проверкой signature continuity;
3. shell до вызова installer по возможности дополнительно проверяет метаданные APK:
   - `packageName`;
   - `versionCode`;
   - signing certificate digest, если его можно достоверно извлечь на устройстве;
4. если pre-install inspection не даёт однозначного ответа, shell всё равно не доверяет APK автоматически, а отдаёт его только в системный installer.

Это важное MVP-решение:

- trust по identity не переносится в сам manifest;
- manifest отвечает за discovery и hash-integrity;
- installer отвечает за финальную проверку update legitimacy.

## Обязательные pre-install проверки на клиенте

Перед тем как показать пользователю подтверждение установки или передать файл installer, shell обязан пройти минимум следующие проверки:

1. `apk.url` скачан по HTTPS без transport error.
2. Скачанный файл имеет `sha256`, равный `manifest.apk.sha256`.
3. APK распознаётся как Android package.
4. `packageName` APK совпадает с package name текущего shell.
5. `versionCode` APK равен `manifest.appVersion`.
6. `versionCode` APK строго больше `installedAppVersion`.

Если доступен локальный inspect signing certificate, shell дополнительно обязан сравнить certificate digest с доверенным expected value.

Если любая проверка не проходит, shell:

- не открывает installer;
- не меняет локальное состояние;
- пишет диагностическое событие причины отказа.

## Expected signing path

Для MVP фиксируется следующий signing contract:

1. существует один release keystore, принадлежащий операторскому контуру;
2. debug APK и release APK не смешиваются в одном publish channel;
3. production-like update channel публикует только APK, подписанные release key;
4. смена signing lineage считается отдельной миграцией, а не обычным обновлением.

Следствие:

- `PL-071` должна разделять как минимум test/debug и real operator channel;
- shell не должен воспринимать любой APK с валидным hash как доверенный, если signing continuity ломается.

## Канонический client flow

### Шаг 1. Проверка manifest

Shell выполняет manual update check по `PL-068`.

Если итоговое состояние:

- `up_to_date` — APK flow не запускается;
- `config_update_available` — APK flow не запускается;
- `apk_update_available` или `apk_update_required` — запускается APK path.

### Шаг 2. Показ доступности обновления

Shell показывает оператору:

- `appVersionName`;
- короткий `message`;
- различие между optional update и required update.

Два режима обязательны:

1. `optional`:
   - новый APK доступен;
   - текущий shell ещё совместим с manifest/config;
   - пользователь может отложить установку.
2. `required`:
   - `installedAppVersion < minSupportedAppVersion`;
   - новый config без нового APK применять нельзя;
   - shell показывает, что требуется обновление приложения.

### Шаг 3. Скачивание APK

После явного подтверждения пользователя shell:

1. скачивает APK во временное внутреннее хранилище;
2. не трогает текущие app/config state;
3. фиксирует диагностические события download start/result.

### Шаг 4. Целостность и metadata validation

Shell:

1. считает `sha256`;
2. сравнивает с `manifest.apk.sha256`;
3. извлекает `packageName` и `versionCode`;
4. по возможности извлекает signing certificate digest;
5. только после успешной проверки разрешает переход к installer.

### Шаг 5. Передача в Android installer

Shell вызывает штатный installer intent и передаёт управление системе.

После этого:

- shell не считает update успешным немедленно;
- локальное состояние версии не переписывается вручную;
- фактом успеха считается только следующий старт приложения с новым фактическим `versionCode`.

### Шаг 6. Post-install confirmation

При следующем запуске shell:

1. читает фактический `installedAppVersion`;
2. если версия выросла до ожидаемой, считает APK update успешным;
3. если версия не изменилась, трактует предыдущий install attempt как неуспешный или отменённый.

## Decision table

| Ситуация | Решение shell |
| --- | --- |
| `manifest.appVersion <= installedAppVersion` | Не скачивать APK, показать `Обновление не требуется` |
| `manifest.appVersion > installedAppVersion`, `installedAppVersion >= minSupportedAppVersion` | Показать optional update |
| `installedAppVersion < minSupportedAppVersion` и `manifest.appVersion > installedAppVersion` | Показать required update, config не применять |
| `installedAppVersion < minSupportedAppVersion` и `manifest.appVersion <= installedAppVersion` | Показать operator error / inconsistent manifest |
| `sha256` mismatch | Остановить flow, показать error, installer не открывать |
| `packageName` mismatch | Остановить flow, считать release invalid |
| `versionCode` mismatch против manifest | Остановить flow, считать release invalid |
| installer reject / signature mismatch | Оставить текущую версию, зафиксировать install failure |
| user cancel install | Оставить текущую версию, считать это штатным отказом |

## Failure policy

### Download interrupted

Поведение:

- update attempt завершается ошибкой;
- APK не считается частично применённым;
- текущий shell продолжает работу на старой версии.

### Hash mismatch

Поведение:

- installer не вызывается;
- скачанный файл считается недоверенным;
- shell пишет явный diagnostic reason `apk_hash_mismatch`.

### Package mismatch

Поведение:

- installer не вызывается;
- событие трактуется как ошибка публикации или compromise release artifact;
- shell не должен предлагать оператору `всё равно установить`.

### Signature mismatch / install rejected

Поведение:

- authority остаётся у старой установленной версии;
- shell фиксирует, что trusted signing path не подтвердился;
- публикация считается broken и требует нового release/hotfix.

### User cancelled install

Поведение:

- это не security incident;
- shell остаётся в рабочем состоянии;
- при следующем manual check тот же APK может быть предложен снова.

## Rollback policy

### До установки

Rollback не нужен: устройство всё ещё на старом APK.

### После неуспешной установки

Rollback не нужен: устройство всё ещё на старом APK.

### После успешной установки

Автоматический rollback в MVP не поддерживается.

Разрешены только два пути:

1. выпустить новый hotfix APK с большим `appVersion`;
2. выполнить отдельную ручную сервисную операцию вне manifest flow.

Запрещено:

- рассчитывать на downgrade через manifest;
- публиковать старый APK как `rollback release` с меньшим `appVersion`;
- менять байты уже опубликованного APK по тому же URL.

## Publish invariants для `PL-071`

`PL-071` должна соблюдать следующие правила:

1. APK release artifacts immutable.
2. Один URL = один конкретный APK.
3. `sha256` считается после финальной сборки и подписания, а не до signing step.
4. Manifest публикуется только после готовности подписанного APK и рассчитанного `sha256`.
5. Publish channel явно разделяет:
   - test/debug artifacts;
   - operator-facing trusted artifacts.
6. Release keystore не смешивается с debug keystore.
7. `appVersion` и APK filename/version metadata не расходятся.

## Минимальный UX contract

Shell обязан ясно различать:

- `доступно обновление приложения`;
- `обновление приложения обязательно`;
- `скачивание не удалось`;
- `файл обновления повреждён`;
- `установка отклонена системой`;
- `установка отменена пользователем`.

Для MVP достаточно простого operator-facing текста без сложной локализации и без скрытых автодействий.

## Что это решение означает для следующего этапа

После этого документа `PL-071` уже можно делать предметно:

- раскладка `manifest.json`, `apk` и `config` на HTTPS;
- расчёт `sha256` после подписания;
- publish runbook для test/stable channel;
- smoke с планшета по реальному URL на VPS.

А `PL-072` получает явный клиентский contract:

- какие состояния update flow должны отображаться;
- какие диагностические события нужно писать;
- когда shell имеет право открывать installer, а когда обязан остановиться раньше.
