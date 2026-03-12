#!/usr/bin/env bash

BOOTSTRAP_ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_SCRIPTS_DIR="$(cd "${BOOTSTRAP_ENV_DIR}/.." && pwd)"
BOOTSTRAP_CALLER_SOURCE="${BASH_SOURCE[1]:-}"
BOOTSTRAP_CALLER_DIR=""

if [[ -n "$BOOTSTRAP_CALLER_SOURCE" ]]; then
  BOOTSTRAP_CALLER_DIR="$(cd "$(dirname "$BOOTSTRAP_CALLER_SOURCE")" && pwd)"
fi

if [[ -z "${ROOT_DIR:-}" ]]; then
  if [[ "$BOOTSTRAP_CALLER_DIR" == */.flow/shared/scripts ]]; then
    ROOT_DIR="$(cd "${BOOTSTRAP_CALLER_DIR}/../../.." && pwd)"
  elif [[ "$BOOTSTRAP_CALLER_DIR" == */.flow/scripts ]]; then
    ROOT_DIR="$(cd "${BOOTSTRAP_CALLER_DIR}/../.." && pwd)"
  else
    current_dir="${PWD:-}"
    while [[ -n "$current_dir" ]]; do
      if [[ -d "${current_dir}/.git" || -d "${current_dir}/.flow/config" || -L "${current_dir}/.flow/shared" ]]; then
        ROOT_DIR="$current_dir"
        break
      fi
      parent_dir="$(cd "${current_dir}/.." && pwd)"
      [[ "$parent_dir" != "$current_dir" ]] || break
      current_dir="$parent_dir"
    done
  fi
fi

if [[ -z "${ROOT_DIR:-}" ]]; then
  ROOT_DIR="$(cd "${BOOTSTRAP_SCRIPTS_DIR}/../../.." && pwd)"
fi

export ROOT_DIR

# shellcheck source=./resolve_config.sh
source "${BOOTSTRAP_ENV_DIR}/resolve_config.sh"

CODEX_SHARED_SCRIPTS_DIR="$(codex_resolve_repo_flow_shared_scripts_dir)"
export CODEX_SHARED_SCRIPTS_DIR
