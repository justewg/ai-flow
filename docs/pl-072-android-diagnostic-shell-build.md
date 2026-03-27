# PL-072: Android diagnostic shell build baseline

## Цель

Зафиксировать `app/planka_quick_test_app` как диагностический shell baseline для следующих Android-задач:

- kiosk-hardening;
- breakout diagnostics на реальном Lenovo;
- будущий manual update channel.

Это всё ещё тестовое приложение MVP-уровня, а не production kiosk shell.

## Что считается baseline

Shell build обязан давать:

- offline startup из локальных `assets`;
- один предсказуемый `singleTask`-entry в landscape;
- повторный immersive recovery после `resume`, `focus regain`, `top resumed` и появления system bars;
- локальный `WebView` shell без сетевой зависимости;
- service bridge между JS и native для ручных диагностических действий;
- breakout diagnostics overlay и экспорт текстового лога;
- установку на Lenovo без скрытых шагов кроме обычной установки debug APK.

## Native shell surface

Нативная часть в `MainActivity` теперь держит управляемый shell state:

- `FLAG_KEEP_SCREEN_ON`;
- `launchMode="singleTask"`;
- повторный fullscreen restore с несколькими delayed-attempts;
- live snapshot состояния shell (`focus`, `resume`, `topResumed`, `lastImmersiveReason`, config source);
- native diagnostics panel c сервисными кнопками:
  - `DIAG`
  - `FS NOW`
  - `Reload UI`
  - `Экспорт txt`

## JS/native bridge

Bridge публикуется в `WebView` как `AndroidApp`.

Поддерживаемые методы baseline:

- `getUiShellConfig()`
- `getUiShellConfigDiagnostics()`
- `getBreakoutDiagnosticsLog()`
- `getShellSnapshot()`
- `setDiagnosticsPanelVisible(boolean)`
- `requestFullscreenRefresh(reason)`
- `exportDiagnosticsLog()`
- `reloadShell()`
- `exitApp()`

Также native shell пушит live snapshot в web через `window`-event:

- `planka:shell-status`

Это текущий service contract для ручных тестов; follow-up задачи должны расширять его осторожно и обратно-совместимо.

## Web diagnostics entry

В `assets/index.html` поверх основной text/keyboard baseline добавлен compact drawer `DBG`:

- не меняет базовую geometry keyboard/text split;
- показывает shell snapshot и config source;
- открывает native diagnostics panel;
- запускает fullscreen recovery;
- экспортирует breakout log;
- перезагружает локальный shell.

То есть ручной smoke теперь возможен и через native overlay, и через WebView-side service drawer.

## Install / smoke на Lenovo

1. Собрать `debug` APK.
2. Передать APK на планшет через USB в `Download`.
3. Установить APK обычным Android installer.
4. Запустить `PLANKA Diagnostic Shell`.
5. Проверить:
   - старт без сети;
   - landscape shell;
   - `DBG` drawer и `DIAG`;
   - `FS NOW` / `FULL` после transient bars;
   - экспорт breakout log в `Downloads`.

## Вне текущего baseline

В этот scope намеренно не вошли:

- сетевой manifest/update client;
- background polling;
- device-owner / lock-task kiosk-hardening;
- production-grade recovery orchestration;
- silent install.

Эти темы зависят от подтверждения системного поведения на Lenovo и идут следующими задачами.
