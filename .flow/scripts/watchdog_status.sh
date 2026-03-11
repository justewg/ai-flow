#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=./env/resolve_config.sh
source "${ROOT_DIR}/.flow/scripts/env/resolve_config.sh"
default_namespace="$(codex_resolve_flow_launchd_namespace)"
launchd_dir="$(codex_resolve_flow_launchd_dir)"
launchagents_dir="$(codex_resolve_flow_launchagents_dir)"

label="${1:-${default_namespace}.codex-watchdog}"
canonical_plist_path="${launchd_dir}/${label}.plist"
plist_path="${launchagents_dir}/${label}.plist"

if [[ ! -f "${plist_path}" ]]; then
  echo "NOT_INSTALLED ${label}"
  exit 0
fi

if launchctl print "gui/${UID}/${label}" >/dev/null 2>&1; then
  echo "RUNNING ${label}"
  echo "PLIST ${plist_path}"
  echo "CANONICAL_PLIST ${canonical_plist_path}"
  exit 0
fi

echo "INSTALLED_NOT_LOADED ${label}"
echo "PLIST ${plist_path}"
echo "CANONICAL_PLIST ${canonical_plist_path}"
