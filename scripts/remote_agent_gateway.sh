#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

usage() {
  cat <<'EOF'
Usage:
  remote_agent_gateway.sh --forced-command --runtime-user <user> --workspace-path <path> --audit-log <path>
  remote_agent_gateway.sh --sudo-probe --runtime-user <user> --workspace-path <path> <probe-subcommand> [options]

Modes:
  --forced-command   Parse SSH_ORIGINAL_COMMAND, audit it, and re-enter via sudo-allowlisted path.
  --sudo-probe       Validate a fixed probe subcommand and execute repo-local run.sh remote_probe as runtime-user.
EOF
}

echo "remote_agent_gateway v1 is disabled; use /usr/local/sbin/ai-flow-remote-agent-v2-gateway" >&2
exit 1

json_escape() {
  printf '%s' "${1:-}" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/"/\\"/g'
}

log_event() {
  local audit_log="$1"
  local event="$2"
  local detail="$3"
  mkdir -p "$(dirname "$audit_log")"
  touch "$audit_log"
  printf '%s event=%s user=%s ssh_connection="%s" detail="%s"\n' \
    "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    "$event" \
    "${USER:-unknown}" \
    "$(json_escape "${SSH_CONNECTION:-}")" \
    "$(json_escape "$detail")" >> "$audit_log"
}

validate_probe_invocation() {
  local subcommand="$1"
  shift || true
  case "$subcommand" in
    semantically_overqualified_runtime_snapshot_env_audit_bundle_v1)
      [[ $# -eq 0 ]] || return 1
      ;;
    semantically_overqualified_docker_compose_contract_surface_v1)
      [[ $# -eq 0 ]] || return 1
      ;;
    semantically_overqualified_ops_bot_debug_gate_surface_v1)
      [[ $# -eq 0 ]] || return 1
      ;;
    semantically_overqualified_nginx_ingress_surface_v1)
      [[ $# -eq 0 ]] || return 1
      ;;
    semantically_overqualified_workspace_git_surface_v1)
      [[ $# -eq 0 ]] || return 1
      ;;
    semantically_overqualified_runtime_log_tail_bundle_v1)
      if [[ $# -eq 0 ]]; then
        return 0
      fi
      [[ $# -eq 2 && "$1" == "--lines" && "$2" =~ ^[0-9]+$ ]] || return 1
      ;;
    *)
      return 1
      ;;
  esac
  return 0
}

run_probe_as_runtime_user() {
  local runtime_user="$1"
  local workspace_path="$2"
  shift 2 || true
  local run_script="${workspace_path}/.flow/shared/scripts/run.sh"
  [[ -x "$run_script" ]] || {
    echo "Missing executable run.sh: ${run_script}" >&2
    exit 1
  }
  exec sudo -n -u "$runtime_user" -- "$run_script" remote_probe "$@"
}

mode=""
runtime_user=""
workspace_path=""
audit_log=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --forced-command)
      mode="forced"
      shift
      ;;
    --sudo-probe)
      mode="sudo-probe"
      shift
      ;;
    --runtime-user)
      [[ $# -ge 2 ]] || { echo "Missing value for --runtime-user" >&2; exit 1; }
      runtime_user="$2"
      shift 2
      ;;
    --workspace-path)
      [[ $# -ge 2 ]] || { echo "Missing value for --workspace-path" >&2; exit 1; }
      workspace_path="$2"
      shift 2
      ;;
    --audit-log)
      [[ $# -ge 2 ]] || { echo "Missing value for --audit-log" >&2; exit 1; }
      audit_log="$2"
      shift 2
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

[[ -n "$mode" && -n "$runtime_user" && -n "$workspace_path" ]] || {
  usage >&2
  exit 1
}

case "$mode" in
  forced)
    [[ -n "$audit_log" ]] || { echo "--audit-log is required for --forced-command" >&2; exit 1; }
    original_command="$(printf '%s' "${SSH_ORIGINAL_COMMAND:-}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    if [[ -z "$original_command" ]]; then
      log_event "$audit_log" "denied" "empty SSH_ORIGINAL_COMMAND"
      echo "No command requested. Allowed probes are fixed read-only subcommands only." >&2
      exit 1
    fi
    read -r -a original_args <<< "$original_command"
    probe_subcommand="${original_args[0]:-}"
    probe_args=("${original_args[@]:1}")
    if ! validate_probe_invocation "$probe_subcommand" "${probe_args[@]}"; then
      log_event "$audit_log" "denied" "$original_command"
      echo "Command denied" >&2
      exit 1
    fi
    log_event "$audit_log" "accepted" "$original_command"
    exec sudo -n "$0" --sudo-probe --runtime-user "$runtime_user" --workspace-path "$workspace_path" "$probe_subcommand" "${probe_args[@]}"
    ;;
  sudo-probe)
    probe_subcommand="${1:-}"
    [[ -n "$probe_subcommand" ]] || { usage >&2; exit 1; }
    shift || true
    validate_probe_invocation "$probe_subcommand" "$@" || {
      echo "Command denied" >&2
      exit 1
    }
    run_probe_as_runtime_user "$runtime_user" "$workspace_path" "$probe_subcommand" "$@"
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
