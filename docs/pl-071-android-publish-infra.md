# PL-071: publish infrastructure для Android release artifacts

## Цель

Поднять минимальную, но воспроизводимую release-инфраструктуру для Android shell:

- APK;
- config payload;
- `manifest.json`.

Результат должен быть пригоден для реального HTTPS update path с планшета и не смешивать Android artifacts с обычным web snapshot без явного trust boundary.

## Каноническая boundary

Для MVP допустимо использовать тот же домен `planka.ewg40.ru`, но не тот же deploy-root, что и обычный web snapshot.

Канонический вариант:

- public base URL: `https://planka.ewg40.ru/android-shell`
- server deploy root: `/var/sites/planka-android-shell`

То есть Android release channel живёт:

- на том же origin;
- в отдельном namespace;
- в отдельном файловом root.

Это упрощает TLS/hosting, но не смешивает release artifacts с обычным `DEPLOY_PATH=/var/sites/planka`.

## Layout на диске и по HTTPS

Канонический layout:

```text
/var/sites/planka-android-shell/
  stable/
    manifest.json
    releases/
      app-v3_config-v7/
        planka-shell-0.3.0.apk
        config-v7.json
        manifest.json
        release-metadata.json
```

Публичные URL при этом выглядят так:

```text
https://planka.ewg40.ru/android-shell/stable/manifest.json
https://planka.ewg40.ru/android-shell/stable/releases/app-v3_config-v7/planka-shell-0.3.0.apk
https://planka.ewg40.ru/android-shell/stable/releases/app-v3_config-v7/config-v7.json
https://planka.ewg40.ru/android-shell/stable/releases/app-v3_config-v7/manifest.json
```

## Почему layout именно такой

1. `manifest.json` в корне channel — единственный mutable object.
2. Все файлы внутри `releases/<release-id>/` immutable.
3. Один `release-id` описывает ровно один published snapshot канала.
4. Повторная публикация не переписывает старые APK/config, а создаёт новый release directory.

## Что автоматизируется уже сейчас

В repo добавлены два entrypoint:

- `scripts/android_release/render_manifest.sh`
- `scripts/android_release/publish_release.sh`

### `render_manifest.sh`

Отвечает только за manifest JSON по contract `PL-068`.

На вход получает:

- app/config версии;
- `message`;
- абсолютные HTTPS URL;
- `sha256`.

На выходе даёт canonical `manifest.json`.

### `publish_release.sh`

Отвечает за publish cycle:

1. принимает локальный APK и config payload;
2. копирует их в versioned release directory;
3. считает `sha256`;
4. рендерит `manifest.json` для этого release;
5. публикует channel-level `manifest.json` последним шагом.

Это важно: switch канала происходит только после готовности artifacts и hashes.

## Пример команды публикации

```bash
scripts/android_release/publish_release.sh \
  --deploy-root /var/sites/planka-android-shell \
  --public-base-url https://planka.ewg40.ru/android-shell \
  --channel stable \
  --apk-file /tmp/planka-shell-0.3.0.apk \
  --config-file /tmp/config-v7.json \
  --app-version 3 \
  --app-version-name 0.3.0 \
  --config-version 7 \
  --min-supported-app-version 2 \
  --message "Обновлён fullscreen flow и новый config layout"
```

## Что остаётся ручным на MVP-этапе

Ручными остаются:

1. сборка APK;
2. подпись release APK;
3. подготовка config payload;
4. решение, какой channel обновлять (`stable`, позже `test`);
5. smoke-проверка с планшета.

Не делаем пока:

- auto-build release APK в GitHub Actions;
- background rollout;
- promotion между каналами;
- auto-prune старых релизов.

## Retention policy

Минимальный policy для MVP:

1. хранить как минимум:
   - текущий stable release;
   - предыдущий stable release.
2. не удалять release directory сразу после публикации следующего.
3. удалять старые release directories только отдельной ручной housekeeping-операцией.

Это нужно для ручной диагностики и для hotfix-сценариев, даже если APK rollback через manifest не поддерживается.

## HTTP/cache policy

Канонические правила:

1. `manifest.json` должен отдаваться с коротким TTL или `no-cache`/revalidation policy.
2. Файлы внутри `releases/<release-id>/` можно отдавать как immutable static artifacts.
3. Shell при manual check всегда заново запрашивает `manifest.json`.

## Smoke checklist

После каждой публикации оператор должен проверить:

1. `curl -fsS https://planka.ewg40.ru/android-shell/stable/manifest.json`
2. `curl -I <apk-url>`
3. `curl -I <config-url>`
4. совпадает ли `sha256` локально с тем, что опубликовано в manifest
5. видит ли планшет новый `manifest.json` и корректно ли распознаёт update state

## Что нужно на VPS

Для реального канала на сервере нужны:

1. отдельный deploy root, например `/var/sites/planka-android-shell`;
2. nginx/static hosting для `/android-shell/`;
3. writable operator path для публикации релизов;
4. доступность URL с планшета по HTTPS.

## Следующий практический шаг

После этого документа и скриптов `PL-071` можно дожать live-частью:

1. завести реальный deploy root на VPS;
2. опубликовать тестовый APK и config через `publish_release.sh`;
3. проверить `manifest.json` с планшета;
4. зафиксировать runbook и smoke evidence.
