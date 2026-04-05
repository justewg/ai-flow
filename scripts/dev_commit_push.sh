#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
push_branch_override="${FLOW_HEAD_BRANCH:-}"
codex_load_flow_env

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 \"commit message\" <path...>"
  exit 1
fi

strip_quotes() {
  local value="$1"
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"
  printf '%s' "$value"
}

read_key_from_env_file() {
  local file_path="$1"
  local key="$2"
  [[ -f "$file_path" ]] || return 1

  local raw
  raw="$(grep -E "^${key}=" "$file_path" | tail -n1 | cut -d'=' -f2- || true)"
  [[ -n "$raw" ]] || return 1
  strip_quotes "$raw"
}

resolve_identity_value() {
  local key="$1"
  local current="$2"
  if [[ -n "$current" ]]; then
    printf '%s' "$current"
    return 0
  fi

  local env_file value
  for env_file in "${ROOT_DIR}/.env" "${ROOT_DIR}/.env.deploy"; do
    value="$(read_key_from_env_file "$env_file" "$key" || true)"
    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return 0
    fi
  done

  printf ''
}

message="$1"
shift

author_name="$(resolve_identity_value "CODEX_GIT_AUTHOR_NAME" "${CODEX_GIT_AUTHOR_NAME:-}")"
author_email="$(resolve_identity_value "CODEX_GIT_AUTHOR_EMAIL" "${CODEX_GIT_AUTHOR_EMAIL:-}")"
committer_name="$(resolve_identity_value "CODEX_GIT_COMMITTER_NAME" "${CODEX_GIT_COMMITTER_NAME:-}")"
committer_email="$(resolve_identity_value "CODEX_GIT_COMMITTER_EMAIL" "${CODEX_GIT_COMMITTER_EMAIL:-}")"

if [[ -z "$author_name" ]]; then
  author_name="PLANKA Codex Agent"
fi
if [[ -z "$author_email" ]]; then
  author_email="codex-agent@local"
fi
if [[ -z "$committer_name" ]]; then
  committer_name="$author_name"
fi
if [[ -z "$committer_email" ]]; then
  committer_email="$author_email"
fi

push_branch="${push_branch_override:-${FLOW_HEAD_BRANCH:-}}"
if [[ -z "$push_branch" ]]; then
  push_branch="$(git -C "${ROOT_DIR}" branch --show-current 2>/dev/null || true)"
fi
if [[ -z "$push_branch" ]]; then
  echo "Cannot determine push branch"
  exit 1
fi

git -C "${ROOT_DIR}" add -f "$@"
GIT_AUTHOR_NAME="$author_name" \
GIT_AUTHOR_EMAIL="$author_email" \
GIT_COMMITTER_NAME="$committer_name" \
GIT_COMMITTER_EMAIL="$committer_email" \
git -C "${ROOT_DIR}" commit -m "$message"
git -C "${ROOT_DIR}" push origin "$push_branch"
