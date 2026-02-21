#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <pr-number>"
  exit 1
fi

pr_number="$1"

gh pr view "$pr_number" \
  --repo justewg/planka \
  --json number,state,url,title,headRefName,baseRefName \
  --jq '.'

