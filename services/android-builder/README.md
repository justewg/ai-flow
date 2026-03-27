# Android Builder Service

Standalone Docker builder for Android and Java-oriented flow tasks.

## Purpose

This service keeps Android/JDK toolchain out of:

- the host system;
- the main Codex/runtime container.

It is intended for tasks where automation needs to:

- run `./gradlew test...`;
- run `./gradlew assemble...`;
- build APK/AAB artifacts;
- execute Java/Gradle-based verification inside an isolated container.

## Layout

- `Dockerfile`
  - JDK 17
  - Android command-line tools
  - preinstalled Android SDK packages for current baseline
- `docker-compose.yml`
  - mounts the target workspace at `/workspace`
  - stores Gradle/cache state in a dedicated host cache path
- `scripts/android_builder.sh`
  - stable wrapper for `docker compose` operations

## Default toolchain

Build args used by default:

- `ANDROID_CMDLINE_TOOLS_VERSION=11076708`
- `ANDROID_COMPILE_SDK=35`
- `ANDROID_BUILD_TOOLS=35.0.0`

These can be overridden through environment variables passed to the wrapper.

## Canonical usage

From a consumer repo with toolkit installed:

```bash
./.flow/shared/scripts/run.sh android_builder up
./.flow/shared/scripts/run.sh android_builder run bash -lc 'cd app/planka_quick_test_app && ./gradlew --no-daemon testDebugUnitTest assembleDebug'
./.flow/shared/scripts/run.sh android_builder shell
./.flow/shared/scripts/run.sh android_builder down
```

## Host cache

The wrapper stores builder home/Gradle cache under:

`<AI_FLOW_ROOT_DIR>/services/android-builder/<project-slug>/home`

This keeps heavy cache directories outside the repo worktree and separate from the main runtime container.

## Scope boundary

This service is for build/test/package steps only.

It intentionally does **not** assume:

- `adb` access to a real device;
- device-owner / kiosk admin actions;
- host USB passthrough;
- manual smoke on Lenovo.

Those stay outside the builder container unless a dedicated device-facing flow is introduced later.

## Host cleanup after migration

If Android automation fully switches to this builder, the host no longer needs JDK/Android SDK for PLANKA automation.

Recommended cleanup on the VPS host:

1. Stop relying on host-side `JAVA_HOME` and `/etc/profile.d/planka-android-env.sh`.
2. Remove host packages that were added only for direct Android builds:
   - `openjdk-17-jdk`
   - `adb`
   - `android-sdk-platform-tools-common`
3. Remove host SDK directories that were created only for direct builds:
   - `/usr/lib/android-sdk`
4. Keep removal manual and explicit; do not automate package removal from the flow runtime.
