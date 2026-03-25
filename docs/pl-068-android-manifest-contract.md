# PL-068: HTTPS manifest contract для Android shell

## Цель

Зафиксировать один канонический контракт обновлений для Android shell, publish-инфраструктуры и операторского runbook.

Контракт должен покрывать два сценария MVP:

- лёгкое обновление конфигурации без переустановки APK;
- полное обновление APK через системный Android installer.

## Границы решения

Этот документ намеренно не вводит:

- фоновые проверки manifest;
- silent install или скрытые OTA-механизмы;
- delta/binary patching для APK;
- downgrade APK через manifest;
- сложную серверную оркестрацию каналов, staged rollout и cohorting.

Для MVP источник истины один: shell вручную запрашивает один HTTPS manifest и принимает решение локально.

## Итоговое решение

1. Android shell знает один well-known HTTPS endpoint manifest.
2. Manifest всегда описывает одновременно:
   - текущий опубликованный APK-релиз;
   - текущий опубликованный config-релиз;
   - минимальную версию shell, с которой этот config разрешено применять.
3. Manifest является полным snapshot-состоянием канала публикации, а не частичным patch-ответом:
   - поля `apk` и `config` обязательны всегда;
   - отсутствие новой APK или нового config для конкретного устройства выражается только сравнением версий на клиенте, а не отсутствием секции в JSON.
4. Конфиг-канал в MVP публикует полный config-файл, а не patch/diff.
5. Проверка обновлений запускается только вручную по явному действию пользователя.
6. Config update может применяться сразу после успешной проверки и валидации.
7. APK update никогда не ставится скрытно: только после явного подтверждения пользователя и через системный installer.

## Канонический manifest contract

### Endpoint

- Shell хранит один настроенный `manifestUrl`.
- URL manifest и URL артефактов должны быть `https://`.
- Manifest читается как JSON-документ UTF-8.

### Schema v1

```json
{
  "schemaVersion": 1,
  "appVersion": 3,
  "appVersionName": "0.3.0",
  "configVersion": 7,
  "minSupportedAppVersion": 2,
  "message": "Обновлена логика fullscreen и поведение клавиатуры",
  "apk": {
    "url": "https://updates.example.com/planka/planka-0.3.0.apk",
    "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  },
  "config": {
    "url": "https://updates.example.com/planka/config-7.json",
    "sha256": "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
  }
}
```

### Поля и семантика

| Поле | Тип | Обязательно | Семантика |
| --- | --- | --- | --- |
| `schemaVersion` | integer | да | Версия самого manifest contract. Для этой задачи фиксируется `1`. |
| `appVersion` | integer | да | Каноническая версия Android shell, сравнимая с `versionCode`. Только монотонный рост. |
| `appVersionName` | string | да | Человекочитаемая версия APK для UI и runbook, например `0.3.0`. |
| `configVersion` | integer | да | Каноническая версия config payload. Только монотонный рост. |
| `minSupportedAppVersion` | integer | да | Минимальный `appVersion`, который имеет право применять `config` из текущего manifest. |
| `message` | string | да | Короткое user-facing сообщение, допустимое для показа в shell без дополнительной обработки. |
| `apk.url` | string | да | Абсолютный HTTPS URL до APK. |
| `apk.sha256` | string | да | SHA-256 APK в hex-формате. |
| `config.url` | string | да | Абсолютный HTTPS URL до полного config-файла. |
| `config.sha256` | string | да | SHA-256 config-файла в hex-формате. |

Дополнительные поля:

- в schema v1 не требуются;
- при появлении дополнительных полей shell v1 обязан игнорировать их, если обязательные поля schema v1 валидны.

### Обязательные правила валидации

Manifest считается валидным только если одновременно выполняется всё ниже:

1. `schemaVersion == 1`.
2. `appVersion >= 1`.
3. `configVersion >= 1`.
4. `minSupportedAppVersion >= 1`.
5. `minSupportedAppVersion <= appVersion`.
6. `appVersionName` и `message` непустые после trim.
7. `apk.url` и `config.url` используют схему `https`.
8. `apk.sha256` и `config.sha256` состоят ровно из 64 hex-символов.
9. Объекты `apk` и `config` присутствуют целиком, без частичного пропуска обязательных полей.

Если manifest не проходит хотя бы одно правило, shell отвергает его целиком и не начинает ни config update, ни APK update.

## Правила сравнения версий

Shell хранит локально как минимум:

- `installedAppVersion`: версия установленного APK;
- `activeConfigVersion`: версия активного локального config;
- `lastKnownGoodConfigVersion`: версия последнего config, который удалось успешно применить.

Сравнение выполняется так:

1. `apkUpdateAvailable = manifest.appVersion > installedAppVersion`
2. `appUpdateRequired = installedAppVersion < manifest.minSupportedAppVersion`
3. `configUpdateAvailable = manifest.configVersion > activeConfigVersion`
4. `configUpdateAllowed = installedAppVersion >= manifest.minSupportedAppVersion`

Следствия:

- если `appUpdateRequired == true`, shell не применяет config из этого manifest;
- если `configUpdateAvailable == true`, но `configUpdateAllowed == false`, shell считает APK обязательным prerequisite;
- если `apkUpdateAvailable == false` и `appUpdateRequired == true`, manifest считается операторской ошибкой публикации: он требует новый shell, но не даёт rescue APK.

## Каноническая decision table

| Условие | Итоговое состояние клиента | Что разрешено делать |
| --- | --- | --- |
| `apkUpdateAvailable == false` и `configUpdateAvailable == false` | `up_to_date` | Ничего не скачивать, показать `Обновлений нет` |
| `configUpdateAvailable == true` и `configUpdateAllowed == true` и `apkUpdateAvailable == false` | `config_update_available` | Скачать и применить config |
| `apkUpdateAvailable == true` и (`configUpdateAvailable == false` или `configUpdateAllowed == false`) и `appUpdateRequired == false` | `apk_update_available` | Показать новый APK и предложить установку |
| `apkUpdateAvailable == true` и `appUpdateRequired == true` | `apk_update_required` | Не применять config, требовать APK как prerequisite |
| `installedAppVersion < minSupportedAppVersion` и `manifest.appVersion <= installedAppVersion` | `manifest_inconsistent` | Ничего не применять, показать операторскую ошибку |

Эта таблица канонична для:

- Android shell;
- publish automation;
- операторского runbook и ручной диагностики.

## Client flow: manual update check

### Базовый сценарий

1. Пользователь нажимает `Проверить обновления`.
2. Shell скачивает manifest по HTTPS.
3. Shell валидирует JSON и contract rules.
4. Shell вычисляет состояние `config` и `apk`.
5. Shell фиксирует один итоговый результат проверки (`up_to_date`, `config_updated`, `apk_available`, `apk_required`, `error`).
6. Дальше выполняется один из сценариев ниже.

### Сценарий A: обновлений нет

Условия:

- `apkUpdateAvailable == false`
- `configUpdateAvailable == false`

Поведение:

- показать нейтральный результат `Обновлений нет`;
- не менять локальное состояние.

### Сценарий B: доступен только config update

Условия:

- `configUpdateAvailable == true`
- `configUpdateAllowed == true`
- `apkUpdateAvailable == false`

Поведение:

1. Скачать `config.url` во временный файл.
2. Проверить `sha256`.
3. Провалидировать формат config на стороне клиента.
4. Атомарно заменить активный config.
5. Обновить `activeConfigVersion`.
6. Показать `message` и результат `Конфигурация обновлена`.

Побочный эффект:

- `lastKnownGoodConfigVersion` обновляется только после успешной активации нового config.

### Сценарий C: доступен только APK update

Условия:

- `apkUpdateAvailable == true`
- `configUpdateAvailable == false` или `configUpdateAllowed == false`

Поведение:

1. Показать экран/диалог `Доступно обновление приложения`.
2. Показать `message`, `appVersionName` и явную кнопку подтверждения установки.
3. До подтверждения пользователя ничего не скачивать и не устанавливать.
4. После подтверждения скачать APK во временный файл.
5. Проверить `sha256`.
6. Передать файл системному installer.

Правило состояния:

- до подтверждённого результата Android installer shell не меняет `installedAppVersion` в локальном persistent state;
- новая версия shell считается установленной только после следующего старта приложения, когда runtime видит новый фактический `versionCode`.

### Сценарий D: доступны оба канала

Условия:

- `configUpdateAvailable == true`
- `apkUpdateAvailable == true`

Поведение:

1. Если `appUpdateRequired == true`, приоритет у APK:
   - config не применять;
   - показать обязательность обновления shell;
   - предложить установку APK.
2. Если `appUpdateRequired == false`, сначала применить config update.
3. После успешного config update всё равно показать, что доступен новый APK.
4. Если пользователь отменил APK install после уже успешного config update, активным остаётся новый config:
   - это не rollback case;
   - повторная проверка обновлений позже снова предложит тот же APK, пока `installedAppVersion` не догонит manifest.

Такой порядок сохраняет пользу лёгких config-изменений, но не позволяет применить config, который требует более новый shell.

## Error handling и failure policy

### Ошибка загрузки или парсинга manifest

Причины:

- сеть недоступна;
- HTTP error;
- невалидный JSON;
- manifest не проходит contract validation.

Поведение:

- показать ошибку проверки обновлений;
- оставить текущие APK и config без изменений;
- не удалять `lastKnownGoodConfig`.
- считать результат manual check как `error`.

### Ошибка загрузки или проверки config

Причины:

- `config.url` не скачался;
- `sha256` не совпал;
- config не прошёл локальную валидацию;
- применение config завершилось ошибкой.

Поведение:

- не менять активный config, если ошибка произошла до атомарной активации;
- если ошибка произошла во время применения после подмены файла, немедленно вернуть `lastKnownGoodConfig`;
- показать пользователю ошибку config update;
- если в том же manifest есть APK update, shell всё ещё может предложить APK update.
- не менять `activeConfigVersion`, если новый config не стал активным и подтверждённо рабочим.

### Ошибка загрузки или проверки APK

Причины:

- APK не скачался;
- `sha256` не совпал;
- системный installer не стартовал;
- пользователь отменил установку.

Поведение:

- текущая установленная версия остаётся рабочей;
- shell не меняет локальный config из-за ошибки APK;
- при отмене установки это считается штатным отказом, а не corrupt state.
- если config уже был успешно обновлён в том же manual check, он не откатывается только из-за отмены или ошибки APK install.

### Manifest требует новый shell, но rescue APK не опубликован

Условия:

- `installedAppVersion < minSupportedAppVersion`
- `manifest.appVersion <= installedAppVersion`

Поведение:

- считать release неконсистентным;
- не применять config;
- показать операторскую ошибку публикации;
- оставаться на текущем локальном состоянии.

## Rollback semantics

### Config rollback

Поддерживается в MVP.

Правила:

1. Shell держит один активный config и один `lastKnownGoodConfig`.
2. Новый config сначала скачивается и валидируется отдельно от активного.
3. Активация выполняется атомарной заменой.
4. Если активация неуспешна, shell откатывается на `lastKnownGoodConfig`.
5. Операторский rollback делается не уменьшением `configVersion`, а публикацией нового manifest с `configVersion = N+1`, указывающего на предыдущий стабильный config payload или его эквивалентную копию.

Запрещено:

- переиспользовать старый `configVersion` для нового содержимого;
- откатывать config через уменьшение version number.

### APK rollback

Автоматический rollback через manifest в MVP не поддерживается.

Причины:

- Android install flow не даёт безопасный silent rollback;
- downgrade `versionCode` обычно невозможен без отдельной ручной операции;
- скрытая переустановка противоречит MVP-ограничению на отсутствие opaque OTA-магии.

Правила:

1. До подтверждённой установки устройство остаётся на старом APK.
2. После неуспешной установки устройство остаётся на старом APK.
3. После успешной установки rollback возможен только:
   - выпуском нового hotfix APK с более высоким `appVersion`;
   - либо ручной операторской переустановкой вне manifest flow.

Запрещено:

- публиковать manifest, рассчитывающий на downgrade APK по меньшему `appVersion`;
- менять байты уже опубликованного APK по тому же URL.

## Publish/runbook invariants

Чтобы contract был одинаково понятен shell и publish-инфраструктуре, публикация должна соблюдать инварианты:

1. Все URL в manifest immutable: один URL соответствует одному конкретному байтовому артефакту.
2. Сначала публикуются APK/config, затем считаются их SHA-256, и только потом публикуется новый manifest.
3. Manifest публикуется последним шагом как переключение указателя на новый релиз.
4. `appVersion` и `configVersion` всегда монотонно растут.
5. `message` должен быть коротким и безопасным для показа на устройстве без markdown/html.
6. Config channel публикует полный config-файл, а не частичный patch, чтобы rollback и валидация оставались простыми.
7. Manifest является единственным mutable-объектом в release flow: shell должен на каждом manual check запрашивать его с сетевой revalidation, а publish-слой не должен допускать долгоживущий stale-cache для `manifest.json`.
8. Публикация не должна убирать секции `apk` или `config` из manifest, даже если в текущем релизе изменился только один канал.

## MVP summary для следующих задач

Этот contract задаёт базу для `PL-069`, `PL-070` и `PL-071`:

- `PL-069`: клиентская реализация manual update check и UI-решений по состояниям;
- `PL-070`: реализация config storage/apply/rollback;
- `PL-071`: publish pipeline, hash generation и manifest publication.

Канонический статус MVP:

- один HTTPS manifest;
- ручная проверка;
- config apply без переустановки;
- APK install только через системное подтверждение;
- rollback для config поддержан;
- rollback для APK только через hotfix или ручную операцию.
