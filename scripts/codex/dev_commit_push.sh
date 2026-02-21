#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 \"commit message\" <path...>"
  exit 1
fi

message="$1"
shift

git add "$@"
git commit -m "$message"
git push origin development

