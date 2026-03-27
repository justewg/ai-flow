# PLANKA Quick Test

Быстрый Android shell для ручного прогона на планшете.

Что внутри:
- fullscreen `WebView` c локальным `HTML/CSS/JS` из `assets`
- versioned `ui-shell-config` с built-in defaults и fallback
- service-кнопка штатного выхода `×`
- on-screen breakout diagnostics overlay по кнопке `DIAG`
- внутренний rolling log в `<filesDir>/breakout-diagnostics/`
- экспорт текущего прогона в `Downloads/planka-breakout-<session>.txt` на Android 10+ (на более старых версиях fallback идёт в app-specific documents dir)

## Сборка
1. Открой папку проекта в Android Studio.
2. Дождись синхронизации Gradle.
3. Запусти `Run app` или `Build > Build APK(s)`.
4. APK будет в `app/build/outputs/apk/debug/app-debug.apk`.

## Что проверять на планшете
1. Запуск в landscape и восстановление fullscreen после `resume/focus`.
2. Поведение при верхней шторке и transient system bars.
3. Попытки ухода в `Home`, `Recent Apps` и launcher.
4. Возврат в shell после системного breakout.
5. События в `DIAG` и экспорт итогового текстового лога.

## Android Breakout Diagnostics

Surface:
- кнопка `DIAG` в левом верхнем углу
- overlay с live-логом и `session/internal/export path`
- bridge-метод `AndroidApp.getBreakoutDiagnosticsLog()`
- экспорт по кнопке `Экспорт txt`

События shell:
- `SESSION_START`
- `ACTIVITY_START`
- `ACTIVITY_RESUME`
- `ACTIVITY_PAUSE`
- `ACTIVITY_STOP`
- `ACTIVITY_RESTART`
- `ACTIVITY_DESTROY`
- `TOP_RESUMED_CHANGED`
- `WINDOW_FOCUS_CHANGED`
- `USER_LEAVE_HINT`
- `TRIM_MEMORY`
- `SAVE_INSTANCE_STATE`
- `SYSTEM_BARS_CHANGED`
- `HIDE_SYSTEM_UI_REQUEST`
- `HIDE_SYSTEM_UI_APPLIED`
- `RETURN_TO_FOREGROUND`
- `FULLSCREEN_RESTORED`
- `BACK_PRESSED_BRIDGE`
- `EXPORT_LOG_SUCCESS`
- `EXPORT_LOG_FAILURE`

Формат строки:

```text
2026-03-27T12:00:05.976Z | seq=0006 | session=20260327-120005-421 | event=SYSTEM_BARS_CHANGED | focus=1 | started=1 | resumed=1 | topResumed=1 | bars=status:0,nav:0 | leaveHint=0 | detail=status=0,nav=0
```

Интерпретация:
- `USER_LEAVE_HINT` это proxy-сигнал для `Home` / `Recent Apps` / launcher / external surface
- `TRIM_MEMORY` с `ui_hidden` это best-effort признак скрытия shell UI системой
- `RETURN_TO_FOREGROUND` фиксирует восстановление после background/focus loss
- `FULLSCREEN_RESTORED` фиксирует, что после hide-request системные бары снова стали hidden

Smoke-flow:
1. Нажать `DIAG`.
2. Воспроизвести breakout: верхняя шторка, transient bars, `Home`, `Recent Apps`, возврат.
3. Сверить `WINDOW_FOCUS_CHANGED`, `USER_LEAVE_HINT`, `ACTIVITY_STOP`, `RETURN_TO_FOREGROUND`.
4. Проверить новый `HIDE_SYSTEM_UI_REQUEST` и `FULLSCREEN_RESTORED`.
5. Сохранить лог через `Экспорт txt`.

Детальный event-contract и sample output:
- [PL-066 Android breakout diagnostics](../../docs/pl-066-android-breakout-diagnostics.md)
- [PL-066 breakout log sample](../../docs/pl-066-breakout-log.sample.txt)

## Что менять быстро

Через config-contract:
- `app/src/main/assets/ui-shell-config.default.json`
- `app/src/main/assets/ui-shell-config.schema.json`
- `<filesDir>/ui-shell-config.active.json`

Если active config отсутствует, несовместим с shell или не проходит валидацию, приложение откатывается на built-in defaults из assets. Если повреждён и bundled asset, shell использует emergency defaults из `UiShellConfig.kt`.
