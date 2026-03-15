#!/usr/bin/env bash
set -euo pipefail

readonly HELPER_PATH="/usr/local/libexec/ai-flow/remote-agent-v2-helper"
readonly LOGGER_TAG="ai-flow-remote-agent-v2-gateway"

usage() {
  cat <<'EOF'
Usage: remote_agent_v2_gateway.sh

Forced-command SSH gateway for Remote Agent v2.

Reads SSH_ORIGINAL_COMMAND, validates a fixed probe invocation, and re-enters
through the immutable root-owned helper via sudo.
EOF
}

log_event() {
  local event="$1"
  local detail="$2"
  if command -v logger >/dev/null 2>&1; then
    logger -t "$LOGGER_TAG" "event=${event} user=${USER:-unknown} ssh_connection=\"${SSH_CONNECTION:-}\" detail=\"${detail}\""
  fi
}

validate_args() {
  local probe_name="${1:-}"
  shift || true

  case "$probe_name" in
    runtime_snapshot_v2|ops_health_v2|compose_contract_metadata_v2|nginx_ingress_metadata_v2|workspace_git_metadata_v2)
      ;;
    runtime_log_tail_v2)
      ;;
    *)
      return 1
      ;;
  esac

  local profile_seen="0"
  local lines_seen="0"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile)
        [[ $# -ge 2 ]] || return 1
        [[ "$profile_seen" == "0" ]] || return 1
        [[ "$2" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || return 1
        profile_seen="1"
        shift 2
        ;;
      --lines)
        [[ "$probe_name" == "runtime_log_tail_v2" ]] || return 1
        [[ $# -ge 2 ]] || return 1
        [[ "$lines_seen" == "0" ]] || return 1
        [[ "$2" =~ ^[0-9]+$ ]] || return 1
        lines_seen="1"
        shift 2
        ;;
      *)
        return 1
        ;;
    esac
  done

  return 0
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "help" ]]; then
    usage
    exit 0
  fi

  local original_command
  original_command="$(printf '%s' "${SSH_ORIGINAL_COMMAND:-}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  if [[ -z "$original_command" ]]; then
    log_event "deny" "empty-command"
    echo "Command denied" >&2
    exit 1
  fi

  local -a args=()
  read -r -a args <<< "$original_command"
  local probe_name="${args[0]:-}"
  local -a probe_args=("${args[@]:1}")

  if ! validate_args "$probe_name" "${probe_args[@]}"; then
    log_event "deny" "$original_command"
    echo "Command denied" >&2
    exit 1
  fi

  log_event "allow" "$original_command"
  exec sudo -n -- "$HELPER_PATH" --dispatch "$probe_name" "${probe_args[@]}"
}

main "$@"
