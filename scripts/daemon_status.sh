#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
default_label="$(codex_resolve_default_daemon_label)"
launchd_dir="$(codex_resolve_flow_launchd_dir)"
launchagents_dir="$(codex_resolve_flow_launchagents_dir)"

label="${1:-$default_label}"
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
