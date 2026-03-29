#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
codex_resolve_flow_config

git fetch origin
git checkout "$FLOW_BASE_BRANCH"
git pull --ff-only origin "$FLOW_BASE_BRANCH"
git checkout "$FLOW_HEAD_BRANCH"
git pull --ff-only origin "$FLOW_HEAD_BRANCH"

# Fast-forward only is too strict when base branch advances via merge commits.
# If base is not yet an ancestor of head, do a regular merge.
if git merge-base --is-ancestor "$FLOW_BASE_BRANCH" "$FLOW_HEAD_BRANCH"; then
  echo "SYNC_BASE_ALREADY_INCLUDED_IN_HEAD=1"
else
  if ! git merge --no-edit "$FLOW_BASE_BRANCH"; then
    echo "BRANCH_SYNC_CONFLICT=1"
    echo "BRANCH_SYNC_STAGE=MERGE_BASE_INTO_HEAD"
    exit 78
  fi
fi

git submodule sync --recursive
git submodule update --init --recursive -- .flow/shared

git push origin "$FLOW_HEAD_BRANCH"
git status --short --branch
