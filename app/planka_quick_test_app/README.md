# PLANKA Diagnostic Shell

Диагностический Android shell baseline для ручного прогона на планшете.

Что внутри:
- fullscreen `WebView` c локальным `HTML/CSS/JS` из `assets`
- versioned `ui-shell-config` с built-in defaults и fallback
- service-кнопка штатного выхода `×`
- parent-mode contour из `prototype/web`: `Р -> О -> Д` с удержанием, PIN gate и parent panel
- local recent-session baseline: сохранение черновика, локали и последних фраз в `localStorage` WebView
- reuse последних фраз через нижнюю recent-session ленту внутри shell
- on-screen breakout diagnostics overlay по кнопке `DIAG`
- `DBG` drawer внутри WebView с service actions `DIAG` / `FULL` / `EXPORT` / `RELOAD`
- JS/native service bridge c live shell snapshot и manual actions
- `singleTask` lifecycle + `FLAG_KEEP_SCREEN_ON`
- повторный immersive restore после `resume/focus/top-resumed/system-bars`
- внутренний rolling log в `<filesDir>/breakout-diagnostics/`
- экспорт текущего прогона в `Downloads/planka-breakout-<session>.txt` на Android 10+ (на более старых версиях fallback идёт в app-specific documents dir)

## Сборка
1. Открой папку проекта в Android Studio.
2. Дождись синхронизации Gradle.
3. Убедись, что локально доступен JDK 17 и `JAVA_HOME` указывает на установленный Java 17 runtime/toolchain.
4. Запусти `Run app` или `Build > Build APK(s)`.
5. APK будет в `app/build/outputs/apk/debug/app-debug.apk`.

## Что проверять на планшете
1. Запуск в landscape и восстановление fullscreen после `resume/focus`.
2. Поведение при верхней шторке и transient system bars.
3. Попытки ухода в `Home`, `Recent Apps` и launcher.
4. Возврат в shell после системного breakout.
5. `DBG` drawer: `DIAG`, `FULL`, `EXPORT`, `RELOAD`.
6. События в `DIAG` и экспорт итогового текстового лога.
7. Parent-mode: `Р -> О -> Д` + hold `Д` 3 секунды, затем PIN `2580`.
8. Level-2 contour: из parent panel открыть Android settings через PIN `9000`.
9. Возврат из parent panel в детский режим и восстановление последней сессии после reload/restart shell.

Baseline-документ для follow-up Android-задач:
- [PL-072 Android diagnostic shell build](../../docs/pl-072-android-diagnostic-shell-build.md)
- [PL-083 Android parent-mode and recent-session port](../../docs/pl-083-android-parent-mode-and-recent-session.md)

## Android Breakout Diagnostics

Surface:
- кнопка `DIAG` в левом верхнем углу
- кнопка `DBG` внутри WebView для service drawer
- overlay с live-логом и `session/internal/export path`
- bridge-метод `AndroidApp.getBreakoutDiagnosticsLog()`
- bridge-метод `AndroidApp.getShellSnapshot()`
- bridge-service actions `setDiagnosticsPanelVisible` / `requestFullscreenRefresh` / `exportDiagnosticsLog` / `reloadShell` / `openSystemSettings`
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
- `TOP_RESUMED_CHANGED` доступен только на Android 10+; если callback не поддерживается, в строках остаётся `topResumed=?`
- `USER_LEAVE_HINT` это proxy-сигнал для `Home` / `Recent Apps` / launcher / external surface
- `TRIM_MEMORY` с `ui_hidden` это best-effort признак скрытия shell UI системой
- `RETURN_TO_FOREGROUND` фиксирует восстановление после background/focus loss
- `FULLSCREEN_RESTORED` фиксирует, что после hide-request системные бары снова стали hidden

Smoke-flow:
1. Нажать `DIAG`.
2. Открыть `DBG` и проверить snapshot shell-state.
3. Воспроизвести breakout: верхняя шторка, transient bars, `Home`, `Recent Apps`, возврат.
4. Сверить `WINDOW_FOCUS_CHANGED`, `USER_LEAVE_HINT`, `ACTIVITY_STOP`, `RETURN_TO_FOREGROUND`.
5. Проверить новый `HIDE_SYSTEM_UI_REQUEST` и `FULLSCREEN_RESTORED`.
6. Сохранить лог через `Экспорт txt` или `EXPORT`.

Детальный event-contract и sample output:
- [PL-066 Android breakout diagnostics](../../docs/pl-066-android-breakout-diagnostics.md)
- [PL-066 breakout log sample](../../docs/pl-066-breakout-log.sample.txt)

## PL-083 UX Port

Что добавлено поверх диагностического baseline:
- parent-mode entry contour из `prototype/web`: последовательность `Р -> О -> Д` и удержание `Д` 3 секунды
- PIN gate уровня 1 и parent panel с быстрыми функциями для recent-session summary
- level-2 PIN contour открывает Android system settings через native bridge `openSystemSettings`
- recent-session storage в `localStorage`: текущий черновик, текущая локаль и до 6 последних фраз
- нижняя лента `Недавние фразы` с сохранением текущего текста и быстрым восстановлением последней фразы
- back/escape сначала закрывает parent overlays и `DBG`, не ломая существующий native back bridge

Что осталось вне scope этой дельты:
- более управляемый возврат из Android settings обратно в shell после level-2 breakout
- backend sync для истории фраз и session payload
- более широкий перенос UX из `prototype/web` за пределами parent-mode и recent-session slice

## Что менять быстро

Через config-contract:
- `app/src/main/assets/ui-shell-config.default.json`
- `app/src/main/assets/ui-shell-config.schema.json`
- `<filesDir>/ui-shell-config.active.json`

Если active config отсутствует, несовместим с shell или не проходит валидацию, приложение откатывается на built-in defaults из assets. Если повреждён и bundled asset, shell использует emergency defaults из `UiShellConfig.kt`.
