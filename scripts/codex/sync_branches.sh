#!/usr/bin/env bash
set -euo pipefail

git fetch origin
git checkout main
git pull --ff-only origin main
git checkout development

# Fast-forward only is too strict when `main` advances via merge commits.
# If `main` is not yet an ancestor of `development`, do a regular merge.
if git merge-base --is-ancestor main development; then
  echo "SYNC_MAIN_ALREADY_INCLUDED_IN_DEVELOPMENT=1"
else
  if ! git merge --no-edit main; then
    echo "BRANCH_SYNC_CONFLICT=1"
    echo "BRANCH_SYNC_STAGE=MERGE_MAIN_INTO_DEVELOPMENT"
    exit 78
  fi
fi

git push origin development
git status --short --branch
