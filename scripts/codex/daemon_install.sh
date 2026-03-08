#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=./env/resolve_config.sh
source "${ROOT_DIR}/scripts/codex/env/resolve_config.sh"
CODEX_DIR="$(codex_export_state_dir)"

label="${1:-com.planka.codex-daemon}"
interval="${2:-45}"
plist_path="${HOME}/Library/LaunchAgents/${label}.plist"

if ! [[ "$interval" =~ ^[0-9]+$ ]] || (( interval < 5 )); then
  echo "Invalid interval: '$interval' (expected integer >= 5 sec)"
  exit 1
fi

mkdir -p "${HOME}/Library/LaunchAgents" "${CODEX_DIR}"

cat > "${plist_path}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${label}</string>

  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${ROOT_DIR}/scripts/codex/daemon_loop.sh</string>
    <string>${interval}</string>
  </array>

  <key>WorkingDirectory</key>
  <string>${ROOT_DIR}</string>

  <key>RunAtLoad</key>
  <true/>

  <key>KeepAlive</key>
  <true/>

  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>CODEX_STATE_DIR</key>
    <string>${CODEX_DIR}</string>
    <key>FLOW_STATE_DIR</key>
    <string>${CODEX_DIR}</string>
  </dict>

  <key>StandardOutPath</key>
  <string>${CODEX_DIR}/launchd.out.log</string>

  <key>StandardErrorPath</key>
  <string>${CODEX_DIR}/launchd.err.log</string>
</dict>
</plist>
EOF

launchctl bootout "gui/${UID}" "${plist_path}" >/dev/null 2>&1 || true
launchctl bootstrap "gui/${UID}" "${plist_path}"
launchctl kickstart -k "gui/${UID}/${label}"

echo "Installed launchd agent: ${label}"
echo "Plist: ${plist_path}"
echo "Interval: ${interval}s"
echo "State dir: ${CODEX_DIR}"
