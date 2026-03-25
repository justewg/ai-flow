#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  render_manifest.sh \
    --app-version <int> \
    --app-version-name <string> \
    --config-version <int> \
    --min-supported-app-version <int> \
    --message <string> \
    --apk-url <https-url> \
    --apk-sha256 <64-hex> \
    --config-url <https-url> \
    --config-sha256 <64-hex>
EOF
}

require_nonempty() {
  local name="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    echo "render_manifest.sh: ${name} is required" >&2
    exit 1
  fi
}

require_https() {
  local name="$1"
  local value="$2"
  if [[ ! "$value" =~ ^https:// ]]; then
    echo "render_manifest.sh: ${name} must start with https://" >&2
    exit 1
  fi
}

require_sha256() {
  local name="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[0-9a-fA-F]{64}$ ]]; then
    echo "render_manifest.sh: ${name} must be a 64-char hex sha256" >&2
    exit 1
  fi
}

app_version=""
app_version_name=""
config_version=""
min_supported_app_version=""
message=""
apk_url=""
apk_sha256=""
config_url=""
config_sha256=""

while [[ $# -gt 0 ]]; do
  case "$1" in
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
    --apk-url)
      apk_url="${2:-}"
      shift 2
      ;;
    --apk-sha256)
      apk_sha256="${2:-}"
      shift 2
      ;;
    --config-url)
      config_url="${2:-}"
      shift 2
      ;;
    --config-sha256)
      config_sha256="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "render_manifest.sh: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_nonempty "app_version" "$app_version"
require_nonempty "app_version_name" "$app_version_name"
require_nonempty "config_version" "$config_version"
require_nonempty "min_supported_app_version" "$min_supported_app_version"
require_nonempty "message" "$message"
require_nonempty "apk_url" "$apk_url"
require_nonempty "apk_sha256" "$apk_sha256"
require_nonempty "config_url" "$config_url"
require_nonempty "config_sha256" "$config_sha256"

require_https "apk_url" "$apk_url"
require_https "config_url" "$config_url"
require_sha256 "apk_sha256" "$apk_sha256"
require_sha256 "config_sha256" "$config_sha256"

jq -n \
  --argjson schemaVersion 1 \
  --argjson appVersion "$app_version" \
  --arg appVersionName "$app_version_name" \
  --argjson configVersion "$config_version" \
  --argjson minSupportedAppVersion "$min_supported_app_version" \
  --arg message "$message" \
  --arg apkUrl "$apk_url" \
  --arg apkSha256 "$(printf '%s' "$apk_sha256" | tr 'A-F' 'a-f')" \
  --arg configUrl "$config_url" \
  --arg configSha256 "$(printf '%s' "$config_sha256" | tr 'A-F' 'a-f')" \
  '{
    schemaVersion: $schemaVersion,
    appVersion: $appVersion,
    appVersionName: $appVersionName,
    configVersion: $configVersion,
    minSupportedAppVersion: $minSupportedAppVersion,
    message: $message,
    apk: {
      url: $apkUrl,
      sha256: $apkSha256
    },
    config: {
      url: $configUrl,
      sha256: $configSha256
    }
  }'
