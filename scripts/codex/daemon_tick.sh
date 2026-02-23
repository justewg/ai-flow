#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CODEX_DIR="${ROOT_DIR}/.tmp/codex"

project_id="${PROJECT_ID:-PVT_kwHOAPt_Q84BPyyr}"
repo="${GITHUB_REPO:-justewg/planka}"
trigger_status="${TRIGGER_STATUS:-To Progress}"
target_status="${TARGET_STATUS:-In Progress}"
target_flow="${TARGET_FLOW:-In Progress}"

if ! git -C "${ROOT_DIR}" diff --quiet --ignore-submodules -- ||
  ! git -C "${ROOT_DIR}" diff --cached --quiet --ignore-submodules --; then
  echo "WAIT_DIRTY_WORKTREE_TRACKED=1"
  exit 0
fi

mkdir -p "$CODEX_DIR"

reply_probe_out="$("${ROOT_DIR}/scripts/codex/daemon_check_replies.sh" 2>&1)"
while IFS= read -r line; do
  [[ -z "$line" || "$line" == "NO_WAITING_USER_REPLY=1" ]] && continue
  echo "$line"
done <<< "$reply_probe_out"
if printf '%s' "$reply_probe_out" | grep -q '^WAIT_USER_REPLY=1'; then
  exit 0
fi

if [[ -s "${CODEX_DIR}/daemon_active_task.txt" ]]; then
  active_task_id="$(<"${CODEX_DIR}/daemon_active_task.txt")"
  echo "WAIT_ACTIVE_TASK_ID=$active_task_id"
  if [[ -s "${CODEX_DIR}/daemon_active_issue_number.txt" ]]; then
    echo "WAIT_ACTIVE_ISSUE_NUMBER=$(<"${CODEX_DIR}/daemon_active_issue_number.txt")"
  fi
  exit 0
fi

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

project_json="$(
  gh api graphql \
    -f query='
query($projectId: ID!, $fieldsFirst: Int!, $itemsFirst: Int!) {
  node(id: $projectId) {
    ... on ProjectV2 {
      fields(first: $fieldsFirst) {
        nodes {
          __typename
          ... on ProjectV2SingleSelectField {
            id
            name
            options {
              id
              name
            }
          }
        }
      }
      items(first: $itemsFirst) {
        nodes {
          id
          content {
            __typename
            ... on DraftIssue { title }
            ... on Issue { title number }
            ... on PullRequest { title number }
          }
          taskId: fieldValueByName(name: "Task ID") {
            __typename
            ... on ProjectV2ItemFieldTextValue { text }
          }
          status: fieldValueByName(name: "Status") {
            __typename
            ... on ProjectV2ItemFieldSingleSelectValue { name optionId }
          }
          flow: fieldValueByName(name: "Flow") {
            __typename
            ... on ProjectV2ItemFieldSingleSelectValue { name optionId }
          }
          priority: fieldValueByName(name: "Priority") {
            __typename
            ... on ProjectV2ItemFieldSingleSelectValue { name optionId }
          }
        }
      }
    }
  }
}
' \
    -f projectId="$project_id" \
    -F fieldsFirst=100 \
    -F itemsFirst=100
)"

matched_json="$(
  printf '%s' "$project_json" | jq -c --arg trigger "$trigger_status" '
    def norm: gsub("^\\s+|\\s+$";"") | ascii_downcase;
    .data.node as $project
    | (($project.fields.nodes[] | select(.name=="Status") | .options[] | select((.name | norm) == ($trigger | norm)) | .id) // null) as $trigger_option_id
    | [
      $project.items.nodes[]
      | {
          item_id: .id,
          content_type: (.content.__typename // ""),
          issue_number: (.content.number // ""),
          title: (.content.title // ""),
          task_id: (
            .taskId.text
            // (try ((.content.title // "") | capture("(?<id>PL-[0-9]{3})").id) catch "")
          ),
          status_name: (.status.name // ""),
          status_option_id: (.status.optionId // ""),
          flow: (.flow.name // ""),
          priority: (.priority.name // "")
        }
      | select(
          if $trigger_option_id == null
          then ((.status_name | norm) == ($trigger | norm))
          else (.status_option_id == $trigger_option_id)
          end
        )
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

matched_count="$(printf '%s' "$matched_json" | jq 'length')"
queue_json="$(printf '%s' "$matched_json" | jq -c '[.[] | select(.content_type == "Issue")]')"
queue_count="$(printf '%s' "$queue_json" | jq 'length')"

if (( matched_count > 0 && queue_count == 0 )); then
  echo "NO_ISSUE_TASKS_IN_TRIGGER_STATUS=$trigger_status"
  printf '%s' "$matched_json" | jq -r '.[] | "IGNORED_NON_ISSUE=\(.content_type)\t\(.title)"'
  exit 0
fi

if (( queue_count == 0 )); then
  echo "NO_TASKS_IN_TRIGGER_STATUS=$trigger_status"
  exit 0
fi

valid_queue_json="$(printf '%s' "$queue_json" | jq -c '[.[] | select(.task_id != "")]')"
valid_queue_count="$(printf '%s' "$valid_queue_json" | jq 'length')"

if (( valid_queue_count == 0 )); then
  echo "BLOCKED_TRIGGER_TASKS_WITHOUT_TASK_ID=$queue_count"
  printf '%s' "$queue_json" | jq -r '.[] | "QUEUE_ITEM_MISSING_TASK_ID=\(.priority)\t\(.title)"'
  exit 0
fi

if (( valid_queue_count > 1 )); then
  echo "BLOCKED_MULTIPLE_TRIGGER_TASKS=$valid_queue_count"
  printf '%s' "$valid_queue_json" | jq -r '.[] | "QUEUE_TASK=\(.task_id)\t\(.priority)\t\(.title)"'
  exit 0
fi

item_id="$(printf '%s' "$valid_queue_json" | jq -r '.[0].item_id')"
issue_number="$(printf '%s' "$valid_queue_json" | jq -r '.[0].issue_number')"
task_id="$(printf '%s' "$valid_queue_json" | jq -r '.[0].task_id')"
title="$(printf '%s' "$valid_queue_json" | jq -r '.[0].title')"

if [[ -z "$task_id" || "$task_id" == "null" ]]; then
  echo "Task in trigger status has no PL-xxx id in Task ID/title"
  exit 1
fi

if [[ -z "$item_id" || "$item_id" == "null" ]]; then
  echo "Task in trigger status has no project item id"
  exit 1
fi

if [[ -z "$issue_number" || "$issue_number" == "null" ]]; then
  echo "Task in trigger status has no issue number"
  exit 1
fi

"${ROOT_DIR}/scripts/codex/sync_branches.sh"
"${ROOT_DIR}/scripts/codex/project_set_status.sh" "$item_id" "$target_status" "$target_flow"

printf '%s\n' "$task_id" > "${CODEX_DIR}/daemon_active_task.txt"
printf '%s\n' "$item_id" > "${CODEX_DIR}/daemon_active_item_id.txt"
printf '%s\n' "$issue_number" > "${CODEX_DIR}/daemon_active_issue_number.txt"
printf '%s\n' "$task_id" > "${CODEX_DIR}/project_task_id.txt"
date -u '+%Y-%m-%dT%H:%M:%SZ' > "${CODEX_DIR}/daemon_last_claim_utc.txt"

echo "CLAIMED_TASK_ID=$task_id"
echo "CLAIMED_ITEM_ID=$item_id"
echo "CLAIMED_ISSUE_NUMBER=$issue_number"
echo "CLAIMED_TITLE=$title"
echo "CLAIMED_FROM_STATUS=$trigger_status"
echo "CLAIMED_TO_STATUS=$target_status"
