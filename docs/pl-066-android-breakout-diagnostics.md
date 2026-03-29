# PL-066: Android breakout diagnostics

## Цель

В `app/planka_quick_test_app` диагностический контур должен за один прогон показать, где ломается fullscreen / pseudo-kiosk:
- потеря `window focus`
- `resume/pause/stop/restart`
- показ и скрытие system bars
- proxy-сигналы ухода в `Home` / `Recent Apps` / launcher
- попытка shell восстановить fullscreen после возврата

## Surface

Локальные точки доступа:
- on-screen overlay по кнопке `DIAG`
- live-лог поверх `WebView`
- внутренний rolling log в `<filesDir>/breakout-diagnostics/`
- экспорт в `Downloads/planka-breakout-<session>.txt`
- `AndroidApp.getBreakoutDiagnosticsLog()` для WebView-side debug

## Event List

Lifecycle и shell:
- `SESSION_START`
- `ACTIVITY_START`
- `ACTIVITY_RESUME`
- `ACTIVITY_PAUSE`
- `ACTIVITY_STOP`
- `ACTIVITY_RESTART`
- `ACTIVITY_DESTROY`
- `SAVE_INSTANCE_STATE`
- `HIDE_SYSTEM_UI_REQUEST`
- `HIDE_SYSTEM_UI_APPLIED`
- `FULLSCREEN_RESTORED`
- `BACK_PRESSED_BRIDGE`
- `EXPORT_LOG_SUCCESS`
- `EXPORT_LOG_FAILURE`

Focus / task ownership:
- `WINDOW_FOCUS_CHANGED`
- `TOP_RESUMED_CHANGED`
  Доступен только на Android 10+ (`API 29+`); на более старых устройствах поле `topResumed` в строке лога остаётся `?`.

System UI:
- `SYSTEM_BARS_CHANGED`
  `detail=status=<0|1>,nav=<0|1>` даёт точный state status/navigation bars.

Proxy / best-effort:
- `USER_LEAVE_HINT`
  `onUserLeaveHint()` не различает `Home`, `Recent Apps`, launcher и часть external surfaces, поэтому трактуется как proxy breakout.
- `TRIM_MEMORY`
  Для этой задачи логируется только `TRIM_MEMORY_UI_HIDDEN` и выше как best-effort сигнал скрытия UI.
- `RETURN_TO_FOREGROUND`
  Фиксируется после `pause/stop` или после `focus regain`, если shell пытается восстановиться.
- `FULLSCREEN_RESTORED`
  Пишется только когда после recovery hide-request статус/nav bars снова стали hidden, а не просто по факту отправки запроса.

## Log Format

Заголовок:

```text
# PLANKA Android breakout diagnostics
# session=20260327-120005-421
# internalPath=/data/user/0/com.planka.quicktest/files/breakout-diagnostics/planka-breakout-20260327-120005-421.log
# exportPath=Downloads/planka-breakout-20260327-120005-421.txt
```

Строка события:

```text
2026-03-27T12:00:05.976Z | seq=0006 | session=20260327-120005-421 | event=SYSTEM_BARS_CHANGED | focus=1 | started=1 | resumed=1 | topResumed=1 | bars=status:0,nav:0 | leaveHint=0 | detail=status=0,nav=0
```

Поля:
- `focus`, `started`, `resumed`, `topResumed` это текущий activity-state на момент записи
- `topResumed=?` означает, что значение ещё не наблюдалось или платформа не даёт этот callback
- `bars=status:...,nav:...` это видимость status/navigation bars (`1` visible, `0` hidden, `?` пока неизвестно)
- `leaveHint=1` означает pending proxy breakout до подтверждения возврата
- `detail` уточняет причину, proxy-сигнал или recovery path

Типовые `detail`:
- `proxy_home_recents_launcher_or_external_surface`
- `background_after_user_leave_hint`
- `background_without_user_leave_hint`
- `status=1,nav=0`
- `status=0,nav=0`
- `after_background`
- `after_background_return_hide_request`
- `after_leave_hint_hide_request`
- `best_effort_after_pause_stop`
- `best_effort_after_focus_regain`

## Smoke Run

1. Запустить shell на планшете.
2. Нажать `DIAG`.
3. Воспроизвести один breakout-сценарий:
   - верхняя шторка;
   - transient system bars;
   - `Home`;
   - `Recent Apps`;
   - возврат в shell.
4. Проверить в логе:
   - потерю `WINDOW_FOCUS_CHANGED` и/или `TOP_RESUMED_CHANGED`;
   - `USER_LEAVE_HINT`;
   - `ACTIVITY_PAUSE` / `ACTIVITY_STOP`;
   - `RETURN_TO_FOREGROUND`;
   - новый `HIDE_SYSTEM_UI_REQUEST` и `FULLSCREEN_RESTORED`.
5. Нажать `Экспорт txt` и приложить экспорт к follow-up issue.

## Reference Output

Репозиторий содержит reference sample-текст с полным breakout flow:
- [docs/pl-066-breakout-log.sample.txt](pl-066-breakout-log.sample.txt)

Это reference формата и состава событий, собранный с детерминированного unit-test smoke-flow, а не аппаратный лог.

## Device Log Status

Обязательный real device-log для Lenovo Tab M10 FHD Plus TB-X606X пока не зафиксирован в этом worktree: текущее окружение не имеет доступа к подключённому планшету и не может снять аппаратный прогон самостоятельно. Для полного acceptance нужен отдельный device-run с экспортом из самой панели `DIAG`.
