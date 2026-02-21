#!/usr/bin/env bash
set -euo pipefail

gh pr list \
  --repo justewg/planka \
  --state open \
  --base main \
  --head development \
  --json number,url,title \
  --jq '.'

