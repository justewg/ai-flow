#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
CODEX_DIR="$(codex_export_state_dir)"
RUNTIME_LOG_DIR="$(codex_resolve_flow_runtime_log_dir)"
daemon_state_dir="$(codex_resolve_state_daemon_dir "$CODEX_DIR")"
lock_dir="${daemon_state_dir}/lock"
service_manager="$(codex_resolve_flow_service_manager)"
runtime_role="$(codex_resolve_flow_automation_runtime_role)"
runtime_instance_id="$(codex_resolve_flow_runtime_instance_id)"
authoritative_runtime_id="$(codex_resolve_flow_authoritative_runtime_id)"
runtime_ownership_state="$(codex_resolve_flow_runtime_ownership_state)"
launchd_dir="$(codex_resolve_flow_launchd_dir)"
launchagents_dir="$(codex_resolve_flow_launchagents_dir)"
systemd_dir="$(codex_resolve_flow_systemd_dir)"
systemd_scope="$(codex_resolve_flow_systemd_scope)"
systemd_unit_dir="$(codex_resolve_flow_systemd_unit_dir)"
default_label="$(codex_resolve_default_daemon_label)"

label="${1:-$default_label}"
interval="${2:-45}"
canonical_plist_path="${launchd_dir}/${label}.plist"
plist_path="${launchagents_dir}/${label}.plist"
canonical_unit_path="${systemd_dir}/${label}.service"
unit_path="${systemd_unit_dir}/${label}.service"
profile_env_file="${DAEMON_GH_ENV_FILE:-}"

if [[ "$runtime_ownership_state" == "INTERACTIVE_ONLY" ]]; then
  echo "SKIPPED_INTERACTIVE_ONLY=1"
  echo "RUNTIME_ROLE=${runtime_role}"
  echo "RUNTIME_INSTANCE_ID=${runtime_instance_id}"
  exit 0
fi

if [[ "$runtime_ownership_state" == "OWNER_MISMATCH" ]]; then
  echo "SKIPPED_RUNTIME_OWNERSHIP=1"
  echo "RUNTIME_ROLE=${runtime_role}"
  echo "RUNTIME_INSTANCE_ID=${runtime_instance_id}"
  echo "AUTHORITATIVE_RUNTIME_ID=${authoritative_runtime_id}"
  exit 0
fi

if ! [[ "$interval" =~ ^[0-9]+$ ]] || (( interval < 5 )); then
  echo "Invalid interval: '$interval' (expected integer >= 5 sec)"
  exit 1
fi

mkdir -p "${CODEX_DIR}" "${RUNTIME_LOG_DIR}" "${daemon_state_dir}"

optional_env_block=""
if [[ -n "$profile_env_file" ]]; then
  optional_env_block="$(cat <<EOF
    <key>DAEMON_GH_ENV_FILE</key>
    <string>${profile_env_file}</string>
EOF
)"
fi

if [[ "$service_manager" == "launchd" ]]; then
  mkdir -p "${launchagents_dir}" "${launchd_dir}"

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
    <string>${CODEX_SHARED_SCRIPTS_DIR}/daemon_loop.sh</string>
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
  <string>${RUNTIME_LOG_DIR}/daemon.log</string>

  <key>StandardErrorPath</key>
  <string>${RUNTIME_LOG_DIR}/daemon.log</string>
</dict>
</plist>
EOF

  ln -sfn "${canonical_plist_path}" "${plist_path}"

  launchctl bootout "gui/${UID}" "${plist_path}" >/dev/null 2>&1 || true
  rmdir "${lock_dir}" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/${UID}" "${plist_path}"
  launchctl kickstart -k "gui/${UID}/${label}"

  echo "SERVICE_MANAGER=launchd"
  echo "Installed launchd agent: ${label}"
  echo "Canonical plist: ${canonical_plist_path}"
  echo "LaunchAgents plist: ${plist_path}"
elif [[ "$service_manager" == "systemd" ]]; then
  local_systemctl=(systemctl)
  if [[ "$systemd_scope" == "user" ]]; then
    local_systemctl+=(--user)
  fi

  mkdir -p "${systemd_dir}" "${systemd_unit_dir}"

  cat > "${canonical_unit_path}" <<EOF
[Unit]
Description=Codex flow daemon (${label})
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
WorkingDirectory=${ROOT_DIR}
Environment=PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
Environment=CODEX_STATE_DIR=${CODEX_DIR}
Environment=FLOW_STATE_DIR=${CODEX_DIR}
$(if [[ -n "$profile_env_file" ]]; then printf 'Environment=DAEMON_GH_ENV_FILE=%s\n' "$profile_env_file"; fi)
ExecStart=/bin/bash ${CODEX_SHARED_SCRIPTS_DIR}/daemon_loop.sh ${interval}
Restart=always
RestartSec=5
StandardOutput=append:${RUNTIME_LOG_DIR}/daemon.log
StandardError=append:${RUNTIME_LOG_DIR}/daemon.log

[Install]
WantedBy=default.target
EOF

  ln -sfn "${canonical_unit_path}" "${unit_path}"

  rmdir "${lock_dir}" >/dev/null 2>&1 || true
  "${local_systemctl[@]}" daemon-reload
  "${local_systemctl[@]}" enable --now "${label}.service"
  "${local_systemctl[@]}" restart "${label}.service"

  echo "SERVICE_MANAGER=systemd"
  echo "SYSTEMD_SCOPE=${systemd_scope}"
  echo "Installed systemd service: ${label}.service"
  echo "Canonical unit: ${canonical_unit_path}"
  echo "Systemd unit: ${unit_path}"
else
  echo "Unsupported FLOW_SERVICE_MANAGER=${service_manager}" >&2
  exit 1
fi

echo "Interval: ${interval}s"
echo "State dir: ${CODEX_DIR}"
echo "Runtime log dir: ${RUNTIME_LOG_DIR}"
echo "Daemon lock dir: ${lock_dir}"
if [[ -n "$profile_env_file" ]]; then
  echo "Profile env: ${profile_env_file}"
fi
