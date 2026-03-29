#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <command-name> <real-command> [args...]"
  exit 1
fi

command_name="$1"
real_command="$2"
shift 2

violations_file="${MICRO_PROFILE_VIOLATIONS_FILE:-}"
full_command="${command_name}"
if [[ $# -gt 0 ]]; then
  full_command="${command_name} $*"
fi

allow_command="0"
case "$command_name" in
  git)
    if [[ "${1:-}" == "status" && "${2:-}" == "--short" ]]; then
      allow_command="1"
    fi
    ;;
  true|pwd)
    allow_command="1"
    ;;
esac

if [[ "$allow_command" != "1" ]]; then
  if [[ -n "$violations_file" ]]; then
    jq -nc \
      --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
      --arg command "$command_name" \
      --arg fullCommand "$full_command" \
      '{ts:$ts, command:$command, fullCommand:$fullCommand}' >> "$violations_file"
    fi
  echo "MICRO_PROFILE_COMMAND_BLOCKED=${full_command}" >&2
  exit 126
fi

exec "$real_command" "$@"
