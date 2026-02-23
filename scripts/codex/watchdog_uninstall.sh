#!/usr/bin/env bash
set -euo pipefail

label="${1:-com.planka.codex-watchdog}"
plist_path="${HOME}/Library/LaunchAgents/${label}.plist"

if [[ -f "${plist_path}" ]]; then
  launchctl bootout "gui/${UID}" "${plist_path}" >/dev/null 2>&1 || true
  rm -f "${plist_path}"
  echo "Uninstalled launchd watchdog: ${label}"
  exit 0
fi

echo "Watchdog plist not found: ${plist_path}"
