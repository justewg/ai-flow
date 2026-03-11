#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=./env/resolve_config.sh
source "${ROOT_DIR}/.flow/scripts/env/resolve_config.sh"
CODEX_DIR="$(codex_export_state_dir)"
lock_dir="${CODEX_DIR}/daemon.lock"
launchd_dir="$(codex_resolve_flow_launchd_dir)"
launchagents_dir="$(codex_resolve_flow_launchagents_dir)"
default_namespace="$(codex_resolve_flow_launchd_namespace)"

label="${1:-${default_namespace}.codex-daemon}"
interval="${2:-45}"
canonical_plist_path="${launchd_dir}/${label}.plist"
plist_path="${launchagents_dir}/${label}.plist"
profile_env_file="${DAEMON_GH_ENV_FILE:-}"

if ! [[ "$interval" =~ ^[0-9]+$ ]] || (( interval < 5 )); then
  echo "Invalid interval: '$interval' (expected integer >= 5 sec)"
  exit 1
fi

mkdir -p "${launchagents_dir}" "${launchd_dir}" "${CODEX_DIR}"

optional_env_block=""
if [[ -n "$profile_env_file" ]]; then
  optional_env_block="$(cat <<EOF
    <key>DAEMON_GH_ENV_FILE</key>
    <string>${profile_env_file}</string>
EOF
)"
fi

cat > "${canonical_plist_path}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${label}</string>

  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${ROOT_DIR}/.flow/scripts/daemon_loop.sh</string>
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
${optional_env_block}
  </dict>

  <key>StandardOutPath</key>
  <string>${CODEX_DIR}/launchd.out.log</string>

  <key>StandardErrorPath</key>
  <string>${CODEX_DIR}/launchd.err.log</string>
</dict>
</plist>
EOF

ln -sfn "${canonical_plist_path}" "${plist_path}"

launchctl bootout "gui/${UID}" "${plist_path}" >/dev/null 2>&1 || true
rmdir "${lock_dir}" >/dev/null 2>&1 || true
launchctl bootstrap "gui/${UID}" "${plist_path}"
launchctl kickstart -k "gui/${UID}/${label}"

echo "Installed launchd agent: ${label}"
echo "Canonical plist: ${canonical_plist_path}"
echo "LaunchAgents plist: ${plist_path}"
echo "Interval: ${interval}s"
echo "State dir: ${CODEX_DIR}"
echo "Daemon lock dir: ${lock_dir}"
if [[ -n "$profile_env_file" ]]; then
  echo "Profile env: ${profile_env_file}"
fi
