#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CODEX_DIR="${ROOT_DIR}/.tmp/codex"

project_id="${PROJECT_ID:-PVT_kwHOAPt_Q84BPyyr}"
project_number="${PROJECT_NUMBER:-2}"
project_owner="${PROJECT_OWNER:-@me}"
project_items_limit="${PROJECT_ITEMS_LIMIT:-200}"
repo="${GITHUB_REPO:-justewg/planka}"
trigger_status="${TRIGGER_STATUS:-Todo}"
target_status="${TARGET_STATUS:-In Progress}"
target_flow="${TARGET_FLOW:-In Progress}"

emit_lines() {
  local text="$1"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "$line"
  done <<< "$text"
}

is_github_network_error() {
  local text="$1"
  printf '%s' "$text" | grep -Eiq \
    'error connecting to api\.github\.com|could not resolve host: api\.github\.com|could not resolve host: github\.com|could not resolve hostname github\.com|temporary failure in name resolution|connection timed out|operation timed out|tls handshake timeout|failed to connect'
}

run_gh_retry_capture() {
  local out=""
  local err_file
  err_file="$(mktemp "${CODEX_DIR}/gh_retry_err.XXXXXX")"
  if out="$("${ROOT_DIR}/scripts/codex/gh_retry.sh" "$@" 2>"$err_file")"; then
    if [[ -s "$err_file" ]]; then
      cat "$err_file" >&2
    fi
    rm -f "$err_file"
    printf '%s' "$out"
    return 0
  else
    local rc=$?
    if [[ -s "$err_file" ]]; then
      cat "$err_file" >&2
    fi
    rm -f "$err_file"
    printf '%s\n' "$out" >&2
    return "$rc"
  fi
}

if ! git -C "${ROOT_DIR}" diff --quiet --ignore-submodules -- ||
  ! git -C "${ROOT_DIR}" diff --cached --quiet --ignore-submodules --; then
  echo "WAIT_DIRTY_WORKTREE_TRACKED=1"
  exit 0
fi

mkdir -p "$CODEX_DIR"

# Сначала пытаемся доставить отложенные действия в GitHub (outbox).
outbox_out="$("${ROOT_DIR}/scripts/codex/github_outbox.sh" flush 2>&1 || true)"
if [[ -n "$outbox_out" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == "OUTBOX_EMPTY=1" ]] && continue
    echo "$line"
  done <<< "$outbox_out"
fi

pending_actions="$(
  "${ROOT_DIR}/scripts/codex/github_outbox.sh" count 2>/dev/null |
    awk -F= '/^OUTBOX_PENDING_COUNT=/{print $2}' |
    tail -n1
)"
if [[ -n "$pending_actions" && "$pending_actions" != "0" ]]; then
  echo "WAIT_GITHUB_PENDING_ACTIONS=$pending_actions"
fi

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
  active_issue_number=""
  if [[ -s "${CODEX_DIR}/daemon_active_issue_number.txt" ]]; then
    active_issue_number="$(<"${CODEX_DIR}/daemon_active_issue_number.txt")"
    echo "WAIT_ACTIVE_ISSUE_NUMBER=$active_issue_number"
  fi

  if [[ -n "$active_issue_number" ]]; then
    exec_out="$("${ROOT_DIR}/scripts/codex/executor_tick.sh" "$active_task_id" "$active_issue_number" 2>&1)"
    emit_lines "$exec_out"
  else
    echo "BLOCKED_ACTIVE_TASK_WITHOUT_ISSUE=1"
  fi
  exit 0
fi

if health_out="$("${ROOT_DIR}/scripts/codex/github_health_check.sh" 2>&1)"; then
  :
else
  rc=$?
  emit_lines "$health_out"
  if [[ "$rc" -eq 75 ]]; then
    echo "WAIT_GITHUB_API_UNSTABLE=1"
    echo "WAIT_GITHUB_STAGE=PRE_CLAIM"
    exit 0
  fi
  exit "$rc"
fi

open_prs_json=""
if open_prs_json="$(
  run_gh_retry_capture \
    gh pr list \
    --repo "$repo" \
    --state open \
    --base main \
    --head development \
    --json number,title,url \
    --jq '.'
)"; then
  :
else
  rc=$?
  if [[ "$rc" -eq 75 ]]; then
    echo "WAIT_GITHUB_API_UNSTABLE=1"
    echo "WAIT_GITHUB_STAGE=OPEN_PR_CHECK"
    exit 0
  fi
  exit "$rc"
fi

open_pr_count="$(printf '%s' "$open_prs_json" | jq 'length')"
if (( open_pr_count > 0 )); then
  echo "WAIT_OPEN_PR_COUNT=$open_pr_count"
  printf '%s' "$open_prs_json" | jq -r '.[] | "OPEN_PR=#\(.number) \(.title) \(.url)"'
  exit 0
fi

project_json=""
if project_json="$(
  run_gh_retry_capture \
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
)"; then
  :
else
  rc=$?
  if [[ "$rc" -eq 75 ]]; then
    echo "WAIT_GITHUB_API_UNSTABLE=1"
    echo "WAIT_GITHUB_STAGE=PROJECT_QUERY"
    exit 0
  fi
  exit "$rc"
fi

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
            . as $item
            | (($item.taskId.text // "") | gsub("^\\s+|\\s+$";"")) as $task_field
            | if $task_field != "" then $task_field
              else (
                ([ (($item.content.title // "") | capture("(?<id>PL-[0-9]{3})").id) ] | first // "") as $pl_from_title
                | if $pl_from_title != "" then $pl_from_title
                  else (
                    if ($item.content.__typename // "") == "Issue" and ($item.content.number != null)
                    then ("ISSUE-" + (($item.content.number | tostring)))
                    else ""
                    end
                  )
                  end
              )
              end
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
      | .num = ((try (.issue_number | tonumber) catch 999999))
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
  fallback_items_json=""
  if fallback_items_json="$(
    run_gh_retry_capture \
      gh project item-list "$project_number" \
      --owner "$project_owner" \
      --limit "$project_items_limit" \
      --format json \
      --jq '.'
  )"; then
    :
  else
    rc=$?
    if [[ "$rc" -eq 75 ]]; then
      echo "WAIT_GITHUB_API_UNSTABLE=1"
      echo "WAIT_GITHUB_STAGE=PROJECT_ITEM_LIST_FALLBACK"
      exit 0
    fi
    exit "$rc"
  fi

  fallback_queue_json="$(
    printf '%s' "$fallback_items_json" | jq -c --arg trigger "$trigger_status" '
      def norm: gsub("^\\s+|\\s+$";"") | ascii_downcase;
      [
        .items[]
        | {
            item_id: .id,
            content_type: (.content.type // ""),
            issue_number: (.content.number // ""),
            title: (.title // .content.title // ""),
            task_id: (
              . as $item
              | (($item."task ID" // "") | gsub("^\\s+|\\s+$";"")) as $task_field
              | if $task_field != "" then $task_field
                else (
                  ([ (($item.title // $item.content.title // "") | capture("(?<id>PL-[0-9]{3})").id) ] | first // "") as $pl_from_title
                  | if $pl_from_title != "" then $pl_from_title
                    else (
                      if ($item.content.type // "") == "Issue" and ($item.content.number != null)
                      then ("ISSUE-" + (($item.content.number | tostring)))
                      else ""
                      end
                    )
                    end
                )
                end
            ),
            status_name: (.status // ""),
            flow: (.flow // ""),
            priority: (.priority // "")
          }
        | select((.status_name | norm) == ($trigger | norm))
        | .pri_w = (
            if .priority == "P0" then 0
            elif .priority == "P1" then 1
            elif .priority == "P2" then 2
            elif .priority == "P3" then 3
            else 9
            end
          )
        | .num = ((try (.issue_number | tonumber) catch 999999))
      ]
      | sort_by(.pri_w, .num)
      | [.[] | select(.content_type == "Issue")]
    '
  )"

  fallback_queue_count="$(printf '%s' "$fallback_queue_json" | jq 'length')"
  if (( fallback_queue_count == 0 )); then
    echo "NO_TASKS_IN_TRIGGER_STATUS=$trigger_status"
    exit 0
  fi

  echo "FALLBACK_PROJECT_ITEM_LIST_USED=1"
  queue_json="$fallback_queue_json"
  queue_count="$fallback_queue_count"
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
  echo "Task in trigger status has no resolvable task id"
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

if sync_out="$("${ROOT_DIR}/scripts/codex/sync_branches.sh" 2>&1)"; then
  :
else
  rc=$?
  emit_lines "$sync_out"
  if is_github_network_error "$sync_out"; then
    echo "WAIT_GITHUB_API_UNSTABLE=1"
    echo "WAIT_GITHUB_STAGE=SYNC_BRANCHES"
    exit 0
  fi
  if [[ "$rc" -eq 78 ]] ||
    printf '%s' "$sync_out" | grep -Eq 'BRANCH_SYNC_CONFLICT=1|Not possible to fast-forward, aborting.|Automatic merge failed'; then
    echo "WAIT_BRANCH_SYNC_REQUIRED=1"
    echo "WAIT_BRANCH_STAGE=SYNC_BRANCHES"
    exit 0
  fi
  exit "$rc"
fi
emit_lines "$sync_out"

if status_out="$("${ROOT_DIR}/scripts/codex/project_set_status.sh" "$item_id" "$target_status" "$target_flow" 2>&1)"; then
  :
else
  rc=$?
  emit_lines "$status_out"
  if is_github_network_error "$status_out"; then
    echo "WAIT_GITHUB_API_UNSTABLE=1"
    echo "WAIT_GITHUB_STAGE=PROJECT_STATUS_UPDATE"
    exit 0
  fi
  exit "$rc"
fi
emit_lines "$status_out"

printf '%s\n' "$task_id" > "${CODEX_DIR}/daemon_active_task.txt"
printf '%s\n' "$item_id" > "${CODEX_DIR}/daemon_active_item_id.txt"
printf '%s\n' "$issue_number" > "${CODEX_DIR}/daemon_active_issue_number.txt"
printf '%s\n' "$task_id" > "${CODEX_DIR}/project_task_id.txt"
"${ROOT_DIR}/scripts/codex/executor_reset.sh" >/dev/null
date -u '+%Y-%m-%dT%H:%M:%SZ' > "${CODEX_DIR}/daemon_last_claim_utc.txt"

echo "CLAIMED_TASK_ID=$task_id"
echo "CLAIMED_ITEM_ID=$item_id"
echo "CLAIMED_ISSUE_NUMBER=$issue_number"
echo "CLAIMED_TITLE=$title"
echo "CLAIMED_FROM_STATUS=$trigger_status"
echo "CLAIMED_TO_STATUS=$target_status"
