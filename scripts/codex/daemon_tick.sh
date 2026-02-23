#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

project_number="${PROJECT_NUMBER:-2}"
project_owner="${PROJECT_OWNER:-justewg}"
repo="${GITHUB_REPO:-justewg/planka}"
trigger_status="${TRIGGER_STATUS:-To Progress}"
target_status="${TARGET_STATUS:-In Progress}"
target_flow="${TARGET_FLOW:-In Progress}"

open_prs_json="$(
  gh pr list \
    --repo "$repo" \
    --state open \
    --base main \
    --head development \
    --json number,title,url \
    --jq '.'
)"
open_pr_count="$(printf '%s' "$open_prs_json" | jq 'length')"
if (( open_pr_count > 0 )); then
  echo "WAIT_OPEN_PR_COUNT=$open_pr_count"
  printf '%s' "$open_prs_json" | jq -r '.[] | "OPEN_PR=#\(.number) \(.title) \(.url)"'
  exit 0
fi

if ! git -C "${ROOT_DIR}" diff --quiet --ignore-submodules -- ||
  ! git -C "${ROOT_DIR}" diff --cached --quiet --ignore-submodules --; then
  echo "WAIT_DIRTY_WORKTREE_TRACKED=1"
  exit 0
fi

project_json="$(
  gh project item-list "$project_number" \
    --owner "$project_owner" \
    --limit 100 \
    --format json
)"

queue_json="$(
  printf '%s' "$project_json" | jq -c --arg status "$trigger_status" '
    [
      .items[]
      | {
          item_id: .id,
          task_id: (."task ID" // ""),
          title: (.title // ""),
          status: (.status // ""),
          flow: (.flow // ""),
          priority: (.priority // "")
        }
      | select(.status == $status)
      | .pri_w = (
          if .priority == "P0" then 0
          elif .priority == "P1" then 1
          elif .priority == "P2" then 2
          elif .priority == "P3" then 3
          else 9
          end
        )
      | .num = (
          (try (.task_id | capture("PL-(?<n>[0-9]+)").n) catch "999999")
          | tonumber
        )
    ]
    | sort_by(.pri_w, .num)
  '
)"

queue_count="$(printf '%s' "$queue_json" | jq 'length')"
if (( queue_count == 0 )); then
  echo "NO_TASKS_IN_TRIGGER_STATUS=$trigger_status"
  exit 0
fi

if (( queue_count > 1 )); then
  echo "BLOCKED_MULTIPLE_TRIGGER_TASKS=$queue_count"
  printf '%s' "$queue_json" | jq -r '.[] | "QUEUE_TASK=\(.task_id)\t\(.priority)\t\(.title)"'
  exit 0
fi

task_id="$(printf '%s' "$queue_json" | jq -r '.[0].task_id')"
title="$(printf '%s' "$queue_json" | jq -r '.[0].title')"

if [[ -z "$task_id" || "$task_id" == "null" ]]; then
  echo "Task in trigger status has no Task ID"
  exit 1
fi

"${ROOT_DIR}/scripts/codex/sync_branches.sh"
"${ROOT_DIR}/scripts/codex/project_set_status.sh" "$task_id" "$target_status" "$target_flow"

mkdir -p "${ROOT_DIR}/.tmp/codex"
printf '%s\n' "$task_id" > "${ROOT_DIR}/.tmp/codex/daemon_active_task.txt"
printf '%s\n' "$task_id" > "${ROOT_DIR}/.tmp/codex/project_task_id.txt"
date -u '+%Y-%m-%dT%H:%M:%SZ' > "${ROOT_DIR}/.tmp/codex/daemon_last_claim_utc.txt"

echo "CLAIMED_TASK_ID=$task_id"
echo "CLAIMED_TITLE=$title"
echo "CLAIMED_FROM_STATUS=$trigger_status"
echo "CLAIMED_TO_STATUS=$target_status"
