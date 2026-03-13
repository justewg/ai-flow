#!/usr/bin/env bash

BOOTSTRAP_ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BOOTSTRAP_SCRIPTS_DIR="$(cd "${BOOTSTRAP_ENV_DIR}/.." && pwd -P)"
BOOTSTRAP_CALLER_SOURCE="${BASH_SOURCE[1]:-}"
BOOTSTRAP_CALLER_DIR=""

normalize_existing_dir() {
  local candidate="${1:-}"
  [[ -n "$candidate" && -d "$candidate" ]] || return 1
  cd "$candidate" && pwd -P
}

if [[ -n "$BOOTSTRAP_CALLER_SOURCE" ]]; then
  BOOTSTRAP_CALLER_DIR="$(cd "$(dirname "$BOOTSTRAP_CALLER_SOURCE")" && pwd -P)"
fi

if [[ -z "${ROOT_DIR:-}" ]]; then
  if [[ "$BOOTSTRAP_CALLER_DIR" == */.flow/shared/scripts ]]; then
    ROOT_DIR="$(cd "${BOOTSTRAP_CALLER_DIR}/../../.." && pwd -P)"
  elif [[ "$BOOTSTRAP_CALLER_DIR" == */.flow/scripts ]]; then
    ROOT_DIR="$(cd "${BOOTSTRAP_CALLER_DIR}/../.." && pwd -P)"
  else
    current_dir="$(normalize_existing_dir "${PWD:-}" 2>/dev/null || true)"
    while [[ -n "$current_dir" ]]; do
      if [[ -d "${current_dir}/.git" || -d "${current_dir}/.flow/config" || -L "${current_dir}/.flow/shared" || -d "${current_dir}/.flow/shared" ]]; then
        ROOT_DIR="$current_dir"
        break
      fi
      parent_dir="$(normalize_existing_dir "${current_dir}/.." 2>/dev/null || true)"
      [[ "$parent_dir" != "$current_dir" ]] || break
      current_dir="$parent_dir"
    done
  fi
fi

if [[ -z "${ROOT_DIR:-}" ]]; then
  ROOT_DIR="$(cd "${BOOTSTRAP_SCRIPTS_DIR}/../../.." && pwd -P)"
fi

export ROOT_DIR

# shellcheck source=./resolve_config.sh
source "${BOOTSTRAP_ENV_DIR}/resolve_config.sh"

CODEX_SHARED_SCRIPTS_DIR="$(codex_resolve_repo_flow_shared_scripts_dir)"
export CODEX_SHARED_SCRIPTS_DIR
