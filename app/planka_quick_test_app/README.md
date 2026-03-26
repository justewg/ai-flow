# PLANKA Quick Test

Быстрый Android Studio проект для теста планшета.

Что внутри:
- полноэкранное приложение
- локальный HTML/CSS/JS в assets
- versioned UI config-contract с built-in defaults и fallback на defaults
- поле текста сверху
- тестовая клавиатура снизу
- кнопка штатного выхода `×` справа сверху

## Сборка
1. Открой папку проекта в Android Studio.
2. Дождись синхронизации Gradle.
3. `Run app` или `Build > Build APK(s)`.
4. Готовый APK будет в:
   `app/build/outputs/apk/debug/app-debug.apk`

## Установка
- либо напрямую из Android Studio на подключённый планшет
- либо перетащить `app-debug.apk` в папку `Download` на планшете и установить вручную

## Что проверить на планшете
1. Запуск и полноэкранность.
2. Можно ли вытянуть верхнюю шторку.
3. Можно ли выйти вниз свайпом.
4. Удобно ли попадать по кнопкам.
5. Достаточно ли крупен текст сверху.
6. Работает ли штатный выход `×`.

## Что менять быстро

Через config-contract:
- `app/src/main/assets/ui-shell-config.default.json` — built-in defaults для APK
- `app/src/main/assets/ui-shell-config.schema.json` — machine-readable contract `v1`
- `<filesDir>/ui-shell-config.active.json` — active override path для shell без пересборки APK

Инварианты contract `v1`:
- numeric и integer поля принимают только JSON numbers, без string coercion
- `keyboard.defaultLocale` обязан совпадать с одним из ключей `keyboard.locales`
- все locale-dependent label map обязаны содержать ровно тот же набор locale keys, что и `keyboard.locales`
- `keyboard.locales.*.rows[*].template.columns` обязан совпадать по длине с `keys`

Допустимо менять через config:
- `layout.textRatio`, `layout.keyboardRatio` и остальные интервалы из `layout.*`
- `shell.serviceButtonOrder`
- `shell.featureFlags.*`
- `keyboard.defaultLocale`
- `keyboard.locales.*.displayName`
- `keyboard.locales.*.rows[*].template.columns`
- `keyboard.locales.*.rows[*].keys`
- `labels.placeholder.*`
- `labels.serviceButtons.*`
- `labels.specialKeys.*`

Если `ui-shell-config.active.json` отсутствует, несовместим с shell или не проходит валидацию, приложение откатывается на built-in defaults из assets. Если повреждён и bundled asset, shell использует emergency defaults, зашитые в `UiShellConfig.kt`.
