#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
CODEX_DIR="$(codex_export_state_dir)"
RUNTIME_LOG_DIR="$(codex_resolve_flow_runtime_log_dir)"
watchdog_state_dir="$(codex_resolve_state_watchdog_dir "$CODEX_DIR")"
lock_dir="${watchdog_state_dir}/lock"
launchd_dir="$(codex_resolve_flow_launchd_dir)"
launchagents_dir="$(codex_resolve_flow_launchagents_dir)"
default_watchdog_label="$(codex_resolve_default_watchdog_label)"
default_daemon_label="$(codex_resolve_default_daemon_label)"

label="${1:-$default_watchdog_label}"
interval="${2:-45}"
canonical_plist_path="${launchd_dir}/${label}.plist"
plist_path="${launchagents_dir}/${label}.plist"
profile_env_file="${DAEMON_GH_ENV_FILE:-}"
daemon_label="${WATCHDOG_DAEMON_LABEL:-$default_daemon_label}"
daemon_interval="${WATCHDOG_DAEMON_INTERVAL_SEC:-45}"

if ! [[ "$interval" =~ ^[0-9]+$ ]] || (( interval < 10 )); then
  echo "Invalid interval: '$interval' (expected integer >= 10 sec)"
  exit 1
fi

mkdir -p "${launchagents_dir}" "${launchd_dir}" "${CODEX_DIR}" "${RUNTIME_LOG_DIR}" "${watchdog_state_dir}"

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
    <string>${CODEX_SHARED_SCRIPTS_DIR}/watchdog_loop.sh</string>
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
    <key>WATCHDOG_DAEMON_LABEL</key>
    <string>${daemon_label}</string>
    <key>WATCHDOG_DAEMON_INTERVAL_SEC</key>
    <string>${daemon_interval}</string>
${optional_env_block}
  </dict>

  <key>StandardOutPath</key>
  <string>${RUNTIME_LOG_DIR}/watchdog.log</string>

  <key>StandardErrorPath</key>
  <string>${RUNTIME_LOG_DIR}/watchdog.log</string>
</dict>
</plist>
EOF

ln -sfn "${canonical_plist_path}" "${plist_path}"

launchctl bootout "gui/${UID}" "${plist_path}" >/dev/null 2>&1 || true
rmdir "${lock_dir}" >/dev/null 2>&1 || true
launchctl bootstrap "gui/${UID}" "${plist_path}"
launchctl kickstart -k "gui/${UID}/${label}"

echo "Installed launchd watchdog: ${label}"
echo "Canonical plist: ${canonical_plist_path}"
echo "LaunchAgents plist: ${plist_path}"
echo "Interval: ${interval}s"
echo "State dir: ${CODEX_DIR}"
echo "Runtime log dir: ${RUNTIME_LOG_DIR}"
echo "Watchdog lock dir: ${lock_dir}"
echo "Daemon label: ${daemon_label}"
echo "Daemon interval: ${daemon_interval}s"
if [[ -n "$profile_env_file" ]]; then
  echo "Profile env: ${profile_env_file}"
fi
