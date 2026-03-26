# PL-067: config-driven contract для UI shell / WebView

## Цель

Зафиксировать versioned contract для UI-параметров Android shell и WebView, чтобы:

- менять keyboard/layout параметры без пересборки APK;
- валидировать config детерминированно до применения;
- при любой ошибке возвращаться к встроенным defaults без деградации offline startup.

## Артефакты

- machine-readable schema: `app/planka_quick_test_app/app/src/main/assets/ui-shell-config.schema.json`
- встроенный default payload: `app/planka_quick_test_app/app/src/main/assets/ui-shell-config.default.json`
- runtime resolver и validator: `app/planka_quick_test_app/app/src/main/java/com/planka/quicktest/UiShellConfig.kt`
- config-driven WebView shell: `app/planka_quick_test_app/app/src/main/assets/index.html`

Runtime override path для будущих PL-069 / PL-074:

- `filesDir/ui-shell-config.active.json`

Shell читает этот файл только если он существует. При любой ошибке чтения или валидации override-файл игнорируется целиком, а UI стартует на встроенном default payload.

## Версионирование и совместимость

Contract v1 задаётся полями:

```json
{
  "contractName": "planka.ui-shell",
  "contractVersion": 1,
  "configVersion": 1,
  "compatibility": {
    "minShellVersion": 1,
    "maxShellVersion": 2147483647
  }
}
```

Правила:

1. `contractName` обязан быть `planka.ui-shell`.
2. `contractVersion` обязан быть `1`.
3. `configVersion >= 1`.
4. shell применяет config только если текущий `versionCode` попадает в диапазон `compatibility.minShellVersion..maxShellVersion`.
5. если contract невалиден или несовместим, override не применяется и shell откатывается на built-in defaults.

Для MVP shell v1 использует strict validation: структура должна совпадать с schema v1 без лишних или пропущенных обязательных полей. Это намеренно повышает предсказуемость клавиатуры.

## Параметры, разрешённые к изменению через config

### Layout

- `layout.textRatio`
- `layout.keyboardRatio`
- `layout.appPaddingPx`
- `layout.sectionGapPx`
- `layout.keyGapPx`
- `layout.keyboardRowGapPx`
- `layout.textSizeMultiplier`
- `layout.keySizeMultiplier`

### Keyboard layouts

- `keyboard.defaultLocale`
- `keyboard.locales[*].displayName`
- `keyboard.locales[*].rows[*].id`
- `keyboard.locales[*].rows[*].template.columns`
- `keyboard.locales[*].rows[*].keys[*].kind`
- `keyboard.locales[*].rows[*].keys[*].value`

### Service buttons и feature flags

- `shell.featureFlags.showClearButton`
- `shell.featureFlags.showLocaleButton`
- `shell.featureFlags.showExitButton`
- `shell.serviceButtonOrder`

### Locale-dependent labels

- `labels.placeholder`
- `labels.serviceButtons.clear`
- `labels.serviceButtons.locale`
- `labels.serviceButtons.exit`
- `labels.specialKeys.space`
- `labels.specialKeys.backspace`
- `labels.specialKeys.enter`

Вне scope v1 намеренно оставлены:

- изменение HTML/CSS-цветов;
- произвольные новые service button id;
- частичный merge config поверх defaults;
- server fetch/apply logic.

## Defaults и fallback policy

Источник истины для built-in defaults: `ui-shell-config.default.json`.

Текущий baseline prototype из defaults:

- `textRatio = 1.0`
- `keyboardRatio = 0.95`
- `appPaddingPx = 8`
- `sectionGapPx = 10`
- `keyGapPx = 8`
- `keyboardRowGapPx = 8`
- `textSizeMultiplier = 1.0`
- `keySizeMultiplier = 1.0`
- locale layouts: `ru`, `en`
- topbar buttons: `clear`, `locale`, `exit`

Failure policy:

1. Нет runtime config: применяются built-in defaults.
2. Runtime config не читается: применяются built-in defaults.
3. Runtime config невалиден по schema/compatibility: применяются built-in defaults.
4. Built-in defaults недоступны или повреждены: используется emergency default, зашитый в `UiShellConfigResolver`.

Частичного применения нет: config принимается только целиком.

## Применение в shell

1. `MainActivity` вызывает `UiShellConfigResolver.resolve(...)`.
2. Resolver валидирует built-in defaults.
3. Resolver пробует прочитать `ui-shell-config.active.json`.
4. Если override валиден, в WebView передаётся он.
5. Если override невалиден, в WebView передаётся built-in default и diagnostics с причиной fallback.
6. `index.html` строит text area, keyboard rows, service buttons и locale labels только из нормализованного config payload.

Это оставляет startup полностью локальным и готовит стабильный config path для следующего шага публикации и доставки runtime-config.
