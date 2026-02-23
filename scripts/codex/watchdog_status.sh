#!/usr/bin/env bash
set -euo pipefail

label="${1:-com.planka.codex-watchdog}"
plist_path="${HOME}/Library/LaunchAgents/${label}.plist"

if [[ ! -f "${plist_path}" ]]; then
  echo "NOT_INSTALLED ${label}"
  exit 0
fi

if launchctl print "gui/${UID}/${label}" >/dev/null 2>&1; then
  echo "RUNNING ${label}"
  echo "PLIST ${plist_path}"
  exit 0
fi

echo "INSTALLED_NOT_LOADED ${label}"
echo "PLIST ${plist_path}"
