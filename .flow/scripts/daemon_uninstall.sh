#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=./env/resolve_config.sh
source "${ROOT_DIR}/.flow/scripts/env/resolve_config.sh"
default_namespace="$(codex_resolve_flow_launchd_namespace)"
launchd_dir="$(codex_resolve_flow_launchd_dir)"
launchagents_dir="$(codex_resolve_flow_launchagents_dir)"

label="${1:-${default_namespace}.codex-daemon}"
canonical_plist_path="${launchd_dir}/${label}.plist"
plist_path="${launchagents_dir}/${label}.plist"

if [[ -f "${plist_path}" ]]; then
  launchctl bootout "gui/${UID}" "${plist_path}" >/dev/null 2>&1 || true
  rm -f "${plist_path}"
  rm -f "${canonical_plist_path}"
  echo "Uninstalled launchd agent: ${label}"
  exit 0
fi

echo "Launchd plist not found: ${plist_path}"
