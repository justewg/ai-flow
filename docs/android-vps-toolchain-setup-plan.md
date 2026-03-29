# Android VPS Toolchain Runbook

## Цель

Дать один воспроизводимый operational path для Android/Java-задач в automation, не засоряя:

- host VPS;
- основной Codex/runtime container.

## Предпочтительная модель

Основной путь для Android-задач должен идти через standalone builder:

- service layer: `/.flow/shared/services/android-builder`
- wrapper: `./.flow/shared/scripts/run.sh android_builder ...`
- workspace монтируется в builder container как `/workspace`
- JDK 17 и Android SDK живут внутри отдельного Docker image
- артефакты сборки остаются в workspace

Канонический запуск:

```bash
./.flow/shared/scripts/run.sh android_builder up
./.flow/shared/scripts/run.sh android_builder run bash -lc 'cd app/planka_quick_test_app && ./gradlew --no-daemon testDebugUnitTest assembleDebug'
./.flow/shared/scripts/run.sh android_builder down
```

## Что делает builder

Builder image должен содержать:

- JDK 17
- Android command-line tools
- `platform-tools`
- одну актуальную Android platform/build-tools baseline для текущих задач

Builder не обязан покрывать:

- `adb` к реальному планшету
- USB passthrough
- device-owner / manual kiosk operations

Это отдельный manual/device contour.

## Host fallback

Host-level Java/Android SDK допускаются только как временный fallback, если builder-контур ещё не поднят или временно сломан.

Если fallback всё же нужен, на host должны быть:

- `openjdk-17-jdk`
- `adb`
- при прямой host-сборке ещё и `/usr/lib/android-sdk`

Но это больше не preferred path.

## Проверка builder-контура

Предусловие для self-hosted GitHub Actions runner: runner user должен быть в
группе `docker`, иначе шаг `Prepare Android builder` упадёт на доступе к
`/var/run/docker.sock`.

Минимальная проверка:

```bash
id planka-deploy
sudo -u planka-deploy docker ps
```

Если доступ только что выдали через `usermod -aG docker planka-deploy`, надо
перезапустить runner service, чтобы он увидел новую group membership.

1. Проверить compose config:

```bash
./.flow/shared/scripts/run.sh android_builder config
```

2. Поднять builder:

```bash
./.flow/shared/scripts/run.sh android_builder up
```

3. Прогнать Android checks:

```bash
./.flow/shared/scripts/run.sh android_builder run bash -lc 'cd app/planka_quick_test_app && ./gradlew --no-daemon testDebugUnitTest assembleDebug'
```

4. Остановить builder:

```bash
./.flow/shared/scripts/run.sh android_builder down
```

## Cleanup host after migration

Если Android automation полностью переведена на builder и host больше не нужен
для Java/SDK, cleanup делать в таком порядке:

1. Дождаться хотя бы одного полного зелёного workflow-run через builder
   (`build -> publish -> notify_telegram`).
2. Убедиться, что ручной `adb` на этой VPS больше не нужен.
3. Только после этого удалять host Java/SDK.

### Команды cleanup

1. Удалить host env overrides:

```bash
sudo rm -f /etc/profile.d/planka-android-env.sh
```

2. Удалить host packages, которые ставились только ради прямой Android-сборки:

```bash
sudo apt-get remove -y openjdk-17-jdk adb android-sdk-platform-tools-common
sudo apt-get autoremove -y
```

3. Удалить host SDK directory, если ручной device flow на этой машине не нужен:

```bash
sudo rm -rf /usr/lib/android-sdk
```

4. После cleanup убедиться, что automation больше не зависит от host Java:

```bash
./.flow/shared/scripts/run.sh android_builder config
```

5. По желанию отдельно проверить, что workflow по-прежнему стартует builder и
не использует host toolchain:

```bash
./.flow/shared/scripts/run.sh android_builder up
./.flow/shared/scripts/run.sh android_builder down
```

## Важная граница

Если на этой VPS всё ещё нужен ручной `adb`-сценарий с реальным устройством, cleanup host Java/SDK делать рано.

Сначала нужно решить отдельно:

- где живёт manual device smoke;
- нужен ли `adb` именно на этой VPS;
- не должен ли этот сценарий переехать на отдельный host.
