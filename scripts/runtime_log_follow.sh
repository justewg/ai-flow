#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <daemon|watchdog|executor|d|w|e> [lines]"
  exit 1
fi

target_raw="$1"
lines="${2:-50}"

if ! [[ "$lines" =~ ^[0-9]+$ ]] || (( lines <= 0 )); then
  echo "lines must be a positive integer"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

case "$(printf '%s' "$target_raw" | tr '[:upper:]' '[:lower:]')" in
  daemon|d)
    log_name="daemon.log"
    ;;
  watchdog|w)
    log_name="watchdog.log"
    ;;
  executor|e)
    log_name="executor.log"
    ;;
  *)
    echo "Unknown target: $target_raw (expected daemon|watchdog|executor|d|w|e)"
    exit 1
    ;;
esac

log_dir="$(codex_resolve_flow_runtime_log_dir)"
log_file="${log_dir}/${log_name}"

if [[ ! -f "$log_file" ]]; then
  echo "Log file not found: $log_file"
  exit 1
fi

exec tail -n "$lines" -f "$log_file"
