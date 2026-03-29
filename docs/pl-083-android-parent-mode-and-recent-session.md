# PL-083: Android parent-mode и recent-session port

## Что переносит этот task

Эта дельта берёт `prototype/web` как functional reference и переносит в `app/planka_quick_test_app` первый полезный UX-slice поверх диагностического baseline из `PL-072`.

В scope вошли:

- parent-mode entry contour `Р -> О -> Д` с удержанием `Д` 3 секунды;
- PIN gate уровня 1 с тем же default PIN `2580`, что и в `prototype/web`;
- parent panel с быстрыми действиями по недавней сессии;
- level-2 PIN contour с вызовом Android system settings через native bridge;
- recent-session baseline внутри Android shell:
  - сохранение текущего черновика;
  - сохранение текущей локали;
  - сохранение до 6 последних фраз;
  - повторное использование последних фраз через отдельную ленту внутри shell;
- shell-side back contour: сначала закрываются parent overlays и `DBG`, затем остаётся штатный native bridge.

## Где реализовано

- `app/planka_quick_test_app/app/src/main/assets/index.html`
  - добавлены parent-mode trigger, PIN modal, parent panel, toast;
  - добавлен recent-session strip и `localStorage` persistence;
  - сохранён текущий diagnostic drawer и bridge к native shell.
- `app/planka_quick_test_app/app/src/main/java/com/planka/quicktest/MainActivity.kt`
  - добавлен native bridge-action `openSystemSettings` для level-2 parent contour;
  - расширен список `supportedServiceActions` без изменения existing diagnostics path.
- `app/planka_quick_test_app/README.md`
  - описан новый UX-slice и ручной smoke для parent-mode/recent-session.

## Что сохраняется из baseline PL-072

`PL-083` не заменяет диагностический shell и не меняет native lifecycle contract. Сохраняются:

- локальный offline startup из `assets`;
- fullscreen `WebView` shell;
- breakout diagnostics overlay;
- `DBG` drawer и existing service actions;
- JS/native bridge и live shell snapshot;
- текущий build path и diagnostic documentation baseline.

## Что остаётся follow-up

В эту задачу сознательно не вошли:

- более управляемый возврат из Android settings обратно в shell после level-2 breakout;
- backend sync или серверное хранение истории фраз;
- более широкий перенос UX из `prototype/web`, не относящийся к parent-mode / recent-session slice;
- kiosk-hardening и device-owner сценарии.
