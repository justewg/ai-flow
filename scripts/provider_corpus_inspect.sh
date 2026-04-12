#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

NODE_BIN="${NODE_BIN:-node}"
state_dir=""
args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --state-dir)
      [[ $# -ge 2 ]] || { echo "Missing value for --state-dir" >&2; exit 1; }
      state_dir="$2"
      args+=("$1" "$2")
      shift 2
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

if [[ -z "$state_dir" ]]; then
  state_dir="$(codex_resolve_state_dir)"
  args=("--state-dir" "$state_dir" "${args[@]}")
fi

exec "$NODE_BIN" "${SCRIPT_DIR}/../runtime-v2/bin/provider_corpus_inspect.js" "${args[@]}"
