#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
default_label="$(codex_resolve_default_daemon_label)"
service_manager="$(codex_resolve_flow_service_manager)"
launchd_dir="$(codex_resolve_flow_launchd_dir)"
launchagents_dir="$(codex_resolve_flow_launchagents_dir)"
systemd_dir="$(codex_resolve_flow_systemd_dir)"
systemd_scope="$(codex_resolve_flow_systemd_scope)"
systemd_unit_dir="$(codex_resolve_flow_systemd_unit_dir)"

label="${1:-$default_label}"
canonical_plist_path="${launchd_dir}/${label}.plist"
plist_path="${launchagents_dir}/${label}.plist"
canonical_unit_path="${systemd_dir}/${label}.service"
unit_path="${systemd_unit_dir}/${label}.service"

if [[ "$service_manager" == "launchd" ]]; then
  if [[ ! -f "${plist_path}" ]]; then
    echo "NOT_INSTALLED ${label}"
    exit 0
  fi

  if launchctl print "gui/${UID}/${label}" >/dev/null 2>&1; then
    echo "RUNNING ${label}"
    echo "SERVICE_MANAGER launchd"
    echo "PLIST ${plist_path}"
    echo "CANONICAL_PLIST ${canonical_plist_path}"
    exit 0
  fi

  echo "INSTALLED_NOT_LOADED ${label}"
  echo "SERVICE_MANAGER launchd"
  echo "PLIST ${plist_path}"
  echo "CANONICAL_PLIST ${canonical_plist_path}"
  exit 0
fi

if [[ "$service_manager" == "systemd" ]]; then
  systemctl_cmd=(systemctl)
  if [[ "$systemd_scope" == "user" ]]; then
    systemctl_cmd+=(--user)
  fi

  if [[ ! -f "${unit_path}" && ! -f "${canonical_unit_path}" ]]; then
    echo "NOT_INSTALLED ${label}"
    exit 0
  fi

  if "${systemctl_cmd[@]}" is-active --quiet "${label}.service"; then
    echo "RUNNING ${label}"
    echo "SERVICE_MANAGER systemd"
    echo "SYSTEMD_SCOPE ${systemd_scope}"
    echo "UNIT ${unit_path}"
    echo "CANONICAL_UNIT ${canonical_unit_path}"
    exit 0
  fi

  echo "INSTALLED_NOT_LOADED ${label}"
  echo "SERVICE_MANAGER systemd"
  echo "SYSTEMD_SCOPE ${systemd_scope}"
  echo "UNIT ${unit_path}"
  echo "CANONICAL_UNIT ${canonical_unit_path}"
  exit 0
fi

echo "Unsupported FLOW_SERVICE_MANAGER=${service_manager}" >&2
exit 1
