#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST_SCRIPT="${ROOT_DIR}/scripts/android_release/render_manifest.sh"

usage() {
  cat <<'EOF'
Usage:
  publish_release.sh \
    --deploy-root <abs-path> \
    --public-base-url <https-base-url> \
    --channel <name> \
    --apk-file <path> \
    --config-file <path> \
    --app-version <int> \
    --app-version-name <string> \
    --config-version <int> \
    --min-supported-app-version <int> \
    --message <string>
EOF
}

require_nonempty() {
  local name="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    echo "publish_release.sh: ${name} is required" >&2
    exit 1
  fi
}

sha256_file() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
    return
  fi
  shasum -a 256 "$path" | awk '{print $1}'
}

deploy_root=""
public_base_url=""
channel=""
apk_file=""
config_file=""
app_version=""
app_version_name=""
config_version=""
min_supported_app_version=""
message=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --deploy-root)
      deploy_root="${2:-}"
      shift 2
      ;;
    --public-base-url)
      public_base_url="${2:-}"
      shift 2
      ;;
    --channel)
      channel="${2:-}"
      shift 2
      ;;
    --apk-file)
      apk_file="${2:-}"
      shift 2
      ;;
    --config-file)
      config_file="${2:-}"
      shift 2
      ;;
    --app-version)
      app_version="${2:-}"
      shift 2
      ;;
    --app-version-name)
      app_version_name="${2:-}"
      shift 2
      ;;
    --config-version)
      config_version="${2:-}"
      shift 2
      ;;
    --min-supported-app-version)
      min_supported_app_version="${2:-}"
      shift 2
      ;;
    --message)
      message="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "publish_release.sh: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_nonempty "deploy_root" "$deploy_root"
require_nonempty "public_base_url" "$public_base_url"
require_nonempty "channel" "$channel"
require_nonempty "apk_file" "$apk_file"
require_nonempty "config_file" "$config_file"
require_nonempty "app_version" "$app_version"
require_nonempty "app_version_name" "$app_version_name"
require_nonempty "config_version" "$config_version"
require_nonempty "min_supported_app_version" "$min_supported_app_version"
require_nonempty "message" "$message"

if [[ ! "$channel" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
  echo "publish_release.sh: channel must match ^[a-z0-9][a-z0-9._-]*$" >&2
  exit 1
fi

if [[ ! -f "$apk_file" ]]; then
  echo "publish_release.sh: apk_file not found: $apk_file" >&2
  exit 1
fi

if [[ ! -f "$config_file" ]]; then
  echo "publish_release.sh: config_file not found: $config_file" >&2
  exit 1
fi

mkdir -p "$deploy_root"

release_id="app-v${app_version}_config-v${config_version}"
channel_root="${deploy_root%/}/${channel}"
release_root="${channel_root}/releases/${release_id}"
public_channel_root="${public_base_url%/}/${channel}"

apk_target_name="planka-shell-${app_version_name}.apk"
config_target_name="config-v${config_version}.json"

mkdir -p "$release_root"
cp "$apk_file" "${release_root}/${apk_target_name}"
cp "$config_file" "${release_root}/${config_target_name}"

apk_sha256="$(sha256_file "${release_root}/${apk_target_name}")"
config_sha256="$(sha256_file "${release_root}/${config_target_name}")"

apk_url="${public_channel_root}/releases/${release_id}/${apk_target_name}"
config_url="${public_channel_root}/releases/${release_id}/${config_target_name}"

manifest_tmp="$(mktemp)"
"$MANIFEST_SCRIPT" \
  --app-version "$app_version" \
  --app-version-name "$app_version_name" \
  --config-version "$config_version" \
  --min-supported-app-version "$min_supported_app_version" \
  --message "$message" \
  --apk-url "$apk_url" \
  --apk-sha256 "$apk_sha256" \
  --config-url "$config_url" \
  --config-sha256 "$config_sha256" \
  > "$manifest_tmp"

mv "$manifest_tmp" "${release_root}/manifest.json"

cat > "${release_root}/release-metadata.json" <<EOF
{
  "channel": "${channel}",
  "releaseId": "${release_id}",
  "appVersion": ${app_version},
  "appVersionName": "$(printf '%s' "$app_version_name" | sed 's/"/\\"/g')",
  "configVersion": ${config_version},
  "minSupportedAppVersion": ${min_supported_app_version},
  "apkFile": "${apk_target_name}",
  "configFile": "${config_target_name}",
  "apkSha256": "${apk_sha256}",
  "configSha256": "${config_sha256}"
}
EOF

cp "${release_root}/manifest.json" "${channel_root}/manifest.json.tmp"
mv "${channel_root}/manifest.json.tmp" "${channel_root}/manifest.json"

echo "PUBLISH_OK=1"
echo "PUBLISH_CHANNEL=${channel}"
echo "PUBLISH_RELEASE_ID=${release_id}"
echo "PUBLISH_CHANNEL_ROOT=${channel_root}"
echo "PUBLISH_RELEASE_ROOT=${release_root}"
echo "PUBLISH_MANIFEST_URL=${public_channel_root}/manifest.json"
echo "PUBLISH_APK_URL=${apk_url}"
echo "PUBLISH_CONFIG_URL=${config_url}"
echo "PUBLISH_APK_SHA256=${apk_sha256}"
echo "PUBLISH_CONFIG_SHA256=${config_sha256}"
